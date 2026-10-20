import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_hub_claim.dart';
import '../design/local_pilot_device_lifecycle.dart';
import 'discovery_api.dart';
import 'discovery_credentials.dart';

/// Opportunistic identity and reachability refresh for already saved devices.
/// Energy measurements continue to come from the Hub poller and Cloud sync.
class DeviceDataRefresh {
  DeviceDataRefresh({
    this.api = const DiscoveryApi(),
    this.credentials = const DiscoveryCredentials(),
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
  }) : clock = clock ?? DateTime.now,
       delay = delay ?? Future<void>.delayed;

  final DiscoveryApi api;
  final DiscoveryCredentials credentials;
  final DateTime Function() clock;
  final Future<void> Function(Duration) delay;
  static const freshness = Duration(seconds: 60);
  static const _scanDeadline = Duration(seconds: 30);

  String _key(String scope) =>
      'energylens.device_refresh.v1.${sha256.convert(utf8.encode(scope))}';

  Future<bool> _isDue(String scope) async {
    final raw = await credentials.storage.read(_key(scope));
    if (raw == null) return true;
    try {
      final value = jsonDecode(raw) as Map<String, dynamic>;
      if (value['version'] != 1 || value['completed_at_ms'] is! int) {
        return true;
      }
      final completed = DateTime.fromMillisecondsSinceEpoch(
        value['completed_at_ms'] as int,
        isUtc: true,
      );
      final age = clock().toUtc().difference(completed);
      return age.isNegative || age > freshness;
    } catch (_) {
      return true;
    }
  }

  Future<void> _markComplete(
    String scope,
    Future<bool> Function() current,
  ) async {
    if (!await current()) return;
    final key = _key(scope);
    final value = jsonEncode({
      'version': 1,
      'completed_at_ms': clock().toUtc().millisecondsSinceEpoch,
    });
    await credentials.storage.write(key, value);
    if (!await current() && await credentials.storage.read(key) == value) {
      await credentials.storage.delete(key);
    }
  }

  /// Returns whether any Hub refresh was attempted. Individual Hub failures
  /// remain due on the next launch or resume and do not block other Hubs.
  Future<bool> refreshCloud({
    required CloudApiClient cloud,
    required String accountId,
    required String homeId,
    required bool Function() isCurrent,
  }) async {
    final generation = cloud.session.generation;
    final scope = OwnedPairingScope(
      origin: cloud.session.config.apiUrl,
      profile: cloud.session.credentialMethod,
      accountId: accountId,
      homeId: homeId,
    );
    bool current() => isCurrent() && cloud.session.generation == generation;
    if (!current()) return false;
    final ownerships = await cloud.hubs(homeId);
    if (!current()) return false;
    var attempted = false;
    for (final ownership in ownerships) {
      if (!current()) return attempted;
      if (ownership.homeId != homeId ||
          ownership.connection == null ||
          !ownership.connection!.isFresh) {
        continue;
      }
      try {
        var pairing = await credentials.readOwnedPairing(scope, ownership);
        if (!current()) return attempted;
        final connection = ownership.connection!;
        final publishedAddress =
            '${connection.httpsOrigin}#sha256=${connection.certificateSha256}';
        if (pairing != null && pairing.address != publishedAddress) {
          pairing = null;
        }
        if (pairing != null) {
          try {
            await api.verifyStoredPairing(
              StoredHubIdentity(address: pairing.address, hubId: pairing.hubId),
            );
          } catch (_) {
            pairing = null;
          }
        }
        if (!current()) return attempted;
        pairing ??= await _claimOwned(cloud, scope, ownership, current);
        if (pairing == null || !current()) continue;
        final activePairing = pairing;
        final durableScope =
            'cloud|${scope.identity}|${ownership.hubId}|${ownership.localHubId}|${ownership.ownershipEpoch}|${activePairing.address}|${activePairing.clientId}|${sha256.convert(utf8.encode(activePairing.token))}';
        if (!await _isDue(durableScope) || !current()) continue;
        attempted = true;
        final authorized = api.authorizedFor(
          HubOwnerAuthorization(
            session: cloud.session,
            homeId: homeId,
            isCurrent: current,
          ),
        );
        var completedPairing = activePairing;
        var complete = false;
        try {
          complete = await _refreshHub(
            authorized,
            activePairing.address,
            activePairing.token,
            () async => current(),
          );
        } on HubRequestException catch (error) {
          if (!error.requiresPairing || !current()) rethrow;
          // A revoked owner token gets one repair from the fresh Cloud hint.
          final repaired = await _claimOwned(cloud, scope, ownership, current);
          if (repaired != null && current()) {
            completedPairing = repaired;
            complete = await _refreshHub(
              authorized,
              repaired.address,
              repaired.token,
              () async => current(),
            );
          }
        }
        if (!current()) return attempted;
        final stillOwned = await credentials.readOwnedPairing(scope, ownership);
        if (!current()) return attempted;
        if (complete &&
            stillOwned?.address == completedPairing.address &&
            stillOwned?.token == completedPairing.token) {
          final completedScope = completedPairing == activePairing
              ? durableScope
              : 'cloud|${scope.identity}|${ownership.hubId}|${ownership.localHubId}|${ownership.ownershipEpoch}|${completedPairing.address}|${completedPairing.clientId}|${sha256.convert(utf8.encode(completedPairing.token))}';
          await _markComplete(completedScope, () async => current());
        }
      } catch (_) {
        // A failed Hub stays due; continue with the other owned Hubs.
      }
    }
    return attempted;
  }

  Future<StoredPairingCredential?> _claimOwned(
    CloudApiClient cloud,
    OwnedPairingScope scope,
    HubOwnership ownership,
    bool Function() current,
  ) async {
    final connection = ownership.connection;
    if (connection == null || !connection.isFresh || !current()) return null;
    final clientId = await credentials.ownedClientId(scope, ownership);
    if (!current()) return null;
    final claim = await api.claimOwnedPairing(
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
    await credentials.storeOwnedPairing(
      scope,
      ownership,
      pairing,
      isCurrent: current,
    );
    return current() ? pairing : null;
  }

  Future<bool> refreshLocal({
    required LocalPilotDeviceLifecycle lifecycle,
    required bool Function() isCurrent,
  }) async {
    final identity = await lifecycle.currentIdentity();
    if (identity == null || !isCurrent()) return false;
    final (address, token) = await lifecycle.credentials.read();
    if (address == null || token == null || token.isEmpty || !isCurrent()) {
      return false;
    }
    final pairing = await lifecycle.credentials.readPairing();
    Future<bool> current() async {
      if (!isCurrent() || await lifecycle.currentIdentity() != identity) {
        return false;
      }
      final (liveAddress, liveToken) = await lifecycle.credentials.read();
      if (!isCurrent() || liveAddress != address || liveToken != token) {
        return false;
      }
      final livePairing = await lifecycle.credentials.readPairing();
      return isCurrent() &&
          livePairing?.address == pairing?.address &&
          livePairing?.hubId == pairing?.hubId &&
          livePairing?.clientId == pairing?.clientId &&
          livePairing?.token == pairing?.token &&
          livePairing?.ownershipEpoch == pairing?.ownershipEpoch;
    }

    if (!await current()) return false;
    if (pairing != null &&
        pairing.address == address &&
        pairing.token == token) {
      await lifecycle.api.verifyStoredPairing(
        StoredHubIdentity(address: address, hubId: pairing.hubId),
      );
    }
    if (!await current()) return false;
    final scope =
        'local|$address|${pairing?.hubId ?? ''}|${pairing?.clientId ?? ''}|${pairing?.ownershipEpoch ?? ''}|${sha256.convert(utf8.encode(token))}';
    if (!await _isDue(scope) || !await current()) return false;
    final complete = await _refreshHub(lifecycle.api, address, token, current);
    if (complete && await current()) {
      await _markComplete(scope, current);
    }
    return true;
  }

  Future<bool> _refreshHub(
    DiscoveryApi hub,
    String address,
    String token,
    Future<bool> Function() current,
  ) async {
    try {
      final v2 = await hub.supportsNearbyDiscovery(address, token);
      if (!await current()) return false;
      if (v2) {
        final scan = await hub.startNearbyScan(address, token);
        var latest = scan;
        final deadline = clock().add(_scanDeadline);
        for (var i = 0; i < 60 && clock().isBefore(deadline); i++) {
          if (!await current()) return false;
          if (latest.nextCursor != null) {
            latest = await hub.nearbyScan(
              address,
              token,
              scan.id,
              cursor: latest.nextCursor,
            );
          } else if (!latest.isTerminal) {
            await delay(const Duration(seconds: 1));
            if (!await current()) return false;
            latest = await hub.nearbyScan(address, token, scan.id);
          } else {
            break;
          }
        }
        if (!await current() ||
            latest.nextCursor != null ||
            !const {'complete', 'partial'}.contains(latest.state)) {
          return false;
        }
        final devices = await hub.nearbyInventory(address, token);
        if (!await current()) return false;
        final refreshed = <String>{};
        var allSucceeded = latest.state == 'complete';
        for (final device in devices) {
          if (!await current()) return false;
          if (!refreshed.add(device.id)) continue;
          final binding = device.bindings.isEmpty
              ? null
              : device.bindings.first;
          if (binding != null &&
              (binding.protocol == 'upnp' ||
                  binding.adapterInstanceId == 'legacy-local')) {
            try {
              await hub.refreshNearbyDevice(address, token, device.id);
            } on HubRequestException catch (error) {
              if (error.requiresPairing) rethrow;
              allSucceeded = false;
            } catch (_) {
              allSucceeded = false;
            }
          }
        }
        if (!await current()) return false;
        final plugs = await hub.saved(address, token);
        if (!await current()) return false;
        if (!await _refreshLegacyPlugs(hub, address, token, plugs, current)) {
          allSucceeded = false;
        }
        if (!await current()) return false;
        await hub.nearbyInventory(address, token);
        if (!await current()) return false;
        await hub.saved(address, token);
        return await current() && allSucceeded;
      }
      await hub.scan(address, token);
      if (!await current()) return false;
      final plugs = await hub.saved(address, token);
      if (!await current()) return false;
      final allSucceeded = await _refreshLegacyPlugs(
        hub,
        address,
        token,
        plugs,
        current,
      );
      if (!await current()) return false;
      await hub.saved(address, token);
      return await current() && allSucceeded;
    } on HubRequestException catch (error) {
      if (error.requiresPairing) rethrow;
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _refreshLegacyPlugs(
    DiscoveryApi hub,
    String address,
    String token,
    List<SavedPlug> plugs,
    Future<bool> Function() current,
  ) async {
    final refreshed = <String>{};
    var allSucceeded = true;
    for (final plug in plugs) {
      if (!await current()) return false;
      if (!refreshed.add(plug.id)) continue;
      if (const {'legacy_tcp', 'http'}.contains(plug.localProtocol)) {
        try {
          final result = await hub.refreshPlugStatus(address, token, plug.id);
          if (result.id != plug.id) {
            allSucceeded = false;
          }
        } on HubRequestException catch (error) {
          if (error.requiresPairing) rethrow;
          allSucceeded = false;
        } catch (_) {
          allSucceeded = false;
        }
      }
    }
    return allSucceeded;
  }
}
