import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../features/discovery/discovery_api.dart';
import '../../features/discovery/discovery_credentials.dart';
import '../../features/identify/onboarding_draft_store.dart';
import 'cloud_api_client.dart';
import 'cloud_home.dart';
import 'cloud_hub_claim.dart';
import '../backend_error.dart';

/// Keeps the one-use hub proof and finish idempotency key for an uncertain retry.
class CloudHubClaimFlow {
  static int _globalGeneration = 0;
  static Future<void> _storageTail = Future.value();
  static Future<T> _ordered<T>(Future<T> Function() action) {
    final result = _storageTail.then((_) => action());
    _storageTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  static Future<void> invalidatePendingClaims({
    OnboardingDraftStorage storage =
        const SecureOnboardingDraftStorage.hubClaim(),
  }) {
    _globalGeneration++;
    return _ordered(storage.clear);
  }

  CloudHubClaimFlow({
    required this.cloud,
    required this.hub,
    required this.credentials,
    this.scope,
    this.diagnosticSink,
    this.pendingStorage = const SecureOnboardingDraftStorage.hubClaim(),
  });

  final CloudApiClient cloud;
  final DiscoveryApi hub;
  final DiscoveryCredentials credentials;
  final OwnedPairingScope? scope;
  final void Function(String)? diagnosticSink;
  final OnboardingDraftStorage pendingStorage;
  HubClaimProof? _pendingProof;
  String? _pendingKey;
  String? _pendingHomeId;
  DateTime? _pendingExpiry;
  int? _instanceGeneration;

  bool get hasPendingFinish => _pendingProof != null;

  Future<HubOwnership> claim(CloudHome home) async {
    var stage = 'restore';
    void record(String event) {
      // Release diagnostics contain only fixed stage names, types and status
      // numbers. Never include identities, payloads, proofs or exception text.
      try {
        (diagnosticSink ?? debugPrint)('[hub.claim] $event');
      } catch (_) {
        // A diagnostic sink must not affect a claim or its retry state.
      }
    }

    void advance(String next) {
      stage = next;
      record('stage=$stage');
    }

    advance(stage);
    try {
      final ownership = await _claim(home, advance);
      record('stage=complete');
      return ownership;
    } catch (error) {
      final status = switch (error) {
        CloudApiException() => error.statusCode,
        PairingException() => error.statusCode,
        _ => null,
      };
      record(
        'stage=$stage outcome=failed type=${error.runtimeType}'
        '${status == null ? '' : ' status=$status'}',
      );
      rethrow;
    }
  }

  Future<HubOwnership> _claim(
    CloudHome home,
    void Function(String) advance,
  ) async {
    final generation = _globalGeneration;
    final sessionGeneration = cloud.session.generation;
    bool current() =>
        generation == _globalGeneration &&
        sessionGeneration == cloud.session.generation;
    if (_instanceGeneration != generation) {
      _pendingProof = null;
      _pendingKey = null;
      _pendingHomeId = null;
      _pendingExpiry = null;
      _instanceGeneration = generation;
    }
    final claimScope = scope;
    StoredPairingCredential? pairing;
    String? hubId;
    var expiredPendingClaim = false;
    if (claimScope != null) {
      if (claimScope.homeId != home.id) throw StateError('Claim scope changed');
      final raw = await _ordered(() => pendingStorage.read());
      if (!current()) throw StateError('Claim scope changed');
      if (raw != null) {
        try {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          final expiry = DateTime.parse(data['expires_at'] as String).toUtc();
          if (data['scope'] == claimScope.identity &&
              data['home_id'] == home.id &&
              data['hub_id'] is String) {
            hubId = data['hub_id'] as String;
            if (expiry.isAfter(DateTime.now().toUtc())) {
              _pendingProof = HubClaimProof.fromJson(
                data['proof'] as Map<String, dynamic>,
              );
              _pendingKey = data['operation_key'] as String;
              _pendingHomeId = home.id;
              _pendingExpiry = expiry;
            } else {
              expiredPendingClaim = true;
            }
          } else {
            await _ordered(
              () => current() ? pendingStorage.clear() : Future.value(),
            );
            _pendingProof = null;
            _pendingKey = null;
            _pendingHomeId = null;
            _pendingExpiry = null;
            throw StateError('Claim scope changed');
          }
        } on StateError {
          rethrow;
        } catch (_) {
          await _ordered(
            () => current() ? pendingStorage.clear() : Future.value(),
          );
        }
      }
    }
    if (hubId == null) {
      pairing = await credentials.readPairing();
      if (!current()) throw StateError('Claim scope changed');
      hubId = pairing?.hubId;
    }
    if (hubId == null) {
      throw const PairingException(
        'Pair this phone with the hub before linking it to a cloud home.',
      );
    }
    if (!RegExp(r'^elhub_[A-Za-z0-9_-]+$').hasMatch(hubId)) {
      throw const PairingException(
        'The paired hub has no cloud-ready identity. Pair with a provisioned hub.',
      );
    }
    if (claimScope != null) {
      advance('ownership_lookup');
      final owned = (await cloud.hubs(home.id))
          .where((value) => value.localHubId == hubId)
          .toList();
      if (!current()) throw StateError('Claim scope changed');
      if (owned.length > 1) {
        throw const FormatException('Duplicate hub ownership');
      }
      if (owned.isNotEmpty) {
        _pendingProof = null;
        _pendingKey = null;
        _pendingHomeId = null;
        _pendingExpiry = null;
        await _ordered(
          () => current() ? pendingStorage.clear() : Future.value(),
        );
        return owned.single;
      }
    }
    if (expiredPendingClaim) {
      _pendingProof = null;
      _pendingKey = null;
      _pendingHomeId = null;
      _pendingExpiry = null;
      await _ordered(() => current() ? pendingStorage.clear() : Future.value());
      throw StateError('Hub claim challenge expired');
    }
    if (_pendingProof != null && _pendingHomeId != home.id) {
      throw const PairingException(
        'Finish the pending claim for the previous home before changing homes.',
      );
    }
    if (_pendingProof == null) {
      pairing ??= await credentials.readPairing();
      if (!current()) throw StateError('Claim scope changed');
      if (pairing == null || pairing.hubId != hubId) {
        throw const PairingException(
          'Pair this phone with the hub before linking it to a cloud home.',
        );
      }
      advance('begin_claim');
      final challenge = await cloud.beginHubClaim(home.id, hubId);
      if (!current()) throw StateError('Claim scope changed');
      if (challenge.localHubId != hubId) {
        throw const PairingException(internalErrorMessage);
      }
      if (!challenge.expiresAt.isAfter(DateTime.now().toUtc())) {
        throw const PairingException(internalErrorMessage);
      }
      advance('hub_proof');
      final proof = await hub.claimProof(
        challenge,
        address: pairing.address,
        hubId: hubId,
        token: pairing.token,
      );
      if (!current()) throw StateError('Claim scope changed');
      _pendingProof = proof;
      _pendingKey = newCloudIdempotencyKey();
      _pendingHomeId = home.id;
      _pendingExpiry = challenge.expiresAt;
      if (claimScope != null) {
        advance('persist_finish');
        await _ordered(
          () => current()
              ? pendingStorage.write(
                  jsonEncode({
                    'scope': claimScope.identity,
                    'home_id': home.id,
                    'hub_id': hubId,
                    'claim_id': proof.claimId,
                    'expires_at': challenge.expiresAt.toUtc().toIso8601String(),
                    'operation_key': _pendingKey,
                    'proof': proof.toJson(),
                  }),
                )
              : Future.value(),
        );
        if (!current()) throw StateError('Claim scope changed');
      }
    }
    if (_pendingExpiry != null &&
        !_pendingExpiry!.isAfter(DateTime.now().toUtc())) {
      _pendingProof = null;
      _pendingKey = null;
      _pendingHomeId = null;
      _pendingExpiry = null;
      if (claimScope != null) {
        await _ordered(
          () => current() ? pendingStorage.clear() : Future.value(),
        );
      }
      throw StateError('Hub claim challenge expired');
    }
    advance('finish_claim');
    final ownership = await cloud.finishHubClaim(
      _pendingProof!,
      idempotencyKey: _pendingKey!,
    );
    if (!current()) throw StateError('Claim scope changed');
    advance('validate_ownership');
    if (ownership.homeId != home.id || ownership.localHubId != hubId) {
      throw const FormatException(
        'Cloud returned ownership for a different home or hub.',
      );
    }
    _pendingProof = null;
    _pendingKey = null;
    _pendingHomeId = null;
    _pendingExpiry = null;
    if (claimScope != null) {
      await _ordered(() => current() ? pendingStorage.clear() : Future.value());
    }
    return ownership;
  }
}
