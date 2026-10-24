import 'package:flutter/material.dart';

import '../../core/backend_error.dart';
import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_home.dart';
import 'discovery_api.dart';
import 'discovery_credentials.dart';

/// Resolves a short code through Cloud before using the pinned local claim.
class HubPairingScreen extends StatefulWidget {
  const HubPairingScreen({
    super.key,
    this.api = const DiscoveryApi(),
    this.credentials = const DiscoveryCredentials(),
    this.cloudApi,
    this.homeId,
    this.onSetUpLater,
  });

  final DiscoveryApi api;
  final DiscoveryCredentials credentials;
  final CloudApiClient? cloudApi;
  final String? homeId;
  final VoidCallback? onSetUpLater;

  @override
  State<HubPairingScreen> createState() => _HubPairingScreenState();
}

class _HubPairingScreenState extends State<HubPairingScreen> {
  static final _codeFormat = RegExp(r'^[0-9A-HJKMNP-TV-Z]{6}$');
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _pair() async {
    if (_busy) return;
    final code = _code.text.trim().toUpperCase();
    if (!_codeFormat.hasMatch(code)) {
      setState(() {
        _error = 'Enter the 6-character code from your hub.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cloud = widget.cloudApi;
      final homeId = widget.homeId;
      if (cloud == null || homeId == null || homeId.isEmpty) {
        throw StateError('Cloud home unavailable');
      }
      final generation = cloud.session.generation;
      final clientId = newCloudIdempotencyKey();
      final resolution = await cloud.resolveHubPairingCode(
        homeId,
        code,
        clientId: clientId,
        idempotencyKey: newCloudIdempotencyKey(),
      );
      if (generation != cloud.session.generation ||
          !resolution.expiresAt.isAfter(DateTime.now().toUtc())) {
        throw StateError('Pairing resolution expired');
      }
      final details = PairingDetails.fromManualFields(
        address:
            '${resolution.httpsOrigin}#sha256=${resolution.certificateSha256}',
        hubId: resolution.localHubId,
        enrollmentSecret: resolution.enrollmentSecret,
      );
      await widget.credentials.claimAndStore(
        details,
        clientId: clientId,
        api: widget.api,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is PairingException
              ? error.message
              : internalErrorMessage;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pair with your hub')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            key: const Key('pairingCode'),
            controller: _code,
            decoration: const InputDecoration(
              labelText: 'Pairing code',
              helperText: 'Enter the 6-character code from your hub.',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _pair(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _pair,
            child: const Text('Verify and pair'),
          ),
          if (widget.onSetUpLater != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : widget.onSetUpLater,
              child: const Text('Set up later'),
            ),
          ],
        ],
      ),
    ),
  );
}
