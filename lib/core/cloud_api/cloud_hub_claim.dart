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
    this.connection,
  });
  final String hubId;
  final String localHubId;
  final String homeId;
  final int ownershipEpoch;
  final int version;
  final HubConnection? connection;

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
      connection: HubConnection.tryParse(json['connection']),
    );
  }
}

/// Short-lived endpoint trust published by the current Hub over Cloud mTLS.
class HubConnection {
  const HubConnection({
    required this.httpsOrigin,
    required this.certificateSha256,
    required this.expiresAt,
  });

  final String httpsOrigin;
  final String certificateSha256;
  final DateTime expiresAt;

  bool get isFresh => expiresAt.isAfter(DateTime.now().toUtc());

  static HubConnection? tryParse(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final origin = value['https_origin'];
    final pin = value['certificate_sha256'];
    final expiry = value['expires_at'];
    if (origin is! String || pin is! String || expiry is! String) return null;
    final uri = Uri.tryParse(origin);
    final expiresAt = DateTime.tryParse(expiry);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(pin) ||
        expiresAt == null ||
        !expiresAt.isUtc) {
      return null;
    }
    return HubConnection(
      httpsOrigin: origin,
      certificateSha256: pin,
      expiresAt: expiresAt,
    );
  }
}
