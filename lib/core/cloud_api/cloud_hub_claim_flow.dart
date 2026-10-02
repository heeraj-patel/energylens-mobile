import '../../features/discovery/discovery_api.dart';
import '../../features/discovery/discovery_credentials.dart';
import 'cloud_api_client.dart';
import 'cloud_home.dart';
import 'cloud_hub_claim.dart';

/// Keeps the one-use hub proof and finish idempotency key for an uncertain retry.
class CloudHubClaimFlow {
  CloudHubClaimFlow({
    required this.cloud,
    required this.hub,
    required this.credentials,
  });

  final CloudApiClient cloud;
  final DiscoveryApi hub;
  final DiscoveryCredentials credentials;
  HubClaimProof? _pendingProof;
  String? _pendingKey;
  String? _pendingHomeId;

  bool get hasPendingFinish => _pendingProof != null;

  Future<HubOwnership> claim(CloudHome home) async {
    final pairing = await credentials.readPairing();
    if (pairing == null) {
      throw const PairingException(
        'Pair this phone with the hub before linking it to a cloud home.',
      );
    }
    if (!RegExp(r'^elhub_[A-Za-z0-9_-]+$').hasMatch(pairing.hubId)) {
      throw const PairingException(
        'The paired hub has no cloud-ready identity. Pair with a provisioned hub.',
      );
    }
    if (_pendingProof != null && _pendingHomeId != home.id) {
      throw const PairingException(
        'Finish the pending claim for the previous home before changing homes.',
      );
    }
    if (_pendingProof == null) {
      final challenge = await cloud.beginHubClaim(home.id, pairing.hubId);
      if (challenge.localHubId != pairing.hubId) {
        throw const PairingException(
          'Cloud returned a challenge for a different hub.',
        );
      }
      if (!challenge.expiresAt.isAfter(DateTime.now().toUtc())) {
        throw const PairingException('The cloud challenge expired. Try again.');
      }
      final proof = await hub.claimProof(
        challenge,
        address: pairing.address,
        hubId: pairing.hubId,
        token: pairing.token,
      );
      _pendingProof = proof;
      _pendingKey = newCloudIdempotencyKey();
      _pendingHomeId = home.id;
    }
    final ownership = await cloud.finishHubClaim(
      _pendingProof!,
      idempotencyKey: _pendingKey!,
    );
    if (ownership.homeId != home.id || ownership.localHubId != pairing.hubId) {
      throw const FormatException(
        'Cloud returned ownership for a different home or hub.',
      );
    }
    _pendingProof = null;
    _pendingKey = null;
    _pendingHomeId = null;
    return ownership;
  }
}
