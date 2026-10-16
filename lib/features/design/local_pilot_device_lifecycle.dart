import '../discovery/discovery_api.dart';
import '../discovery/discovery_credentials.dart';

enum LocalWriteStatus { confirmed, unresolved, failed }

class LocalInventory {
  const LocalInventory(
    this.identity,
    this.rows, {
    this.protocolDevices = const [],
    this.savedPlugs = const [],
  });
  final String identity;
  final List<SavedAppliance> rows;
  final List<NearbySavedDevice> protocolDevices;
  final List<SavedPlug> savedPlugs;
}

class LocalWriteResult {
  const LocalWriteResult(this.status, [this.inventory, this.appliance]);
  final LocalWriteStatus status;
  final LocalInventory? inventory;
  final SavedAppliance? appliance;
}

class LocalSaveSession {
  LocalSaveSession._(this._credential, this._beforeIds);
  final _HubCredential _credential;
  final Set<int> _beforeIds;
  bool _attempted = false;
  bool _busy = false;
  int? _returnedId;
  ApplianceInput? _input;
}

class _HubCredential {
  const _HubCredential(this.address, this.token, this.identity);
  final String address;
  final String token;
  final String identity;
}

/// The Hub is the sole source of saved local devices. A session can POST only
/// once; an uncertain response is reconciled against the pre-write inventory.
class LocalPilotDeviceLifecycle {
  LocalPilotDeviceLifecycle({
    this.api = const DiscoveryApi(),
    this.credentials = const DiscoveryCredentials(),
  });

  final DiscoveryApi api;
  final DiscoveryCredentials credentials;
  String? _lastCredential;
  LocalInventory? _lastInventory;
  int _revision = 0;

  Future<_HubCredential?> _credential() async {
    final (address, token) = await credentials.read();
    if (address == null || token == null || token.isEmpty) {
      if (_lastCredential != null) {
        _lastCredential = null;
        _revision++;
        _lastInventory = null;
      }
      return null;
    }
    final endpoint = HubEndpoint.parse(address);
    final pairing = await credentials.readPairing();
    final paired =
        pairing != null && pairing.address == address && pairing.token == token;
    if (paired) {
      await api.verifyStoredPairing(
        StoredHubIdentity(address: address, hubId: pairing.hubId),
      );
    }
    final key = '${paired ? pairing.hubId : endpoint.uri}|$address|$token';
    if (_lastCredential != key) {
      _lastCredential = key;
      _revision++;
      _lastInventory = null;
    }
    return _HubCredential(
      address,
      token,
      '${paired ? pairing.hubId : endpoint.uri}|$_revision',
    );
  }

  Future<bool> _isCurrent(_HubCredential expected) async {
    try {
      final current = await _credential();
      return current != null && current.identity == expected.identity;
    } catch (_) {
      return false;
    }
  }

  Future<LocalInventory?> inventory() async {
    _HubCredential? credential;
    try {
      credential = await _credential();
      if (credential == null) return null;
      final rows = await api.appliances(credential.address, credential.token);
      var protocolDevices = _lastInventory?.identity == credential.identity
          ? _lastInventory!.protocolDevices
          : const <NearbySavedDevice>[];
      var savedPlugs = _lastInventory?.identity == credential.identity
          ? _lastInventory!.savedPlugs
          : const <SavedPlug>[];
      try {
        savedPlugs = await api.saved(credential.address, credential.token);
      } catch (_) {
        // A legacy plug endpoint outage must not hide appliance inventory.
      }
      try {
        if (await api.supportsNearbyDiscovery(
          credential.address,
          credential.token,
        )) {
          protocolDevices = await api.nearbyInventory(
            credential.address,
            credential.token,
          );
        }
      } catch (_) {
        // A v2 outage must not hide existing manual/photo rows.
      }
      if (!await _isCurrent(credential)) return null;
      final inventory = LocalInventory(
        credential.identity,
        List.unmodifiable(rows),
        protocolDevices: List.unmodifiable(protocolDevices),
        savedPlugs: List.unmodifiable(savedPlugs),
      );
      _lastInventory = inventory;
      return inventory;
    } catch (_) {
      if (credential != null &&
          _lastInventory?.identity == credential.identity &&
          await _isCurrent(credential)) {
        return _lastInventory;
      }
      return null;
    }
  }

  Future<String?> currentIdentity() async {
    try {
      return (await _credential())?.identity;
    } catch (_) {
      return null;
    }
  }

  Future<LocalSaveSession?> beginSave(LocalInventory inventory) async {
    final credential = await _credential();
    if (credential == null || credential.identity != inventory.identity) {
      return null;
    }
    return LocalSaveSession._(
      credential,
      inventory.rows.map((row) => row.id).toSet(),
    );
  }

  Future<LocalWriteResult> save(
    LocalSaveSession session,
    ApplianceInput input,
  ) async {
    if (session._busy) {
      return const LocalWriteResult(LocalWriteStatus.unresolved);
    }
    session._busy = true;
    try {
      if (!await _isCurrent(session._credential)) {
        return const LocalWriteResult(LocalWriteStatus.failed);
      }
      if (session._attempted && !_sameInput(session._input, input)) {
        return const LocalWriteResult(LocalWriteStatus.failed);
      }
      if (!session._attempted) {
        session._attempted = true;
        session._input = input;
        try {
          final created = await api.addAppliance(
            session._credential.address,
            session._credential.token,
            input,
          );
          session._returnedId = created.id;
        } catch (_) {
          // A timeout may occur after the Hub commits. Never POST this session again.
        }
      }
      return await _reconcileSave(session);
    } finally {
      session._busy = false;
    }
  }

  Future<LocalWriteResult> _reconcileSave(LocalSaveSession session) async {
    final inventory = await this.inventory();
    if (inventory == null ||
        inventory.identity != session._credential.identity) {
      return const LocalWriteResult(LocalWriteStatus.unresolved);
    }
    final matches = inventory.rows
        .where(
          (row) =>
              (session._returnedId == null
                  ? !session._beforeIds.contains(row.id)
                  : row.id == session._returnedId) &&
              _matches(row, session._input!),
        )
        .toList();
    if (matches.length != 1) {
      return LocalWriteResult(LocalWriteStatus.unresolved, inventory);
    }
    return LocalWriteResult(
      LocalWriteStatus.confirmed,
      inventory,
      matches.single,
    );
  }

  Future<LocalWriteResult> delete(LocalInventory inventory, int id) async {
    final row = inventory.rows.where((row) => row.id == id).firstOrNull;
    if (row == null || !{'manual', 'photo'}.contains(row.onboardingMethod)) {
      return const LocalWriteResult(LocalWriteStatus.failed);
    }
    final credential = await _credential();
    if (credential == null || credential.identity != inventory.identity) {
      return const LocalWriteResult(LocalWriteStatus.failed);
    }
    try {
      await api.deleteManualAppliance(credential.address, credential.token, id);
    } catch (_) {
      // A lost response is resolved through list readback below.
    }
    final after = await this.inventory();
    if (after == null || after.identity != inventory.identity) {
      return const LocalWriteResult(LocalWriteStatus.unresolved);
    }
    return after.rows.any((row) => row.id == id)
        ? LocalWriteResult(LocalWriteStatus.failed, after)
        : LocalWriteResult(LocalWriteStatus.confirmed, after);
  }

  bool _sameInput(ApplianceInput? a, ApplianceInput b) =>
      a != null &&
      a.name == b.name &&
      a.category == b.category &&
      a.manufacturer == b.manufacturer &&
      a.model == b.model &&
      a.onboardingMethod == b.onboardingMethod;

  bool _matches(SavedAppliance row, ApplianceInput input) =>
      row.id > 0 &&
      row.name == input.name &&
      row.category == input.category &&
      row.manufacturer == input.manufacturer &&
      row.model == input.model &&
      row.onboardingMethod == input.onboardingMethod;
}
