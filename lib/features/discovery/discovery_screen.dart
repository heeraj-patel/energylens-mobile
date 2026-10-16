import 'dart:async';

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';

import 'dart:convert';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_appliance.dart';
import '../../core/cloud_api/cloud_home.dart';
import '../../core/cloud_api/cloud_hub_claim_flow.dart';
import '../../core/cloud_api/cloud_hub_claim.dart';
import '../../core/cloud_api/cloud_sensor.dart';

import 'discovery_api.dart';
import 'plug_connection_status.dart';
import 'discovery_credentials.dart';
import 'hub_pairing_screen.dart';
import '../identify/appliance_onboarding_screen.dart';
import 'device_energy_detail_screen.dart';

String? _makeModelIdentity(String? manufacturer, String? model) {
  final make = manufacturer?.trim() ?? '';
  final fullModel = model?.trim() ?? '';
  if (make.isEmpty || fullModel.isEmpty) return null;
  return '$make $fullModel';
}

/// Local discovery, adoption, and readback from the pilot hub.
class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({
    super.key,
    this.api = const DiscoveryApi(),
    this.credentials = const DiscoveryCredentials(),
    this.autoScan = false,
    this.cloudHome,
    this.cloudApi,
    this.accountId,
  });

  final DiscoveryApi api;
  final DiscoveryCredentials credentials;
  final bool autoScan;
  final CloudHome? cloudHome;
  final CloudApiClient? cloudApi;
  final String? accountId;

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final _hub = TextEditingController();
  final _token = TextEditingController();
  final _ip = TextEditingController();
  String _manualProtocol = 'kasa';
  List<DiscoveredPlug> _candidates = const [];
  List<NearbyDeviceCandidate> _nearbyCandidates = const [];
  List<NearbySavedDevice> _nearbySaved = const [];
  final Set<String> _addedNearbyIds = {};
  bool _nearbyAvailable = false;
  String? _nearbyState;
  String? _nearbyScanId;
  String? _nearbyScanHub;
  String? _nearbyScanToken;
  int _scanEpoch = 0;
  List<SavedPlug> _saved = const [];
  final Map<String, CloudAppliance> _cloudAttached = {};
  final Map<int, EnergyEstimate> _estimates = {};
  bool _busy = false;
  bool _hubConnected = false;
  bool _paired = false;
  bool _showConnectionSettings = false;
  bool _showManualEntry = false;
  String? _pairedHubId;
  bool _searched = false;
  final Set<String> _statusChecking = {};
  final Map<String, String> _plugCheckFeedback = {};
  final Map<String, String> _plugUpdateFeedback = {};
  String? _error;
  CloudHubClaimFlow? _claimFlow;
  bool _claimBusy = false;
  bool _claimedThisSession = false;
  String? _claimMessage;
  HubOwnership? _cloudOwnership;
  int? _pairedOwnershipEpoch;

  bool get _canUseHubCustomerApi =>
      widget.cloudHome == null ||
      (_cloudOwnership != null &&
          _pairedOwnershipEpoch == _cloudOwnership!.ownershipEpoch);

  OwnedPairingScope? get _pairingScope {
    final cloud = widget.cloudApi;
    final home = widget.cloudHome;
    final account = widget.accountId;
    if (cloud == null || home == null || account == null) return null;
    return OwnedPairingScope(
      origin: cloud.session.config.apiUrl,
      profile: cloud.session.credentialMethod,
      accountId: account,
      homeId: home.id,
    );
  }

  DiscoveryApi get _hubApi {
    final cloud = widget.cloudApi;
    final home = widget.cloudHome;
    if (cloud == null || home == null) return widget.api;
    final expectedScope = _pairingScope?.identity;
    final expectedGeneration = cloud.session.generation;
    return widget.api.authorizedFor(
      HubOwnerAuthorization(
        session: cloud.session,
        homeId: home.id,
        isCurrent: () =>
            mounted &&
            expectedScope != null &&
            _pairingScope?.identity == expectedScope &&
            cloud.session.generation == expectedGeneration &&
            _cloudOwnership?.homeId == home.id &&
            _cloudOwnership?.localHubId == _pairedHubId &&
            _cloudOwnership?.ownershipEpoch == _pairedOwnershipEpoch,
      ),
    );
  }

  Future<HubOwnership?> _ownedHub() async {
    final cloud = widget.cloudApi;
    final home = widget.cloudHome;
    final localHubId = _pairedHubId;
    if (cloud == null || home == null || localHubId == null) return null;
    if (_cloudOwnership case final current?
        when current.homeId == home.id && current.localHubId == localHubId) {
      return current;
    }
    final matches = (await cloud.hubs(home.id))
        .where((hub) => hub.localHubId == localHubId)
        .toList();
    if (matches.length > 1) {
      throw const FormatException('Duplicate cloud hub ownership');
    }
    _cloudOwnership = matches.firstOrNull;
    return _cloudOwnership;
  }

  Future<void> _claimHub() async {
    final home = widget.cloudHome;
    final cloud = widget.cloudApi;
    if (home == null || cloud == null || _claimBusy) return;
    setState(() {
      _claimBusy = true;
      _claimMessage = null;
    });
    try {
      final flow = _claimFlow ??= CloudHubClaimFlow(
        cloud: cloud,
        hub: widget.api,
        credentials: widget.credentials,
        scope: _pairingScope,
      );
      final ownership = await flow.claim(home);
      _cloudOwnership = ownership;
      if (mounted) {
        setState(() {
          _claimedThisSession = true;
          _claimMessage = _notSyncedMessage(ownership);
        });
      }
      // A newly claimed epoch revokes the pre-claim pairing token.
      if (_pairedOwnershipEpoch != ownership.ownershipEpoch) {
        _pairedOwnershipEpoch = null;
      }
    } on CloudApiException catch (error) {
      if (mounted) {
        setState(
          () => _claimMessage = error.statusCode == 409
              ? 'Cloud could not link this hub. It may already belong to a home. Check ownership before trying again.'
              : _claimFlow?.hasPendingFinish == true
              ? 'Cloud could not confirm the hub link (${error.code}). Retry to finish the same claim.'
              : 'Cloud could not start the hub link (${error.code}). Try again.',
        );
      }
    } on PairingException catch (error) {
      if (mounted) setState(() => _claimMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _claimMessage = _claimFlow?.hasPendingFinish == true
              ? 'Could not confirm the hub link. Retry to finish the same claim.'
              : 'Could not start the hub link. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _claimBusy = false);
    }
  }

  String _notSyncedMessage(HubOwnership ownership) =>
      'Hub linked to ${widget.cloudHome?.name ?? 'home'} (ownership epoch ${ownership.ownershipEpoch}). Local devices are not synced to Cloud yet.';

  Future<void> _syncAdoptedPlugSensors(Iterable<SavedPlug> plugs) async {
    final cloud = widget.cloudApi;
    final home = widget.cloudHome;
    final HubOwnership ownership;
    try {
      final current = await _ownedHub();
      if (current == null) return;
      ownership = current;
    } catch (_) {
      return;
    }
    if (cloud == null ||
        home == null ||
        ownership.homeId != home.id ||
        ownership.localHubId != _pairedHubId ||
        ownership.ownershipEpoch < 1) {
      return;
    }
    var complete = true;
    for (final plug in plugs) {
      // The Cloud sensor capability contract requires an observed meter.
      // Unknown or absent meters remain local and are never labeled measured.
      if (plug.meterStatus != 'verified') {
        complete = false;
        continue;
      }
      try {
        final before = await cloud.sensors(home.id);
        final existing = before.where(
          (sensor) =>
              sensor.hubId == ownership.hubId &&
              sensor.ownershipEpoch == ownership.ownershipEpoch &&
              sensor.localSensorId == plug.id,
        );
        if (existing.isNotEmpty) {
          if (existing.length != 1 ||
              !_matchesAdoptedPlugSensor(
                existing.single,
                home.id,
                ownership,
                plug,
              )) {
            complete = false;
            continue;
          }
          continue;
        }
        final capabilities = const ['power', 'energy'];
        await cloud.createSensor(
          home.id,
          CloudSensorCreate(
            kind: 'plug',
            capabilities: capabilities,
            hubId: ownership.hubId,
            ownershipEpoch: ownership.ownershipEpoch,
            // The hub uses this same stable ID for its adopted plug and
            // telemetry outbox, so its cloud-issued sensor ID maps back to it.
            localSensorId: plug.id,
          ),
          idempotencyKey: _sensorRegistrationKey(
            home.id,
            ownership.hubId,
            ownership.ownershipEpoch,
            plug.id,
            capabilities,
          ),
        );
        final after = await cloud.sensors(home.id);
        final readback = after.where(
          (sensor) =>
              sensor.hubId == ownership.hubId &&
              sensor.ownershipEpoch == ownership.ownershipEpoch &&
              sensor.localSensorId == plug.id,
        );
        if (readback.length != 1 ||
            !_matchesAdoptedPlugSensor(
              readback.single,
              home.id,
              ownership,
              plug,
            )) {
          complete = false;
        }
      } catch (_) {
        // Local adoption remains successful; a later scan or link can retry.
        complete = false;
      }
    }
    if (mounted) {
      setState(
        () => _claimMessage = complete ? null : _notSyncedMessage(ownership),
      );
    }
  }

  bool _matchesAdoptedPlugSensor(
    CloudSensor sensor,
    String homeId,
    HubOwnership ownership,
    SavedPlug plug,
  ) =>
      sensor.homeId == homeId &&
      sensor.hubId == ownership.hubId &&
      sensor.ownershipEpoch == ownership.ownershipEpoch &&
      sensor.localSensorId == plug.id &&
      sensor.kind == 'plug' &&
      sensor.capabilities.toSet().containsAll(const {'power', 'energy'});

  String _sensorRegistrationKey(
    String homeId,
    String hubId,
    int epoch,
    String localSensorId,
    List<String> capabilities,
  ) {
    final digest = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              'energylens-discovery-sensor-v1',
              homeId,
              hubId,
              epoch,
              localSensorId,
              capabilities,
            ]),
          ),
        )
        .bytes
        .take(16)
        .toList();
    digest[6] = (digest[6] & 0x0f) | 0x40;
    digest[8] = (digest[8] & 0x3f) | 0x80;
    final hex = digest
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  void _invalidateHubData() {
    if (_saved.isEmpty &&
        _nearbySaved.isEmpty &&
        _estimates.isEmpty &&
        _candidates.isEmpty &&
        !_searched &&
        !_nearbyAvailable) {
      return;
    }
    _cancelActiveNearbyScan();
    setState(() {
      _saved = const [];
      _nearbySaved = const [];
      _cloudAttached.clear();
      _hubConnected = false;
      _estimates.clear();
      _candidates = const [];
      _nearbyCandidates = const [];
      _addedNearbyIds.clear();
      _nearbyAvailable = false;
      _nearbyState = null;
      _scanEpoch++;
      _searched = false;
      _error = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      if (widget.cloudHome != null) {
        final cloud = widget.cloudApi;
        final scope = _pairingScope;
        if (cloud == null || scope == null) return;
        final sessionGeneration = cloud.session.generation;
        bool current() =>
            mounted &&
            _pairingScope?.identity == scope.identity &&
            cloud.session.generation == sessionGeneration;
        final ownerships = await cloud.hubs(scope.homeId);
        if (!current()) return;
        Future<StoredPairingCredential?> automaticallyPair(
          HubOwnership ownership,
        ) async {
          final connection = ownership.connection;
          if (connection == null || !connection.isFresh || !current()) {
            return null;
          }
          try {
            final clientId = await widget.credentials.ownedClientId(
              scope,
              ownership,
            );
            if (!current()) return null;
            final claim = await widget.api.claimOwnedPairing(
              ownership,
              clientId: clientId,
              owner: HubOwnerAuthorization(
                session: cloud.session,
                homeId: scope.homeId,
                isCurrent: current,
              ),
            );
            if (!current()) return null;
            final pairing = StoredPairingCredential(
              address:
                  '${connection.httpsOrigin}#sha256=${connection.certificateSha256}',
              hubId: claim.hubId,
              clientId: claim.clientId,
              token: claim.token,
              ownershipEpoch: claim.ownershipEpoch,
            );
            await widget.credentials.storeOwnedPairing(
              scope,
              ownership,
              pairing,
              isCurrent: current,
            );
            return pairing;
          } catch (_) {
            if (!current()) return null;
            // One unreachable owned Hub must not prevent another from
            // restoring. The existing manual pairing remains available.
            return null;
          }
        }

        for (final ownership in ownerships) {
          var pairing = await widget.credentials.readOwnedPairing(
            scope,
            ownership,
          );
          if (!current()) return;
          if (ownership.homeId != scope.homeId) continue;
          if (pairing != null) {
            try {
              await widget.api.verifyStoredPairing(
                StoredHubIdentity(
                  address: pairing.address,
                  hubId: pairing.hubId,
                ),
              );
            } catch (_) {
              // A current directory publication can repair an address or pin
              // change without trusting anything learned from the LAN.
              pairing = null;
            }
          }
          if (!current()) return;
          final automaticallyPaired = pairing == null;
          if (pairing == null) pairing = await automaticallyPair(ownership);
          if (!current()) return;
          if (pairing == null) continue;
          final restoredPairing = pairing;
          _cloudOwnership = ownership;
          _pairedOwnershipEpoch = restoredPairing.ownershipEpoch;
          setState(() {
            _paired = true;
            _pairedHubId = restoredPairing.hubId;
            _hub.text = restoredPairing.address;
            _token.text = restoredPairing.token;
          });
          final requiresPairing = await _loadSaved();
          if (!current()) return;
          if (requiresPairing && !automaticallyPaired) {
            final repaired = await automaticallyPair(ownership);
            if (!current()) return;
            if (repaired != null) {
              setState(() {
                _pairedHubId = repaired.hubId;
                _pairedOwnershipEpoch = repaired.ownershipEpoch;
                _hub.text = repaired.address;
                _token.text = repaired.token;
              });
              await _loadSaved();
            }
          }
          if (current() && _hubConnected && widget.autoScan) await _search();
          return;
        }
        if (ownerships.isEmpty) {
          // A first claim needs the bootstrap pairing, but it cannot read
          // household inventory before Cloud ownership is established.
          final pairing = await widget.credentials.readPairing();
          if (!current() || pairing == null) return;
          await widget.api.verifyStoredPairing(
            StoredHubIdentity(address: pairing.address, hubId: pairing.hubId),
          );
          if (!current()) return;
          setState(() {
            _paired = true;
            _pairedHubId = pairing.hubId;
            _pairedOwnershipEpoch = null;
            _hub.text = pairing.address;
            _token.text = pairing.token;
          });
        }
        return;
      }
      await widget.credentials.importDebugPairingFile();
      final pairing = await widget.credentials.readPairing();
      if (pairing != null) {
        if (!mounted) return;
        setState(() {
          _paired = true;
          _pairedHubId = pairing.hubId;
          _hub.text = pairing.address;
          _token.text = pairing.token;
        });
        await _hubApi.verifyStoredPairing(
          StoredHubIdentity(address: pairing.address, hubId: pairing.hubId),
        );
        try {
          if (await _ownedHub() != null && mounted) {
            setState(() => _claimedThisSession = true);
          }
        } catch (_) {
          // Local discovery remains available if Cloud is offline.
        }
        await _loadSaved();
        if (widget.autoScan) await _search();
        return;
      }
      final (address, token) = await widget.credentials.read();
      if (!mounted) return;
      if (address != null) _hub.text = address;
      if (token != null) _token.text = token;
      if (address != null && token != null) {
        await _loadSaved();
        if (widget.autoScan) await _search();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _hubConnected = false;
          _error = error is PairingException
              ? error.message
              : 'Could not restore the hub connection. Pair again or retry.';
        });
      }
    }
  }

  Future<void> _openPairing() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            HubPairingScreen(api: widget.api, credentials: widget.credentials),
      ),
    );
    if (result == true && mounted) {
      final scope = _pairingScope;
      final cloud = widget.cloudApi;
      if (scope != null && cloud != null) {
        final owned = await cloud.hubs(scope.homeId);
        for (final ownership in owned) {
          if (await widget.credentials.saveOwnedPairing(scope, ownership))
            break;
        }
      }
      _invalidateHubData();
      await _restore();
    }
  }

  Future<bool> _loadSaved() async {
    if (!_canUseHubCustomerApi) return false;
    var requiresPairing = false;
    try {
      final plugs = await _hubApi.saved(_hub.text.trim(), _token.text.trim());
      if (mounted) {
        setState(() {
          _saved = plugs;
          _hubConnected = true;
          _error = null;
        });
        await _syncAdoptedPlugSensors(plugs);
        await _loadCloudAttachments(plugs);
        for (final plug in plugs) {
          final appliance = plug.connectedAppliance;
          if (appliance == null) continue;
          if (plug.connectionStatus == 'identity_changed') {
            _estimates.remove(appliance.id);
            continue;
          }
          try {
            final estimate = await _hubApi.estimate(
              _hub.text.trim(),
              _token.text.trim(),
              appliance.id,
            );
            if (mounted) setState(() => _estimates[appliance.id] = estimate);
          } catch (_) {
            // The plug remains visible when the source cache is unavailable.
          }
        }
      }
    } catch (error) {
      requiresPairing = error is HubRequestException && error.requiresPairing;
      if (mounted) {
        setState(() {
          _hubConnected = false;
          _error =
              'Could not load saved plugs from the hub. Check its connection.';
        });
      }
    } finally {
      if (!requiresPairing) await _loadNearbySaved();
    }
    return requiresPairing;
  }

  Future<void> _loadNearbySaved() async {
    final hub = _hub.text.trim();
    final token = _token.text.trim();
    try {
      if (!await _hubApi.supportsNearbyDiscovery(hub, token)) {
        return;
      }
      if (!mounted || hub != _hub.text.trim() || token != _token.text.trim()) {
        return;
      }
      final devices = await _hubApi.nearbyInventory(hub, token);
      if (mounted && hub == _hub.text.trim() && token == _token.text.trim()) {
        setState(() => _nearbySaved = devices);
      }
    } catch (_) {
      // Keep the last inventory visible on a failed v2 read.
    }
  }

  Future<void> _loadCloudAttachments(Iterable<SavedPlug> plugs) async {
    final cloud = widget.cloudApi;
    final home = widget.cloudHome;
    if (cloud == null || home == null || plugs.isEmpty) return;
    try {
      final ownership = await _ownedHub();
      if (ownership == null) return;
      final sensors = await cloud.sensors(home.id);
      final attachments = await cloud.attachments(home.id);
      final appliances = (await cloud.applianceList(home.id)).appliances;
      final applianceById = {
        for (final item in appliances)
          if (item.homeId == home.id &&
              item.archivedAt == null &&
              item.demoDeviceId == null)
            item.id: item,
      };
      final attached = <String, CloudAppliance>{};
      for (final plug in plugs) {
        final matches = sensors.where(
          (sensor) =>
              sensor.hubId == ownership.hubId &&
              sensor.ownershipEpoch == ownership.ownershipEpoch &&
              sensor.localSensorId == plug.id,
        );
        if (matches.length != 1) continue;
        final active = attachments.where(
          (item) => item.sensorId == matches.single.id && item.endedAt == null,
        );
        if (active.length != 1) continue;
        final appliance = applianceById[active.single.applianceId];
        if (appliance != null) attached[plug.id] = appliance;
      }
      if (mounted) {
        setState(() {
          _cloudAttached
            ..clear()
            ..addAll(attached);
        });
      }
    } catch (_) {
      // The local plug remains available if Cloud readback is unavailable.
    }
  }

  Future<void> _refreshPlugStatus(SavedPlug plug) async {
    if (_statusChecking.contains(plug.id)) return;
    setState(() {
      _statusChecking.add(plug.id);
      _plugCheckFeedback.remove(plug.id);
      _error = null;
    });
    try {
      final refreshed = await _hubApi.refreshPlugStatus(
        _hub.text.trim(),
        _token.text.trim(),
        plug.id,
      );
      if (!mounted) return;
      setState(() {
        _saved = [
          for (final current in _saved)
            if (current.id == refreshed.id) refreshed else current,
        ];
        final result = switch (refreshed.connectionStatus) {
          'connected' => 'Check complete · Plug connected',
          'disconnected' => 'Check complete · Plug disconnected',
          'identity_changed' =>
            'Check complete · Different plug at this address',
          _ => null,
        };
        if (result != null) _plugCheckFeedback[plug.id] = result;
        if (refreshed.connectionStatus == 'identity_changed') {
          final applianceId = refreshed.connectedAppliance?.id;
          if (applianceId != null) _estimates.remove(applianceId);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _plugCheckFeedback[plug.id] = 'Check failed · Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _statusChecking.remove(plug.id));
    }
  }

  Future<void> _checkConnectedEnergy(SavedAppliance appliance) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _hubApi.lookupEnergy(
        _hub.text.trim(),
        _token.text.trim(),
        appliance.id,
      );
      final estimate = await _hubApi.estimate(
        _hub.text.trim(),
        _token.text.trim(),
        appliance.id,
      );
      if (mounted) setState(() => _estimates[appliance.id] = estimate);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError
              ? error.message
              : 'Could not check energy data.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _attachedApplianceIdentity(SavedPlug plug) {
    final cloudAppliance = _cloudAttached[plug.id];
    if (cloudAppliance != null) {
      return _makeModelIdentity(cloudAppliance.brand, cloudAppliance.fullModel);
    }
    final appliance = plug.connectedAppliance;
    if (appliance == null) return null;
    return _makeModelIdentity(appliance.manufacturer, appliance.model);
  }

  Widget _attachedApplianceSection(SavedPlug plug, ThemeData theme) {
    final identity = _attachedApplianceIdentity(plug);
    if (identity == null) return const SizedBox.shrink();

    final cloudAppliance = _cloudAttached[plug.id];
    final appliance = plug.connectedAppliance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Text(identity, style: theme.textTheme.labelLarge),
        if (cloudAppliance != null) ...[
          Text(cloudAppliance.name, style: theme.textTheme.titleMedium),
          Text(cloudAppliance.category),
        ] else if (appliance != null) ...[
          Text(appliance.name, style: theme.textTheme.titleMedium),
          Text(appliance.category),
          const Text('Connected load · No live readings'),
          if (plug.connectionStatus == 'identity_changed')
            const Text('Estimate hidden until this plug is verified.')
          else if (_estimates[appliance.id] case final estimate?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                energyRateDescription(estimate),
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (plug.connectionStatus != 'identity_changed') ...[
            if (_estimates[appliance.id]?.evidence case final source?) ...[
              Text(
                _estimates[appliance.id]!.estimatedCostUsd == null
                    ? 'Estimated monthly energy: ${_estimates[appliance.id]!.estimatedKwh!.toStringAsFixed(1)} kWh'
                    : 'Estimated monthly cost: \$${_estimates[appliance.id]!.estimatedCostUsd!.toStringAsFixed(2)} · ${_estimates[appliance.id]!.estimatedKwh!.toStringAsFixed(1)} kWh',
              ),
              TextButton.icon(
                onPressed: () => _showSource(source, _estimates[appliance.id]!),
                icon: Icon(
                  source.sourceKind == 'energy_star' ||
                          source.sourceKind == 'epa_exact'
                      ? Icons.verified_outlined
                      : Icons.info_outline,
                ),
                label: Text(energySourceLabel(source)),
              ),
            ] else
              const Text('Estimate unavailable · Exact model/source needed'),
          ],
          TextButton(
            onPressed: _busy ? null : () => _checkConnectedEnergy(appliance),
            child: const Text('Check energy data or update cost'),
          ),
        ],
      ],
    );
  }

  void _showSource(EnergyEvidence source, EnergyEstimate estimate) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                energySourceHeading(source),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (source.sourceKind != 'user_label')
                Text(
                  'Matched model: ${source.matchedBrand} ${source.matchedModel}',
                ),
              Text(
                source.sourceKind == 'user_label'
                    ? 'Calculated energy: ${source.annualKwh.toStringAsFixed(1)} kWh/year'
                    : 'Published energy${estimate.bulbCount != null && estimate.bulbCount! > 1 ? ' per bulb' : ''}: ${source.annualKwh.toStringAsFixed(1)} kWh/year',
              ),
              Text('Basis: ${source.usageBasis}'),
              if (source.sourceKind != 'user_label')
                Text('Dataset: ${source.datasetId}'),
              Text(
                'Source date: ${DateTime.fromMillisecondsSinceEpoch(source.retrievedAt * 1000).toLocal()}',
              ),
              Text(energyRateDescription(estimate)),
              if (estimate.rateSourceUrl case final url?) SelectableText(url),
              if (source.sourceUrl.isNotEmpty) SelectableText(source.sourceUrl),
              const SizedBox(height: 8),
              const Text(
                'Estimated energy for the connected load. No live energy measurement.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _connectAppliance(SavedPlug plug) async {
    if (_busy) return;
    if (widget.cloudHome != null && widget.cloudApi != null) {
      await _connectCloudAppliance(plug);
      return;
    }
    List<SavedAppliance> appliances;
    try {
      appliances = await _hubApi.appliances(
        _hub.text.trim(),
        _token.text.trim(),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load appliances from the hub.');
      }
      return;
    }
    if (!mounted) return;
    final choice = await showDialog<Object>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Connected appliance or lamp'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              'For appliance-specific readings, connect only that appliance to this plug. A shared plug measures the combined load.',
            ),
          ),
          for (final item in appliances)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, item.id),
              child: Text('${item.name} · ${item.category}'),
            ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'manual'),
            child: const Text('Enter a new appliance'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'photo'),
            child: const Text('Identify a new appliance from photo'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice is String) {
      final attached = await Navigator.push<SavedPlug>(
        context,
        MaterialPageRoute(
          builder: (_) => ApplianceOnboardingScreen(
            method: choice,
            plugId: plug.id,
            api: widget.api,
            credentials: widget.credentials,
          ),
        ),
      );
      if (attached != null && mounted) {
        setState(
          () => _saved = [
            for (final item in _saved)
              if (item.id == attached.id) attached else item,
          ],
        );
        if (attached.connectedAppliance != null) {
          await _checkConnectedEnergy(attached.connectedAppliance!);
        }
      }
      return;
    }
    if (choice is! int) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final attached = await _hubApi.attachAppliance(
        _hub.text.trim(),
        _token.text.trim(),
        plug.id,
        choice,
      );
      if (mounted) {
        setState(
          () => _saved = [
            for (final item in _saved)
              if (item.id == attached.id) attached else item,
          ],
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError
              ? error.message
              : 'Could not connect this appliance to the plug.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectCloudAppliance(SavedPlug plug) async {
    final cloud = widget.cloudApi!;
    final home = widget.cloudHome!;
    List<CloudAppliance> appliances;
    try {
      final inventory = await cloud.applianceList(home.id);
      appliances = inventory.appliances
          .where(
            (item) =>
                item.homeId == home.id &&
                item.demoDeviceId == null &&
                item.archivedAt == null &&
                item.fuel == 'electricity' &&
                item.version != null,
          )
          .toList();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not load this home’s appliances. Try again.',
        );
      }
      return;
    }
    if (!mounted) return;
    final choice = await showDialog<Object>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Connected appliance or lamp'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              'For appliance-specific readings, connect only that appliance to this plug. A shared plug measures the combined load.',
            ),
          ),
          for (final item in appliances)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, item),
              child: Text('${item.name} · ${item.category}'),
            ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'manual'),
            child: const Text('Enter a new appliance'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'photo'),
            child: const Text('Identify a new appliance from photo'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice is String) {
      final saved = await Navigator.push<CloudAppliance>(
        context,
        MaterialPageRoute<CloudAppliance>(
          builder: (_) => ApplianceOnboardingScreen(
            method: choice,
            cloudHome: home,
            cloudApi: cloud,
          ),
        ),
      );
      if (saved != null && mounted) {
        setState(() {
          _busy = true;
          _error = null;
        });
        try {
          await _attachCloudAppliance(plug, saved);
          if (mounted) setState(() => _cloudAttached[plug.id] = saved);
        } catch (_) {
          if (mounted) {
            setState(
              () => _error = 'Could not connect this appliance to the plug.',
            );
          }
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      }
      return;
    }
    if (choice is! CloudAppliance) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _attachCloudAppliance(plug, choice);
      if (mounted) setState(() => _cloudAttached[plug.id] = choice);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not connect this appliance to the plug.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attachCloudAppliance(
    SavedPlug plug,
    CloudAppliance appliance,
  ) async {
    final cloud = widget.cloudApi!;
    final homeId = widget.cloudHome!.id;
    final ownership = await _ownedHub();
    if (ownership == null || plug.meterStatus != 'verified') {
      throw StateError('Cloud sensor unavailable');
    }
    await _syncAdoptedPlugSensors([plug]);
    final sensors = (await cloud.sensors(homeId))
        .where(
          (sensor) =>
              sensor.hubId == ownership.hubId &&
              sensor.ownershipEpoch == ownership.ownershipEpoch &&
              sensor.localSensorId == plug.id &&
              _matchesAdoptedPlugSensor(sensor, homeId, ownership, plug),
        )
        .toList();
    if (sensors.length != 1 || appliance.version == null) {
      throw StateError('Cloud sensor or appliance unavailable');
    }
    final sensor = sensors.single;
    final active = (await cloud.attachments(homeId))
        .where((item) => item.sensorId == sensor.id && item.endedAt == null)
        .toList();
    if (active.length > 1) throw StateError('Duplicate active attachment');
    if (active.isNotEmpty) {
      if (active.single.applianceId == appliance.id) return;
    }
    final startedAt = DateTime.now().toUtc();
    final request = CloudAttachmentCreate(
      sensorId: sensor.id,
      applianceId: appliance.id,
      startedAt: startedAt,
      identityRevision: appliance.version!,
    );
    try {
      await cloud.createAttachment(
        homeId,
        request,
        ifMatch: '"${sensor.version}"',
        idempotencyKey: _attachmentKey(
          homeId,
          sensor.id,
          appliance.id,
          startedAt,
        ),
      );
    } catch (_) {
      final readback = (await cloud.attachments(homeId))
          .where((item) => item.sensorId == sensor.id && item.endedAt == null)
          .toList();
      if (readback.length != 1 || readback.single.applianceId != appliance.id) {
        rethrow;
      }
    }
    final readback = (await cloud.attachments(homeId))
        .where((item) => item.sensorId == sensor.id && item.endedAt == null)
        .toList();
    if (readback.length != 1 || readback.single.applianceId != appliance.id) {
      throw const FormatException('Cloud attachment readback changed');
    }
  }

  String _attachmentKey(
    String homeId,
    String sensorId,
    String applianceId,
    DateTime startedAt,
  ) {
    final bytes = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              'energylens-discovery-attachment-v1',
              homeId,
              sensorId,
              applianceId,
              startedAt.toIso8601String(),
            ]),
          ),
        )
        .bytes
        .take(16)
        .toList();
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> _adopt(DiscoveredPlug plug) async {
    final name = TextEditingController(
      text: plug.alias?.isNotEmpty == true ? plug.alias : plug.model,
    );
    final room = TextEditingController();
    var acknowledged = false;
    final details = await showDialog<(String, String, bool)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Save smart plug'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Plug name'),
                ),
                TextField(
                  controller: room,
                  decoration: const InputDecoration(labelText: 'Room'),
                ),
                if (plug.meterStatus == 'absent')
                  CheckboxListTile(
                    value: acknowledged,
                    onChanged: (value) =>
                        update(() => acknowledged = value ?? false),
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'I understand this plug cannot measure energy',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  name.text.trim().isEmpty ||
                      (plug.meterStatus == 'absent' && !acknowledged)
                  ? null
                  : () => Navigator.pop(dialogContext, (
                      name.text.trim(),
                      room.text.trim(),
                      acknowledged,
                    )),
              child: const Text('Save plug'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    room.dispose();
    if (details == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await _hubApi.adopt(
        _hub.text.trim(),
        _token.text.trim(),
        plug,
        details.$1,
        details.$2,
        details.$3,
      );
      if (!mounted) return;
      setState(() {
        _saved = [..._saved.where((item) => item.id != saved.id), saved];
      });
      try {
        if (!_paired) {
          await widget.credentials.save(_hub.text.trim(), _token.text.trim());
        }
      } catch (_) {
        if (mounted) {
          setState(
            () => _error = 'Plug saved on the hub. Enter the hub address and token again next time.',
          );
        }
      }
      await _syncAdoptedPlugSensors(_saved);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError ? error.message : 'Could not save the plug. Check that it is still connected and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateSavedConnection(
    DiscoveredPlug candidate,
    SavedPlug saved,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _plugUpdateFeedback.remove(saved.id);
      _error = null;
    });
    try {
      final updated = await _hubApi.adopt(
        _hub.text.trim(),
        _token.text.trim(),
        candidate,
        saved.name,
        saved.room,
        candidate.meterStatus == 'absent',
      );
      if (!mounted) return;
      setState(() {
        _saved = [
          for (final plug in _saved)
            if (plug.id == updated.id) updated else plug,
        ];
        _plugUpdateFeedback[saved.id] = 'Plug connection updated';
      });
      await _syncAdoptedPlugSensors(_saved);
      await _refreshPlugStatus(updated);
    } catch (_) {
      if (mounted) {
        setState(() {
          _plugUpdateFeedback[saved.id] = 'Could not update the plug connection. Check that it is still connected and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _cancelActiveNearbyScan();
    _hub.dispose();
    _token.dispose();
    _ip.dispose();
    super.dispose();
  }

  Future<void> _search({bool manual = false}) async {
    if (_busy || !_canUseHubCustomerApi) return;
    int? nearbyEpoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_token.text.trim().isEmpty) {
        throw const FormatException('Enter the hub discovery token.');
      }
      if (!manual &&
          await _hubApi.supportsNearbyDiscovery(
            _hub.text.trim(),
            _token.text.trim(),
          )) {
        if (!mounted) return;
        setState(() {
          _nearbyAvailable = true;
          _nearbyState = 'queued';
          _nearbyCandidates = const [];
          _searched = true;
        });
        final epoch = ++_scanEpoch;
        nearbyEpoch = epoch;
        final scanHub = _hub.text.trim();
        final scanToken = _token.text.trim();
        final collected = <String, NearbyDeviceCandidate>{};
        var scan = await _hubApi.startNearbyScan(scanHub, scanToken);
        if (!mounted || epoch != _scanEpoch) {
          unawaited(_cancelScan(scanHub, scanToken, scan.id));
          return;
        }
        _nearbyScanId = scan.id;
        _nearbyScanHub = scanHub;
        _nearbyScanToken = scanToken;
        for (var attempt = 0; attempt < 15; attempt++) {
          if (!mounted || epoch != _scanEpoch) return;
          setState(() {
            _nearbyState = scan.state;
            for (final candidate in scan.candidates) {
              collected[candidate.id] = candidate;
            }
            _nearbyCandidates = collected.values.toList(growable: false);
            _hubConnected = true;
          });
          if (scan.nextCursor != null) {
            scan = await _hubApi.nearbyScan(
              scanHub,
              scanToken,
              scan.id,
              cursor: scan.nextCursor,
            );
            continue;
          }
          if (scan.isTerminal) break;
          await Future<void>.delayed(const Duration(seconds: 1));
          if (!mounted || epoch != _scanEpoch) return;
          scan = await _hubApi.nearbyScan(scanHub, scanToken, scan.id);
        }
        if (mounted && epoch == _scanEpoch && !scan.isTerminal) {
          setState(() => _nearbyState = 'failed');
          _cancelActiveNearbyScan();
        }
        if (epoch == _scanEpoch && scan.isTerminal) _clearActiveNearbyScan();
        return;
      }
      if (!manual && mounted) setState(() => _nearbyAvailable = false);
      final results = manual
          ? [
              await _hubApi.probe(
                _hub.text.trim(),
                _token.text.trim(),
                _ip.text.trim(),
                protocol: _manualProtocol,
              ),
            ]
          : await _hubApi.scan(_hub.text.trim(), _token.text.trim());
      if (!mounted) return;
      setState(() {
        final byId = <String, DiscoveredPlug>{
          for (final candidate in _candidates) candidate.id: candidate,
          for (final candidate in results) candidate.id: candidate,
        };
        _candidates = byId.values.toList();
        _searched = true;
        _hubConnected = true;
        if (_candidates.isEmpty) _showManualEntry = true;
      });
      await _syncAdoptedPlugSensors(_saved);
    } catch (error) {
      if (!mounted) return;
      if (nearbyEpoch != null && nearbyEpoch != _scanEpoch) return;
      if (nearbyEpoch != null) _cancelActiveNearbyScan();
      setState(() {
        if (_nearbyAvailable) {
          _nearbyState = 'failed';
          return;
        }
        _error = error is FormatException
            ? error.message
            : error is StateError
            ? error.message
            : 'Couldn’t connect. Try again.';
      });
    } finally {
      if (mounted && (nearbyEpoch == null || nearbyEpoch == _scanEpoch)) {
        setState(() => _busy = false);
      }
    }
  }

  List<Widget> _detectedResults(ThemeData theme) {
    if (_nearbyAvailable) return _nearbyResults(theme);
    final savedById = {for (final plug in _saved) plug.id: plug};
    final savedIds = savedById.keys.toSet();
    final candidates = [..._candidates]
      ..sort((left, right) {
        final savedOrder = (savedIds.contains(right.id) ? 1 : 0).compareTo(
          savedIds.contains(left.id) ? 1 : 0,
        );
        if (savedOrder != 0) return savedOrder;
        final modelOrder = left.model.compareTo(right.model);
        return modelOrder != 0 ? modelOrder : left.ip.compareTo(right.ip);
      });
    return [
      if (_nearbySaved.isNotEmpty) ..._nearbyResults(theme),
      const SizedBox(height: 24),
      Text('Detected plugs', style: theme.textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(
        _searched
            ? '${candidates.length} verified in this session · Tap a plug for details'
            : 'Scan results will appear here. Detection does not save a plug yet.',
        style: theme.textTheme.bodyMedium,
      ),
      if (_searched && candidates.isEmpty) ...[
        const SizedBox(height: 8),
        const Text(
          'No verified plugs found. Check that the plug is powered on and try its IP address.',
        ),
      ],
      for (final candidate in candidates) ...[
        const SizedBox(height: 8),
        _PlugCandidateCard(
          candidate: candidate,
          saved: savedById.containsKey(candidate.id),
          savedName: savedById[candidate.id]?.name,
          onSave: _busy
              ? null
              : savedById[candidate.id] == null
              ? () => _adopt(candidate)
              : () =>
                    _updateSavedConnection(candidate, savedById[candidate.id]!),
          updateFeedback: _plugUpdateFeedback[candidate.id],
        ),
      ],
    ];
  }

  List<Widget> _nearbyResults(ThemeData theme) {
    final active = _nearbyState == 'queued' || _nearbyState == 'running';
    final stopped =
        _nearbyState == 'failed' ||
        _nearbyState == 'cancelled' ||
        _nearbyState == 'partial';
    return [
      const SizedBox(height: 24),
      Text('Nearby devices', style: theme.textTheme.titleLarge),
      if (active) const Text('Looking for devices…'),
      if (stopped) const Text('Search stopped. Try again.'),
      if (!active &&
          !stopped &&
          _nearbyCandidates.isEmpty &&
          _nearbySaved.isEmpty)
        const Text('No devices found'),
      if (active)
        TextButton(onPressed: _cancelNearby, child: const Text('Cancel')),
      if (stopped)
        TextButton(
          onPressed: _busy ? null : () => _search(),
          child: const Text('Try again'),
        ),
      for (final device in _nearbySaved.where(
        (device) => !_saved.any((plug) => plug.id == device.id),
      ))
        ListTile(
          key: Key('nearby-saved-${device.id}'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            device.name.trim().isEmpty ? 'Unnamed device' : device.name,
          ),
        ),
      for (final candidate in _nearbyCandidates)
        if (!_addedNearbyIds.contains(candidate.id))
          ListTile(
            key: Key('nearby-${candidate.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(candidate.displayName),
            trailing: TextButton(
              onPressed:
                  _busy ||
                      (candidate.requiresAction &&
                          (candidate.manualProtocol == null ||
                              candidate.manualIpv4 == null))
                  ? null
                  : () => _addNearby(candidate),
              child: const Text('Add'),
            ),
          ),
    ];
  }

  void _cancelNearby() {
    _scanEpoch++;
    _cancelActiveNearbyScan();
    setState(() {
      _nearbyState = 'cancelled';
      _busy = false;
    });
  }

  Future<void> _cancelScan(String hub, String token, String scanId) async {
    try {
      await _hubApi.cancelNearbyScan(hub, token, scanId);
    } catch (_) {
      // The visible scan is stopped locally even if the Hub is unreachable.
    }
  }

  void _cancelActiveNearbyScan() {
    final scanId = _nearbyScanId;
    final hub = _nearbyScanHub;
    final token = _nearbyScanToken;
    _clearActiveNearbyScan();
    if (scanId != null && hub != null && token != null) {
      unawaited(_cancelScan(hub, token, scanId));
    }
  }

  void _clearActiveNearbyScan() {
    _nearbyScanId = null;
    _nearbyScanHub = null;
    _nearbyScanToken = null;
  }

  Future<void> _addNearby(NearbyDeviceCandidate candidate) async {
    if (DateTime.now().millisecondsSinceEpoch >= candidate.expiresAtMs) {
      setState(() => _error = 'Search stopped. Try again.');
      return;
    }
    if (candidate.requiresAction) {
      final continueSetup = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Finish setup'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (continueSetup == true && mounted) {
        _ip.text = candidate.manualIpv4!;
        setState(() {
          _showManualEntry = true;
          _manualProtocol = candidate.manualProtocol!;
          _nearbyAvailable = false;
        });
        await _search(manual: true);
      }
      return;
    }
    setState(() => _busy = true);
    try {
      await _hubApi.adoptNearby(
        _hub.text.trim(),
        _token.text.trim(),
        candidate,
        candidate.displayName,
      );
      if (mounted) setState(() => _addedNearbyIds.add(candidate.id));
      await _loadNearbySaved();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Couldn’t connect. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Find a smart plug')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_hubConnected) ...[
              Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Hub connected',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(
                      () => _showConnectionSettings = !_showConnectionSettings,
                    ),
                    child: Text(
                      _showConnectionSettings
                          ? 'Hide details'
                          : 'Connection details',
                    ),
                  ),
                ],
              ),
            ],
            if (widget.cloudHome != null &&
                widget.cloudApi != null &&
                _paired) ...[
              const SizedBox(height: 16),
              Text(
                'Cloud home: ${widget.cloudHome!.name}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                'Link this paired hub to the selected cloud home. The hub must be registered for cloud claims.',
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _claimBusy || _claimedThisSession ? null : _claimHub,
                icon: const Icon(Icons.cloud_done_outlined),
                label: Text(
                  _claimBusy
                      ? 'Linking hub…'
                      : _claimedThisSession
                      ? 'Hub linked to home'
                      : 'Link paired hub to home',
                ),
              ),
              if (_claimMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _claimMessage!,
                    key: const Key('hubClaimMessage'),
                  ),
                ),
            ],
            if (!_hubConnected || _showConnectionSettings) ...[
              Text(
                'Connect to your local hub',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Connect the plug to the same Wi-Fi network as your local hub. Pair this phone with the hub, then scan for TP-Link Kasa plugs or enter a local plug IP.',
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : _openPairing,
                icon: const Icon(Icons.phonelink_lock),
                label: Text(
                  _paired ? 'Pair with a different hub' : 'Pair with hub',
                ),
              ),
              if (_pairedHubId != null) ...[
                const SizedBox(height: 8),
                Text('Paired hub: $_pairedHubId'),
              ],
              if (_paired && !_hubConnected) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _restore,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry hub connection'),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                key: const Key('hubAddress'),
                controller: _hub,
                decoration: InputDecoration(
                  labelText: _paired ? 'Paired hub address' : 'Hub address',
                  hintText: 'https://192.168.68.136:18787#sha256=…',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                readOnly: _paired,
                onChanged: (_) => _invalidateHubData(),
              ),
              const SizedBox(height: 12),
              if (!_paired)
                TextField(
                  controller: _token,
                  decoration: const InputDecoration(
                    labelText: 'Pilot discovery token',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  autocorrect: false,
                  onChanged: (_) => _invalidateHubData(),
                ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy || !_canUseHubCustomerApi
                  ? null
                  : () => _search(),
              icon: const Icon(Icons.radar),
              label: const Text('Scan for plugs'),
            ),
            ..._detectedResults(theme),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () =>
                  setState(() => _showManualEntry = !_showManualEntry),
              icon: Icon(_showManualEntry ? Icons.expand_less : Icons.add_link),
              label: Text(
                _showManualEntry
                    ? 'Hide manual IP entry'
                    : 'Enter a plug IP address',
              ),
            ),
            if (_showManualEntry) ...[
              const Text(
                'If the scan misses your plug, enter its local IP address.',
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('manualPlugIp'),
                controller: _ip,
                decoration: const InputDecoration(
                  labelText: 'Plug IP address',
                  hintText: '192.168.1.42',
                  border: OutlineInputBorder(),
                ),
                // iOS maps this to the decimal pad, which includes the period
                // needed for dotted IPv4 addresses. Leave input unrestricted
                // so users can paste a complete address; the hub validates it.
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _manualProtocol,
                decoration: const InputDecoration(
                  labelText: 'Device type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'kasa', child: Text('TP-Link Kasa')),
                  DropdownMenuItem(
                    value: 'shelly_gen2',
                    child: Text('Shelly Gen2'),
                  ),
                  DropdownMenuItem(value: 'tasmota', child: Text('Tasmota')),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _manualProtocol = value);
                        }
                      },
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy || !_canUseHubCustomerApi
                    ? null
                    : () => _search(manual: true),
                child: const Text('Check this IP address'),
              ),
            ],
            if (_busy && !_nearbyAvailable) ...[
              const SizedBox(height: 18),
              const Center(child: CircularProgressIndicator()),
              Center(
                child: Text(
                  _nearbyAvailable
                      ? 'Looking for devices…'
                      : 'Checking the local network…',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Saved smart plugs',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: _busy ? null : _loadSaved,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh saved plugs',
                ),
              ],
            ),
            if (_saved.isEmpty)
              const Text('No smart plugs saved on this hub yet.'),
            for (final plug in _saved) ...[
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Smart plug · Saved',
                        style: theme.textTheme.labelLarge,
                      ),
                      Text(plug.name, style: theme.textTheme.titleMedium),
                      Text(
                        '${plug.model} · ${plug.room.isEmpty ? 'No room' : plug.room}',
                      ),
                      if (plug.mac != null) Text('MAC ${plug.mac}'),
                      if (plug.localProtocol == 'http')
                        Text('Local API · HTTP ${plug.httpPort ?? 80}'),
                      Text(
                        plug.meterStatus == 'absent'
                            ? 'No energy monitoring'
                            : 'Meter status: ${plug.meterStatus}',
                      ),
                      if (plug.connectedAppliance == null ||
                          _attachedApplianceIdentity(plug) != null)
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => DeviceEnergyDetailScreen(
                                plug: plug,
                                api: widget.api,
                                hubAddress: _hub.text.trim(),
                                token: _token.text.trim(),
                                estimate: plug.connectedAppliance == null
                                    ? null
                                    : _estimates[plug.connectedAppliance!.id],
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.electric_meter_outlined),
                          label: const Text('View energy details'),
                        ),
                      Text(
                        plugConnectionLabel(plug, hubConnected: _hubConnected),
                      ),
                      TextButton.icon(
                        onPressed: _statusChecking.contains(plug.id)
                            ? null
                            : () => _refreshPlugStatus(plug),
                        icon: _statusChecking.contains(plug.id)
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(
                          _statusChecking.contains(plug.id)
                              ? 'Checking plug…'
                              : 'Check plug connection',
                        ),
                      ),
                      if (_plugCheckFeedback[plug.id] case final result?)
                        Text(result),
                      Text(
                        plugConnectionDetail(plug),
                        style: theme.textTheme.bodySmall,
                      ),
                      _attachedApplianceSection(plug, theme),
                      TextButton(
                        onPressed: _busy ? null : () => _connectAppliance(plug),
                        child: Text(
                          _attachedApplianceIdentity(plug) == null
                              ? 'Identify connected appliance'
                              : 'Change connected appliance',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlugCandidateCard extends StatelessWidget {
  const _PlugCandidateCard({
    required this.candidate,
    required this.saved,
    required this.savedName,
    required this.onSave,
    required this.updateFeedback,
  });

  final DiscoveredPlug candidate;
  final bool saved;
  final String? savedName;
  final VoidCallback? onSave;
  final String? updateFeedback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noMeter = candidate.meterStatus == 'absent';
    return Card(
      child: ExpansionTile(
        leading: Icon(
          saved ? Icons.check_circle_outline : Icons.power_outlined,
          color: saved ? theme.colorScheme.primary : null,
        ),
        title: Text(
          savedName?.isNotEmpty == true
              ? savedName!
              : candidate.alias?.isNotEmpty == true
              ? candidate.alias!
              : candidate.model,
          style: theme.textTheme.titleMedium,
        ),
        subtitle: Text(
          '${candidate.ip} · ${noMeter
              ? 'No energy monitoring'
              : candidate.meterStatus == 'verified'
              ? 'Energy meter verified'
              : 'Energy meter unknown'}${saved ? ' · Saved' : ''}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Detected · ${noMeter
                ? 'No energy monitoring'
                : candidate.meterStatus == 'verified'
                ? 'Energy meter verified'
                : 'Energy meter unknown'}',
          ),
          Text(
            'Model ${candidate.model}${candidate.hardwareVersion == null ? '' : ' · Hardware ${candidate.hardwareVersion}'}',
          ),
          if (candidate.mac != null) Text('MAC ${candidate.mac}'),
          if (candidate.localProtocol == 'http')
            Text('Local API · HTTP ${candidate.httpPort ?? 80}'),
          if (candidate.relayOn != null)
            Text(
              'Switch ${candidate.relayOn! ? 'on' : 'off'} · This is not a power reading',
            ),
          const SizedBox(height: 8),
          Text(
            'Connected appliance or lamp',
            style: theme.textTheme.labelLarge,
          ),
          const Text(
            'Not identified yet. Add its model after saving the plug to estimate cost.',
          ),
          const SizedBox(height: 8),
          Text(
            saved
                ? 'Already saved on this hub'
                : 'Detected for this scan · Not saved yet',
            style: theme.textTheme.bodySmall,
          ),
          if (saved) ...[
            const SizedBox(height: 8),
            FilledButton(
              onPressed: onSave,
              child: const Text('Update plug connection'),
            ),
            if (updateFeedback != null) Text(updateFeedback!),
          ] else ...[
            const SizedBox(height: 8),
            FilledButton(
              onPressed: onSave,
              child: const Text('Save this plug'),
            ),
          ],
        ],
      ),
    );
  }
}
