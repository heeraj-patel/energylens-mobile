import '../../core/cloud_api/cloud_api_client.dart';
import '../discovery/discovery_api.dart';
import '../discovery/discovery_credentials.dart';

class CloudSavedPlug {
  const CloudSavedPlug({
    required this.id,
    required this.name,
    required this.model,
  });
  final String id;
  final String name;
  final String model;
}

/// Reads legacy plugs only through pairings owned by the current Cloud home.
class CloudSavedPlugInventory {
  const CloudSavedPlugInventory({
    this.api = const DiscoveryApi(),
    this.credentials = const DiscoveryCredentials(),
  });

  final DiscoveryApi api;
  final DiscoveryCredentials credentials;

  Future<List<CloudSavedPlug>> read({
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
    if (!current()) return const [];
    final ownerships = await cloud.hubs(homeId);
    if (!current()) return const [];
    final result = <CloudSavedPlug>[];
    final seen = <String>{};
    for (final ownership in ownerships) {
      if (!current()) return const [];
      if (ownership.homeId != homeId) {
        throw const FormatException('Hub belongs to another home');
      }
      final pairing = await credentials.readOwnedPairing(scope, ownership);
      if (!current()) return const [];
      if (pairing == null) continue;
      late final List<SavedPlug> plugs;
      try {
        await api.verifyStoredPairing(
          StoredHubIdentity(address: pairing.address, hubId: pairing.hubId),
        );
        if (!current()) return const [];
        final authorized = api.authorizedFor(
          HubOwnerAuthorization(
            session: cloud.session,
            homeId: homeId,
            isCurrent: current,
          ),
        );
        plugs = await authorized.saved(pairing.address, pairing.token);
      } catch (_) {
        if (!current()) return const [];
        // One unavailable Hub does not hide plugs from other owned Hubs.
        continue;
      }
      if (!current()) return const [];
      final stillOwned = await credentials.readOwnedPairing(scope, ownership);
      if (!current()) return const [];
      if (stillOwned == null ||
          stillOwned.address != pairing.address ||
          stillOwned.hubId != pairing.hubId ||
          stillOwned.token != pairing.token) {
        return const [];
      }
      for (final plug in plugs) {
        if (plug.id.isEmpty) throw const FormatException('Invalid Hub plug ID');
        final id = '${ownership.localHubId}|${plug.id}';
        if (seen.add(id)) {
          result.add(
            CloudSavedPlug(id: id, name: plug.name, model: plug.model),
          );
        }
      }
    }
    return result;
  }
}
