import 'package:flutter/material.dart';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_home.dart';
import '../../core/cloud_api/cloud_report_preview.dart';
import '../../core/cloud_api/cloud_report_delivery.dart';
import '../../core/cloud_auth/cloud_auxiliary_domain_lifecycle.dart';
import '../design/report_delivery_domain_adapter.dart';
import '../design/report_preview_domain_repository.dart';

class CloudReportPreviewScreen extends StatefulWidget {
  const CloudReportPreviewScreen({
    super.key,
    required this.api,
    required this.home,
    this.lifecycle,
    this.accountId,
  });
  final CloudApiClient api;
  final CloudHome home;
  final CloudAuxiliaryDomainLifecycle? lifecycle;
  final String? accountId;

  @override
  State<CloudReportPreviewScreen> createState() =>
      _CloudReportPreviewScreenState();
}

class _CloudReportPreviewScreenState extends State<CloudReportPreviewScreen> {
  List<CloudAppliance>? _appliances;
  final Set<String> _selected = {};
  CloudReportPreview? _preview;
  ReportPreviewDomainSnapshot? _scopedPreview;
  String? _error;
  bool _busy = false;
  String _key = newCloudIdempotencyKey();
  final TextEditingController _recipients = TextEditingController();
  bool _approved = false;
  String? _currentDeliveryId;
  String? _deliveryStatus;
  _DeliveryAttempt? _attempt;

  bool get _hasVerifiedScope {
    final lifecycle = widget.lifecycle;
    if (lifecycle == null) return true;
    final accountId = widget.accountId;
    return accountId != null &&
        lifecycle.isVerifiedScope(accountId, widget.home.id);
  }

  Future<CloudReportPreview?> _readPreview(
    String previewId,
    Set<String> owned,
  ) async {
    final lifecycle = widget.lifecycle;
    if (lifecycle == null) {
      return widget.api.reportPreview(widget.home.id, previewId, owned);
    }
    if (!_hasVerifiedScope) return null;
    final snapshot = await lifecycle.reportPreview(
      homeId: widget.home.id,
      previewId: previewId,
      ownedApplianceIds: owned,
    );
    if (!_hasVerifiedScope) return null;
    _scopedPreview = snapshot;
    return snapshot?.preview;
  }

  @override
  void dispose() {
    widget.lifecycle?.scopeChanges.removeListener(_onScopeChanged);
    _recipients.dispose();
    super.dispose();
  }

  void _resetApproval({bool clearCurrentDelivery = true}) {
    _approved = false;
    _attempt = null;
    if (clearCurrentDelivery) {
      _currentDeliveryId = null;
      _deliveryStatus = null;
    }
  }

  @override
  void initState() {
    super.initState();
    widget.lifecycle?.scopeChanges.addListener(_onScopeChanged);
    _load();
  }

  void _onScopeChanged() {
    if (!mounted) return;
    setState(() {
      if (!_hasVerifiedScope) {
        _appliances = null;
        _selected.clear();
        _preview = null;
        _scopedPreview = null;
        _resetApproval();
        _busy = false;
        _error = null;
      }
    });
  }

  Future<void> _load() async {
    if (!_hasVerifiedScope) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final appliances = await widget.api.appliances(widget.home.id);
      if (!mounted || !_hasVerifiedScope) return;
      setState(() {
        _appliances = appliances;
        _selected.removeWhere((id) => !appliances.any((a) => a.id == id));
      });
    } catch (_) {
      if (mounted && _hasVerifiedScope) {
        setState(
          () => _error = 'Could not load this home’s appliances. Try again.',
        );
      }
    } finally {
      if (mounted && _hasVerifiedScope) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (!_hasVerifiedScope ||
        _appliances == null ||
        _selected.isEmpty ||
        _selected.length > 25) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
      _scopedPreview = null;
      _resetApproval();
    });
    try {
      final owned = _appliances!.map((a) => a.id.toLowerCase()).toSet();
      final selected = _selected.toList()..sort();
      final lifecycle = widget.lifecycle;
      final CloudReportPreview? preview;
      if (lifecycle == null) {
        final created = await widget.api.createReportPreview(
          widget.home.id,
          selected,
          owned,
          idempotencyKey: _key,
        );
        preview = await _readPreview(created.id, owned);
      } else {
        final snapshot = await lifecycle.createReportPreview(
          homeId: widget.home.id,
          applianceIds: selected,
          ownedApplianceIds: owned,
          idempotencyKey: _key,
        );
        _scopedPreview = snapshot;
        preview = snapshot?.preview;
      }
      if (preview == null || !mounted || !_hasVerifiedScope) return;
      if (mounted) {
        setState(() {
          _preview = preview;
          _key = newCloudIdempotencyKey();
          _resetApproval();
        });
      }
    } on CloudApiException catch (error) {
      if (!mounted || !_hasVerifiedScope) return;
      setState(
        () => _error = switch (error.statusCode) {
          401 || 403 => 'Cloud sign-in is required to review this report.',
          404 => 'This home or appliance is no longer available. Refresh appliances.',
          409 => 'This request key was used for another selection. Change the selection and try again.',
          _ => 'Could not confirm the preview. Retry the same selection or refresh the home.',
        },
      );
    } catch (_) {
      if (mounted && _hasVerifiedScope) {
        setState(
          () => _error = 'Could not confirm the preview. Retry the same selection or refresh the home.',
        );
      }
    } finally {
      if (mounted && _hasVerifiedScope) setState(() => _busy = false);
    }
  }

  Future<void> _refreshPreview() async {
    final current = _preview;
    if (!_hasVerifiedScope || current == null || _appliances == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final owned = _appliances!.map((a) => a.id.toLowerCase()).toSet();
      final preview = await _readPreview(current.id, owned);
      if (preview == null || !mounted || !_hasVerifiedScope) return;
      if (mounted) {
        setState(() {
          final sameSnapshot =
              preview.snapshotSha256 == current.snapshotSha256;
          if (preview.isStale || !sameSnapshot) {
            _resetApproval(clearCurrentDelivery: !sameSnapshot);
          }
          _preview = preview;
          final delivery = preview.latestDelivery;
          _deliveryStatus = delivery?.id != _currentDeliveryId
              ? null
              : switch (delivery?.state) {
                  'sent' => 'Email sent',
                  'canceled' => 'Email failed, try again later.',
                  _ => null,
                };
        });
      }
    } catch (_) {
      if (mounted && _hasVerifiedScope) {
        setState(() {
          _preview = null;
          _scopedPreview = null;
          _resetApproval();
          _error = 'Could not confirm the latest preview status. Create a new preview.';
        });
      }
    } finally {
      if (mounted && _hasVerifiedScope) setState(() => _busy = false);
    }
  }

  Future<void> _queueDelivery() async {
    final current = _preview;
    if (!_hasVerifiedScope ||
        current == null ||
        current.isStale ||
        !_approved ||
        _appliances == null) {
      return;
    }
    final recipients = validatedReportRecipients(_recipients.text);
    if (recipients == null) {
      setState(
        () => _error = 'Enter 1 to 5 distinct, valid email addresses, separated by commas or lines.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var attempt = _attempt;
      if (attempt == null) {
        // Recheck the selected owner home and the exact preview immediately before approval.
        final homes = await widget.api.homes();
        if (!mounted || !_hasVerifiedScope) return;
        if (!homes.any((home) => home.id == widget.home.id)) {
          throw const FormatException('Selected home is no longer available');
        }
        final owned = _appliances!.map((a) => a.id.toLowerCase()).toSet();
        final fresh = await _readPreview(current.id, owned);
        if (!mounted || !_hasVerifiedScope || fresh == null) return;
        setState(() => _preview = fresh);
        if (fresh.isStale || fresh.snapshotSha256 != current.snapshotSha256) {
          setState(() {
            _resetApproval();
            _error = 'This preview changed or expired. Create a new preview and approve it again.';
          });
          return;
        }
        attempt = _DeliveryAttempt(
          current.id,
          current.snapshotSha256,
          recipients,
          newCloudIdempotencyKey(),
        );
        _attempt = attempt;
      }
      if (!_hasVerifiedScope) return;
      final lifecycle = widget.lifecycle;
      final CloudReportDelivery delivery;
      if (lifecycle == null) {
        delivery = await widget.api.queueReportDelivery(
          widget.home.id,
          attempt.previewId,
          attempt.digest,
          attempt.recipients,
          idempotencyKey: attempt.key,
        );
      } else {
        final snapshot = _scopedPreview;
        if (snapshot == null) return;
        final result = await lifecycle.queueReportDelivery(
          preview: snapshot,
          explicitlyApproved: _approved,
          approvedSnapshotSha256: attempt.digest,
          recipients: attempt.recipients.join(','),
          ownedApplianceIds: _appliances!
              .map((a) => a.id.toLowerCase())
              .toSet(),
          idempotencyKey: attempt.key,
        );
        if (result.status == ReportDeliveryStatus.contextChanged ||
            !_hasVerifiedScope) {
          return;
        }
        if (result.status != ReportDeliveryStatus.queued ||
            result.delivery == null) {
          setState(() {
            _resetApproval();
            _error = 'This preview changed or expired. Create a new preview and approve it again.';
          });
          return;
        }
        delivery = result.delivery!;
      }
      if (mounted && _hasVerifiedScope) {
        setState(() {
          _currentDeliveryId = delivery.id;
          _deliveryStatus = null;
          _attempt = null;
          _approved = false;
        });
      }
    } on CloudApiException catch (error) {
      if (!mounted || !_hasVerifiedScope) return;
      setState(() {
        if (error.code == 'preview_stale' ||
            error.code == 'snapshot_mismatch' ||
            error.statusCode == 404) {
          _preview = null;
          _resetApproval();
        }
        _error = switch (error.code) {
          'preview_stale' || 'snapshot_mismatch' => 'This preview changed or expired. Create a new preview and approve it again.',
          'idempotency_key_reuse' => 'This request key was used for different recipients. Change recipients and approve again.',
          'delivery_rate_limited' =>
            'The manual report request limit was reached. Try later.',
          _ => switch (error.statusCode) {
            401 || 403 => 'Cloud sign-in is required to request this report.',
            404 => 'This home or preview is no longer available. Create a new preview.',
            _ => 'Could not confirm the request. Retry unchanged to safely check the same request.',
          },
        };
      });
    } catch (_) {
      if (mounted && _hasVerifiedScope) {
        setState(
          () => _error = 'Could not confirm the request. Retry unchanged to safely check the same request.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => !_hasVerifiedScope
      ? const SizedBox.shrink()
      : Scaffold(
          appBar: AppBar(title: const Text('Private report preview')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      widget.home.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose 1 to 25 appliances for a private 24-hour snapshot. This does not send a report.',
                    ),
                    if (_busy)
                      const LinearProgressIndicator(key: Key('reportLoading')),
                    if (_error != null)
                      Text(_error!, key: const Key('reportError')),
                    if (_appliances == null)
                      TextButton(
                        onPressed: _busy ? null : _load,
                        child: const Text('Retry appliances'),
                      ),
                    if (_appliances != null && _appliances!.isEmpty)
                      const Text('Add a cloud appliance to this home first.'),
                    if (_appliances != null)
                      for (final appliance in _appliances!)
                        CheckboxListTile(
                          key: Key('reportAppliance-${appliance.id}'),
                          title: Text(appliance.name),
                          subtitle: Text(
                            appliance.category.replaceAll('_', ' '),
                          ),
                          value: _selected.contains(appliance.id),
                          onChanged: _busy
                              ? null
                              : (value) => setState(() {
                                  if (value == true) {
                                    _selected.add(appliance.id);
                                  } else {
                                    _selected.remove(appliance.id);
                                  }
                                  _key = newCloudIdempotencyKey();
                                  _preview = null;
                                  _scopedPreview = null;
                                  _resetApproval();
                                  _error = null;
                                }),
                        ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed:
                          _busy || _selected.isEmpty || _selected.length > 25
                          ? null
                          : _create,
                      child: const Text('Create private preview'),
                    ),
                    if (_preview case final preview?) ...[
                      const SizedBox(height: 24),
                      Text(
                        preview.isStale
                            ? 'Saved preview · stale'
                            : 'Saved preview · current',
                        key: const Key('reportStatus'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (preview.isStale)
                        const Text(
                          'This snapshot changed or expired. Create a new preview before relying on its estimates.',
                        ),
                      Text(
                        'Created ${preview.createdAt.toUtc()} · Expires ${preview.expiresAt.toUtc()}',
                      ),
                      Text(
                        'Snapshot fingerprint: ${preview.snapshotSha256.substring(0, 12)}…',
                      ),
                      const Text(
                        'Whole-home total unavailable: only selected appliances are included. Measured energy and recommendations are not included.',
                      ),
                      for (final item in preview.items)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.category.replaceAll('_', ' '),
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                Text(item.explanation),
                                if (item.estimate case final estimate?) ...[
                                  Text(
                                    '${estimate.kind == 'estimated_useful_cost' ? 'Estimated useful cost' : 'Estimated operating cost'}: USD ${estimate.costUsd} · ${estimate.energyKwh} kWh',
                                  ),
                                  Text(
                                    '${estimate.periodStart} to ${estimate.periodEnd} (end exclusive) · As of ${estimate.asOf.toUtc()}',
                                  ),
                                  Text(
                                    'Sources: ${estimate.sourceRefs.join('; ')}',
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      if (preview.assumptions.isNotEmpty)
                        ExpansionTile(
                          title: const Text('Snapshot assumptions'),
                          children: [
                            for (final assumption in preview.assumptions)
                              ListTile(title: Text(assumption)),
                          ],
                        ),
                      if (_currentDeliveryId == null && !preview.isStale) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Request this snapshot by email. You choose the recipients and explicitly approve this exact preview. A request is queued; email delivery availability and completion are not confirmed here.',
                        ),
                        TextField(
                          key: const Key('reportRecipients'),
                          controller: _recipients,
                          maxLines: 3,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Recipient email addresses (1 to 5)',
                            helperText:
                                'Separate addresses with commas or new lines',
                          ),
                          onChanged: (_) => setState(() {
                            _resetApproval();
                            _error = null;
                          }),
                        ),
                        CheckboxListTile(
                          key: const Key('reportApproval'),
                          value: _approved,
                          onChanged: _busy
                              ? null
                              : (value) =>
                                    setState(() => _approved = value == true),
                          title: Text(
                            'I approve this report preview for the recipients above from ${widget.home.name}.',
                          ),
                          subtitle: const Text(
                            'This is a one-time request. No recurring email is enabled. A forwarded copy cannot be revoked.',
                          ),
                        ),
                        FilledButton(
                          key: const Key('requestReportDelivery'),
                          onPressed: _busy || !_approved
                              ? null
                              : _queueDelivery,
                          child: Text(
                            _attempt == null
                                ? 'Queue email report request'
                                : 'Retry same request',
                          ),
                        ),
                      ],
                      if (_currentDeliveryId != null) ...[
                        const SizedBox(height: 16),
                        if (_deliveryStatus case final status?)
                          Text(
                            status,
                            key: const Key('reportDeliveryStatus'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                      ],
                      TextButton(
                        onPressed: _busy ? null : _refreshPreview,
                        child: const Text('Check preview status'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
}

class _DeliveryAttempt {
  const _DeliveryAttempt(
    this.previewId,
    this.digest,
    this.recipients,
    this.key,
  );
  final String previewId, digest, key;
  final List<String> recipients;
}
