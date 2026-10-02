class HubClaimChallenge {
  const HubClaimChallenge({
    required this.claimId,
    required this.hubId,
    required this.localHubId,
    required this.nonce,
    required this.expiresAt,
  });
  final String claimId;
  final String hubId;
  final String localHubId;
  final String nonce;
  final DateTime expiresAt;

  factory HubClaimChallenge.fromJson(Map<String, dynamic> json) {
    final claimId = json['claim_id'];
    final hubId = json['hub_id'];
    final localHubId = json['local_hub_id'];
    final nonce = json['nonce'];
    final expiresAt = DateTime.tryParse(
      json['expires_at'] is String ? json['expires_at'] as String : '',
    );
    if (claimId is! String ||
        hubId is! String ||
        localHubId is! String ||
        nonce is! String ||
        expiresAt == null) {
      throw const FormatException('Invalid hub claim challenge');
    }
    return HubClaimChallenge(
      claimId: claimId,
      hubId: hubId,
      localHubId: localHubId,
      nonce: nonce,
      expiresAt: expiresAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'claim_id': claimId,
    'hub_id': hubId,
    'local_hub_id': localHubId,
    'nonce': nonce,
    'expires_at': expiresAt.toUtc().toIso8601String(),
  };
}

class HubClaimProof {
  const HubClaimProof({
    required this.claimId,
    required this.localHubId,
    required this.possessionProof,
    required this.deviceSignature,
  });
  final String claimId;
  final String localHubId;
  final String possessionProof;
  final String deviceSignature;

  factory HubClaimProof.fromJson(Map<String, dynamic> json) {
    final claimId = json['claim_id'];
    final localHubId = json['local_hub_id'];
    final proof = json['possession_proof'];
    final signature = json['device_signature'];
    if (claimId is! String ||
        localHubId is! String ||
        proof is! String ||
        proof.length < 20 ||
        signature is! String ||
        signature.isEmpty) {
      throw const FormatException('Invalid hub claim proof');
    }
    return HubClaimProof(
      claimId: claimId,
      localHubId: localHubId,
      possessionProof: proof,
      deviceSignature: signature,
    );
  }

  Map<String, dynamic> toJson() => {
    'claim_id': claimId,
    'local_hub_id': localHubId,
    'possession_proof': possessionProof,
    'device_signature': deviceSignature,
  };
}

class HubOwnership {
  const HubOwnership({
    required this.hubId,
    required this.localHubId,
    required this.homeId,
    required this.ownershipEpoch,
    required this.version,
  });
  final String hubId;
  final String localHubId;
  final String homeId;
  final int ownershipEpoch;
  final int version;

  factory HubOwnership.fromJson(Map<String, dynamic> json) {
    if (json['hub_id'] is! String ||
        json['local_hub_id'] is! String ||
        json['home_id'] is! String ||
        json['ownership_epoch'] is! int ||
        json['version'] is! int) {
      throw const FormatException('Invalid hub ownership');
    }
    return HubOwnership(
      hubId: json['hub_id'] as String,
      localHubId: json['local_hub_id'] as String,
      homeId: json['home_id'] as String,
      ownershipEpoch: json['ownership_epoch'] as int,
      version: json['version'] as int,
    );
  }
}
