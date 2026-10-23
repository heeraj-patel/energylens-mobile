import 'dart:async';
import 'dart:convert';

import 'package:energylens_mobile/core/cloud_api/cloud_api_client.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_home.dart';
import 'package:energylens_mobile/core/cloud_api/cloud_hub_claim.dart';
import 'package:energylens_mobile/core/cloud_auth/cloud_auth.dart';
import 'package:energylens_mobile/features/discovery/discovery_api.dart';
import 'package:energylens_mobile/features/discovery/discovery_credentials.dart';
import 'package:energylens_mobile/features/discovery/discovery_screen.dart';
import 'package:energylens_mobile/features/discovery/device_energy_detail_screen.dart';
import 'package:energylens_mobile/features/identify/appliance_onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const bool _testDeveloperMode =
    String.fromEnvironment('DEVELOPER_MODE') == 'TRUE';

const _cloudHomeId = '11111111-1111-4111-8111-111111111111';
const _cloudHubId = '22222222-2222-4222-8222-222222222222';
const _cloudSensorId = '33333333-3333-4333-8333-333333333333';
const _localHubId = 'elhub_test-hub';
const _cloudConfig = CloudAuthConfig(
  issuer: 'https://issuer.example',
  audience: 'audience',
  clientId: 'client',
  redirectUrl: 'io.energylens.app://login-callback',
  apiUrl: 'https://api.example',
);

class _TestTokenStore implements CloudTokenStore {
  @override
  Future<void> clear() async {}
  @override
  Future<CloudTokens?> read() async => const CloudTokens(accessToken: 'token');
  @override
  Future<void> save(CloudTokens tokens) async {}
}

class _TestAuthenticator implements CloudAuthenticator {
  @override
  Future<CloudTokens> signIn(CloudAuthConfig config) async =>
      const CloudTokens(accessToken: 'token');
  @override
  Future<CloudTokens> refresh(
    CloudAuthConfig config,
    String refreshToken,
  ) async => const CloudTokens(accessToken: 'token');
}

class _ClaimCredentials extends FakeCredentials {
  @override
  Future<StoredPairingCredential?> readOwnedPairing(
    OwnedPairingScope scope,
    HubOwnership ownership,
  ) async =>
      ownership.localHubId == _localHubId && ownership.ownershipEpoch == 3
      ? const StoredPairingCredential(
          address: 'https://192.168.1.20:8787#sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          hubId: _localHubId,
          clientId: 'client-1',
          token: 'issued-token',
          ownershipEpoch: 3,
        )
      : null;
  @override
  Future<StoredPairingCredential?> readPairing() async =>
      const StoredPairingCredential(
        address: 'https://192.168.1.20:8787#sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        hubId: _localHubId,
        clientId: 'client-1',
        token: 'issued-token',
      );
}

class _FirstClaimCredentials extends FakeCredentials {
  _FirstClaimCredentials({this.pendingLegacy});
  final Completer<StoredPairingCredential?>? pendingLegacy;
  StoredPairingCredential? ownedPairing;
  static const legacyPairing = StoredPairingCredential(
    address: 'https://192.168.1.20:8787#sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    hubId: _localHubId,
    clientId: 'client-1',
    token: 'bootstrap-token',
  );

  @override
  Future<StoredPairingCredential?> readPairing() =>
      pendingLegacy?.future ?? Future.value(legacyPairing);

  @override
  Future<StoredPairingCredential?> readOwnedPairing(
    OwnedPairingScope scope,
    HubOwnership ownership,
  ) async => ownedPairing;
}

class _FirstClaimApi extends _ClaimDiscoveryApi {
  int customerReads = 0;
  int identityChecks = 0;
  bool failCustomerReads = false;

  @override
  Future<void> verifyStoredPairing(StoredHubIdentity pairing) async {
    identityChecks++;
  }

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async {
    customerReads++;
    if (failCustomerReads) {
      throw HubRequestException(503, 'unavailable', 'Hub unavailable');
    }
    return const [];
  }

  @override
  Future<bool> supportsNearbyDiscovery(String baseUrl, String token) async {
    customerReads++;
    return false;
  }
}

class _ClaimDiscoveryApi extends SavingApi {
  @override
  DiscoveryApi authorizedFor(HubOwnerAuthorization owner) => this;
  @override
  Future<void> verifyStoredPairing(StoredHubIdentity pairing) async {}

  @override
  Future<List<DiscoveredPlug>> scan(String baseUrl, String token) async => [
    const DiscoveredPlug(
      id: 'stable-local-plug-1',
      ip: '192.168.1.42',
      model: 'HS110',
      alias: 'Office meter',
      meterStatus: 'verified',
      relayOn: true,
    ),
  ];

  @override
  Future<SavedPlug> adopt(
    String baseUrl,
    String token,
    DiscoveredPlug candidate,
    String name,
    String room,
    bool acknowledgeNoMeter,
  ) async {
    plug = SavedPlug(
      id: candidate.id,
      ip: candidate.ip,
      model: candidate.model,
      name: name,
      room: room,
      meterStatus: candidate.meterStatus,
      lastVerifiedAt: 100,
    );
    return plug!;
  }

  @override
  Future<HubClaimProof> claimProof(
    HubClaimChallenge challenge, {
    required String address,
    required String hubId,
    required String token,
  }) async => HubClaimProof(
    claimId: challenge.claimId,
    localHubId: hubId,
    possessionProof: 'p' * 24,
    deviceSignature: 'signature',
  );
}

class _AutoPairDiscoveryApi extends _ClaimDiscoveryApi {
  int claims = 0;
  int scans = 0;
  int savedReads = 0;
  String? rejectionCode;
  bool rejectAllPairings = false;
  Future<void> Function()? beforeClaimResponse;
  Object? claimError;

  _AutoPairDiscoveryApi() {
    plug = const SavedPlug(
      id: 'saved-plug',
      ip: '192.168.1.42',
      model: 'HS103',
      name: 'Saved office plug',
      room: 'Office',
      meterStatus: 'absent',
      lastVerifiedAt: 100,
    );
  }

  @override
  Future<PairingClaim> claimOwnedPairing(
    HubOwnership ownership, {
    required String clientId,
    required HubOwnerAuthorization owner,
  }) async {
    claims++;
    await beforeClaimResponse?.call();
    if (claimError != null) throw claimError!;
    return PairingClaim(
      hubId: ownership.localHubId,
      clientId: clientId,
      token: 'auto-paired-token',
      ownershipEpoch: ownership.ownershipEpoch,
    );
  }

  @override
  Future<List<DiscoveredPlug>> scan(String baseUrl, String token) async {
    scans++;
    return [];
  }

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async {
    savedReads++;
    if (rejectionCode != null &&
        (token == 'stale-token' || rejectAllPairings)) {
      throw HubRequestException(401, rejectionCode, 'Rejected');
    }
    return super.saved(baseUrl, token);
  }
}

class _ForbiddenPairingTransport implements PairingTransport {
  @override
  Future<PairingHttpResponse> send(
    String address,
    String path,
    String method, {
    Map<String, dynamic>? body,
    String? bearerToken,
  }) async {
    if (path == '/healthz') {
      return PairingHttpResponse(
        statusCode: 200,
        body: jsonEncode({'hub_id': _localHubId}),
      );
    }
    return PairingHttpResponse(
      statusCode: 403,
      body: jsonEncode({
        'error': {'message': 'Owner access refused.'},
      }),
    );
  }
}

class _RealClaimDiscoveryApi extends _AutoPairDiscoveryApi {
  final _real = DiscoveryApi(pairingTransport: _ForbiddenPairingTransport());

  @override
  Future<PairingClaim> claimOwnedPairing(
    HubOwnership ownership, {
    required String clientId,
    required HubOwnerAuthorization owner,
  }) {
    claims++;
    return _real.claimOwnedPairing(ownership, clientId: clientId, owner: owner);
  }
}

class _AutoPairStore implements SecureKeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class FakeDiscoveryApi extends DiscoveryApi {
  const FakeDiscoveryApi();

  @override
  Future<bool> supportsNearbyDiscovery(String baseUrl, String token) async =>
      false;

  @override
  Future<ElectricitySettings> electricitySettings(
    String baseUrl,
    String token,
  ) async => const ElectricitySettings();

  @override
  Future<ElectricitySettings> updateElectricitySettings(
    String baseUrl,
    String token, {
    required String? postalCode,
    required double? rateUsdPerKwh,
  }) async =>
      ElectricitySettings(postalCode: postalCode, rateUsdPerKwh: rateUsdPerKwh);

  @override
  Future<List<DiscoveredPlug>> scan(String baseUrl, String token) async => [
    const DiscoveredPlug(
      id: 'plug-1',
      ip: '192.168.1.42',
      model: 'HS103',
      alias: 'Desk plug',
      mac: '00:31:92:43:c5:28',
      localProtocol: 'http',
      httpPort: 80,
      meterStatus: 'absent',
      relayOn: true,
    ),
  ];
}

class PersistingSettingsApi extends FakeDiscoveryApi {
  ElectricitySettings settings = const ElectricitySettings();

  @override
  Future<ElectricitySettings> electricitySettings(
    String baseUrl,
    String token,
  ) async => settings;

  @override
  Future<ElectricitySettings> updateElectricitySettings(
    String baseUrl,
    String token, {
    required String? postalCode,
    required double? rateUsdPerKwh,
  }) async {
    settings = ElectricitySettings(
      postalCode: postalCode,
      rateUsdPerKwh: rateUsdPerKwh,
    );
    return settings;
  }
}

class FakeCredentials extends DiscoveryCredentials {
  String? address;
  String? token;

  @override
  Future<StoredPairingCredential?> readPairing() async => null;

  @override
  Future<(String?, String?)> read() async => (address, token);

  @override
  Future<void> save(String address, String token) async {
    this.address = address;
    this.token = token;
  }

  @override
  Future<String?> readPostalCode({OwnedPairingScope? scope}) async => null;

  @override
  Future<void> savePostalCode(
    String postalCode, {
    OwnedPairingScope? scope,
  }) async {}
}

class OfflinePairedCredentials extends FakeCredentials {
  @override
  Future<StoredPairingCredential?> readPairing() async =>
      const StoredPairingCredential(
        address: 'https://192.168.1.20:8787#sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        hubId: 'hub-1',
        clientId: 'client-1',
        token: 'issued-token',
      );
}

class OfflinePairingApi extends FakeDiscoveryApi {
  int checks = 0;

  @override
  Future<void> verifyStoredPairing(StoredHubIdentity pairing) async {
    checks++;
    throw const PairingException('Hub temporarily unavailable.');
  }
}

class SavingApi extends FakeDiscoveryApi {
  SavedPlug? plug;
  int estimateCalls = 0;
  int statusRefreshCalls = 0;
  String refreshedStatus = 'connected';
  final appliance = const SavedAppliance(
    id: 7,
    name: 'Desk lamp',
    room: 'Office',
    category: 'lighting',
    manufacturer: 'Example',
    model: 'L123',
    loadKind: 'replaceable_bulb',
    onboardingMethod: 'manual',
  );

  @override
  Future<SavedPlug> adopt(
    String baseUrl,
    String token,
    DiscoveredPlug candidate,
    String name,
    String room,
    bool acknowledgeNoMeter,
  ) async {
    expect(acknowledgeNoMeter, isTrue);
    plug = SavedPlug(
      id: candidate.id,
      ip: candidate.ip,
      model: candidate.model,
      name: name,
      room: room,
      meterStatus: candidate.meterStatus,
      lastVerifiedAt: 100,
      mac: candidate.mac,
      localProtocol: candidate.localProtocol,
      httpPort: candidate.httpPort,
    );
    return plug!;
  }

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async =>
      plug == null ? [] : [plug!];

  @override
  Future<SavedPlug> refreshPlugStatus(
    String baseUrl,
    String token,
    String plugId,
  ) async {
    statusRefreshCalls++;
    final before = plug!;
    expect(plugId, before.id);
    plug = SavedPlug(
      id: before.id,
      ip: before.ip,
      model: before.model,
      name: before.name,
      room: before.room,
      meterStatus: before.meterStatus,
      lastVerifiedAt: before.lastVerifiedAt,
      connectionStatus: refreshedStatus,
      statusCheckedAt: 200,
      connectedAppliance: before.connectedAppliance,
    );
    return plug!;
  }

  @override
  Future<List<SavedAppliance>> appliances(String baseUrl, String token) async =>
      [appliance];

  @override
  Future<SavedPlug> attachAppliance(
    String baseUrl,
    String token,
    String plugId,
    int applianceId,
  ) async {
    expect(plugId, 'plug-1');
    expect(applianceId, 7);
    final before = plug!;
    plug = SavedPlug(
      id: before.id,
      ip: before.ip,
      model: before.model,
      name: before.name,
      room: before.room,
      meterStatus: before.meterStatus,
      lastVerifiedAt: before.lastVerifiedAt,
      mac: before.mac,
      localProtocol: before.localProtocol,
      httpPort: before.httpPort,
      connectedAppliance: appliance,
    );
    return plug!;
  }

  @override
  Future<EnergyEstimate> estimate(
    String baseUrl,
    String token,
    int applianceId, {
    double? rateUsdPerKwh,
    String? postalCode,
  }) async {
    estimateCalls++;
    return const EnergyEstimate(status: 'no_estimate', reason: 'not_checked');
  }
}

class _DeletingSavedApi extends FakeDiscoveryApi {
  final plugs = <SavedPlug>[
    const SavedPlug(
      id: 'plug-a',
      ip: '192.168.1.41',
      model: 'HS103',
      name: 'First plug',
      room: 'Office',
      meterStatus: 'absent',
      lastVerifiedAt: 100,
    ),
    const SavedPlug(
      id: 'plug-b',
      ip: '192.168.1.42',
      model: 'HS103',
      name: 'Second plug',
      room: 'Office',
      meterStatus: 'absent',
      lastVerifiedAt: 100,
    ),
  ];
  final deleted = <String>[];
  final savedReads = <String>[];
  final nearbyReads = <String>[];
  final queuedSavedReads = <Completer<List<SavedPlug>>>[];
  final queuedNearbyReads = <Completer<List<NearbySavedDevice>>>[];
  bool savedReadFails = false;
  bool nearbyEnabled = false;
  Completer<void>? pending;
  bool fail = false;

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async {
    savedReads.add(baseUrl);
    if (queuedSavedReads.isNotEmpty) return queuedSavedReads.removeAt(0).future;
    if (savedReadFails) throw StateError('Refresh failed');
    return List.of(plugs);
  }

  @override
  Future<bool> supportsNearbyDiscovery(String baseUrl, String token) async =>
      nearbyEnabled;

  @override
  Future<List<NearbySavedDevice>> nearbyInventory(
    String baseUrl,
    String token,
  ) async {
    nearbyReads.add(baseUrl);
    if (queuedNearbyReads.isNotEmpty) {
      return queuedNearbyReads.removeAt(0).future;
    }
    return [for (final plug in plugs) NearbySavedDevice(plug.id, plug.name)];
  }

  @override
  Future<void> deleteSavedPlug(
    String baseUrl,
    String token,
    String plugId,
  ) async {
    deleted.add(plugId);
    if (pending case final operation?) await operation.future;
    if (fail) throw StateError('Hub failed');
    plugs.removeWhere((plug) => plug.id == plugId);
  }
}

class _FixtureApplianceApi extends SavingApi {
  _FixtureApplianceApi({required String manufacturer, required String model})
    : _appliance = SavedAppliance(
        id: 8,
        name: 'Living room fan',
        room: 'Living room',
        category: 'fan',
        manufacturer: manufacturer,
        model: model,
        loadKind: 'appliance',
        onboardingMethod: 'manual',
      );

  final SavedAppliance _appliance;

  @override
  SavedAppliance get appliance => _appliance;
}

class FailingSettingsApi extends SavingApi {
  @override
  Future<ElectricitySettings> electricitySettings(
    String baseUrl,
    String token,
  ) async => throw StateError('settings unavailable');
}

class DeviceDetailApi extends FakeDiscoveryApi {
  int estimateCalls = 0;
  final appliance = const SavedAppliance(
    id: 31,
    name: 'Desk fan',
    room: 'Office',
    category: 'fan',
    manufacturer: 'Example',
    model: 'F100',
    loadKind: 'appliance',
    onboardingMethod: 'manual',
  );

  @override
  Future<ApplianceSpec> applianceSpec(
    String baseUrl,
    String token,
    int applianceId,
  ) async => const ApplianceSpec(status: 'not_found');

  @override
  Future<List<SavedPlug>> saved(String baseUrl, String token) async => [
    SavedPlug(
      id: 'plug-detail',
      ip: '192.168.1.42',
      model: 'HS110',
      name: 'Office meter',
      room: 'Office',
      meterStatus: 'verified',
      lastVerifiedAt: 100,
      connectedAppliance: appliance,
    ),
  ];

  @override
  Future<EnergyEstimate> estimate(
    String baseUrl,
    String token,
    int applianceId, {
    double? rateUsdPerKwh,
    String? postalCode,
  }) async {
    estimateCalls++;
    return const EnergyEstimate(
      status: 'estimated',
      estimatedKwh: 18,
      estimatedCostUsd: 3.24,
      evidence: EnergyEvidence(
        sourceKind: 'epa_exact',
        datasetId: 'epa-ratings',
        sourceUrl: 'https://example.test/fan',
        matchedBrand: 'Example',
        matchedModel: 'F100',
        annualKwh: 200,
        usageBasis: 'rated',
        retrievedAt: 1,
      ),
    );
  }

  @override
  Future<DeviceEnergy> deviceEnergy(
    String baseUrl,
    String token,
    String plugId, {
    String period = 'day',
    String? timezone,
    String? postalCode,
    double? rateUsdPerKwh,
  }) async => const DeviceEnergy(
    status: 'measured',
    period: 'day',
    totalKwh: 0.2,
    coverageFraction: 0.5,
    coveredSecs: 43200,
    latestWatts: null,
    observedCostUsd: 0.04,
    rateSourceLabel: 'Your electricity rate',
    rateUsdPerKwh: 0.2,
    rateSource: 'user',
    readingCount: 2,
  );
}

class NameplateDetailApi extends DeviceDetailApi {
  @override
  Future<ApplianceSpec> applianceSpec(
    String baseUrl,
    String token,
    int applianceId,
  ) async {
    expect(applianceId, 31);
    return const ApplianceSpec(
      status: 'matched',
      evidence: ApplianceSpecEvidence(
        sourceKind: 'oem_rated_input',
        ratedInputWatts: 1350,
        sourceUrl: 'https://example.test/manual.pdf',
        matchedBrand: 'Example',
        matchedModel: 'F100',
        usageBasis: 'Nameplate input',
        retrievedAt: 1790000000,
      ),
    );
  }
}

class MeasuredEstimateApi extends DeviceDetailApi {
  @override
  Future<EnergyEstimate> estimate(
    String baseUrl,
    String token,
    int applianceId, {
    double? rateUsdPerKwh,
    String? postalCode,
  }) async {
    estimateCalls++;
    return const EnergyEstimate(
      status: 'measured',
      estimatedKwh: 12.5,
      estimatedCostUsd: 4.5,
      rateSource: 'utility',
      rateUsdPerKwh: 0.36,
      rateSourceLabel: 'Texas average',
      rateAsOf: '2026-01-01',
      rateStatus: 'stale',
      isStale: true,
      measurementCoverageFraction: 0.35,
    );
  }
}

class TimestampApi extends DeviceDetailApi {
  @override
  Future<DeviceEnergy> deviceEnergy(
    String baseUrl,
    String token,
    String plugId, {
    String period = 'day',
    String? timezone,
    String? postalCode,
    double? rateUsdPerKwh,
  }) async => DeviceEnergy(
    status: 'measured',
    period: period,
    totalKwh: 0.2,
    coverageFraction: 0.5,
    coveredSecs: 43200,
    latestWatts: 42,
    readingCount: 1,
    readings: [EnergyReading(ts: DateTime.utc(2026, 9, 29, 12), watts: 42)],
  );
}

class OfflineEstimateApi extends DeviceDetailApi {
  @override
  Future<EnergyEstimate> estimate(
    String baseUrl,
    String token,
    int applianceId, {
    double? rateUsdPerKwh,
    String? postalCode,
  }) async => throw StateError('hub unavailable');
}

class PeriodRaceApi extends DeviceDetailApi {
  final day = Completer<DeviceEnergy>();

  @override
  Future<DeviceEnergy> deviceEnergy(
    String baseUrl,
    String token,
    String plugId, {
    String period = 'day',
    String? timezone,
    String? postalCode,
    double? rateUsdPerKwh,
  }) async {
    if (period == 'day') return day.future;
    return const DeviceEnergy(
      status: 'measured',
      period: 'week',
      totalKwh: 0.7,
      coverageFraction: 0.5,
      coveredSecs: 302400,
      latestWatts: 70,
      readingCount: 2,
    );
  }
}

class _OwnerHeaderApi extends _AutoPairDiscoveryApi {
  _OwnerHeaderApi({this.owner, List<String>? reads}) : reads = reads ?? [];
  final HubOwnerAuthorization? owner;
  final List<String> reads;

  @override
  DiscoveryApi authorizedFor(HubOwnerAuthorization owner) =>
      _OwnerHeaderApi(owner: owner, reads: reads)..plug = plug;

  @override
  Future<DeviceEnergy> deviceEnergy(
    String baseUrl,
    String token,
    String plugId, {
    String period = 'day',
    String? timezone,
    String? postalCode,
    double? rateUsdPerKwh,
  }) async {
    if (owner == null) {
      throw HubRequestException(
        403,
        'forbidden',
        'Home authorization is required',
      );
    }
    reads.add('${owner!.homeId}:$plugId');
    return const DeviceEnergy(
      status: 'measured',
      period: 'day',
      totalKwh: 0.2,
      coverageFraction: 0.5,
      coveredSecs: 43200,
      latestWatts: null,
      observedCostUsd: 0.04,
      rateSourceLabel: 'Your electricity rate',
      rateUsdPerKwh: 0.2,
      rateSource: 'user',
      readingCount: 2,
    );
  }
}

void main() {
  for (final scenario in [
    'clean',
    'session-change',
    'revoked',
    'invalid-session',
    'still-revoked',
  ]) {
    final switchSession = scenario == 'session-change';
    testWidgets('Auto-scan owner pairing: $scenario', (tester) async {
      final api = _AutoPairDiscoveryApi();
      final store = _AutoPairStore();
      final session = CloudSession(
        config: _cloudConfig,
        store: _TestTokenStore(),
        authenticator: _TestAuthenticator(),
      );
      final cloud = CloudApiClient(
        session: session,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/hubs')) {
            return http.Response(
              jsonEncode({
                'hubs': [
                  {
                    'hub_id': _cloudHubId,
                    'local_hub_id': _localHubId,
                    'home_id': _cloudHomeId,
                    'ownership_epoch': 3,
                    'version': 1,
                    'connection': {
                      'https_origin': 'https://192.168.1.20:18787',
                      'certificate_sha256': 'a' * 64,
                      'expires_at': DateTime.now()
                          .toUtc()
                          .add(const Duration(minutes: 5))
                          .toIso8601String(),
                    },
                  },
                ],
              }),
              200,
            );
          }
          return http.Response('{"sensors":[]}', 200);
        }),
      );
      if (['revoked', 'invalid-session', 'still-revoked'].contains(scenario)) {
        api.rejectionCode = scenario == 'invalid-session'
            ? 'unauthorized'
            : 'requires_pairing';
        api.rejectAllPairings = scenario == 'still-revoked';
        await DiscoveryCredentials(storage: store).storeOwnedPairing(
          OwnedPairingScope(
            origin: _cloudConfig.apiUrl,
            profile: session.credentialMethod,
            accountId: 'account-a',
            homeId: _cloudHomeId,
          ),
          const HubOwnership(
            hubId: _cloudHubId,
            localHubId: _localHubId,
            homeId: _cloudHomeId,
            ownershipEpoch: 3,
            version: 1,
          ),
          const StoredPairingCredential(
            address: 'https://192.168.1.20:18787#sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            hubId: _localHubId,
            clientId: 'old-client',
            token: 'stale-token',
            ownershipEpoch: 3,
          ),
        );
      }
      if (switchSession)
        api.beforeClaimResponse = () =>
            session.selectCredentialMethod('username_password');
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(
            api: api,
            credentials: DiscoveryCredentials(storage: store),
            autoScan: true,
            cloudApi: cloud,
            accountId: 'account-a',
            cloudHome: const CloudHome(
              id: _cloudHomeId,
              name: 'Selected home',
              timezone: 'America/Chicago',
              countryCode: 'US',
              postalCode: '60601',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.claims, scenario == 'invalid-session' ? 0 : 1);
      if (switchSession) {
        expect(api.scans, 0);
        expect(
          store.values.values.any((v) => v.contains('auto-paired-token')),
          isFalse,
        );
        expect(find.text('Hub connected'), findsNothing);
      } else if (scenario == 'invalid-session' || scenario == 'still-revoked') {
        expect(api.scans, 0);
        expect(api.savedReads, scenario == 'invalid-session' ? 1 : 2);
        expect(find.text('Hub connected'), findsNothing);
      } else {
        expect(api.scans, 1);
        expect(find.text('Hub connected'), findsOneWidget);
        if (_testDeveloperMode) {
          await tester.tap(find.text('Connection details'));
          await tester.pumpAndSettle();
          expect(find.text('Pair with a different hub'), findsOneWidget);
          expect(find.textContaining('Paired hub:'), findsOneWidget);
          expect(find.text('Paired hub address'), findsOneWidget);
        } else {
          expect(find.text('Connection details'), findsNothing);
          expect(find.text('Pair with a different hub'), findsNothing);
          expect(find.textContaining('Paired hub:'), findsNothing);
          expect(find.text('Paired hub address'), findsNothing);
        }
        expect(find.text('Link paired hub to home'), findsNothing);
        expect(find.textContaining('Link this paired hub'), findsNothing);
        expect(
          find.textContaining('Pair this phone with the hub'),
          findsNothing,
        );
        await tester.scrollUntilVisible(
          find.text('Saved office plug'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Saved office plug'), findsOneWidget);
        expect(
          store.values.values.any((v) => v.contains('auto-paired-token')),
          isTrue,
        );
        expect(store.values.containsKey('energylens.hub.pairing'), isFalse);
      }
      expect(find.byKey(const Key('operatorPairingJson')), findsNothing);
      cloud.close();
    });
  }
  for (final scenario in ['forbidden', 'unreachable', 'no-hint']) {
    testWidgets('Hub access message for auto-pair failure: $scenario', (
      tester,
    ) async {
      final api = scenario == 'forbidden'
          ? _RealClaimDiscoveryApi()
          : _AutoPairDiscoveryApi();
      if (scenario == 'forbidden') {
        // The real claim path decodes the 403 from the fake transport.
      } else if (scenario == 'unreachable') {
        api.claimError = StateError('hub unreachable');
      }
      final cloud = CloudApiClient(
        session: CloudSession(
          config: _cloudConfig,
          store: _TestTokenStore(),
          authenticator: _TestAuthenticator(),
        ),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/hubs')) {
            return http.Response(
              jsonEncode({
                'hubs': [
                  {
                    'hub_id': _cloudHubId,
                    'local_hub_id': _localHubId,
                    'home_id': _cloudHomeId,
                    'ownership_epoch': 3,
                    'version': 1,
                    if (scenario != 'no-hint')
                      'connection': {
                        'https_origin': 'https://192.168.1.20:18787',
                        'certificate_sha256': 'a' * 64,
                        'expires_at': DateTime.now()
                            .toUtc()
                            .add(const Duration(minutes: 5))
                            .toIso8601String(),
                      },
                  },
                ],
              }),
              200,
            );
          }
          return http.Response('{"sensors":[]}', 200);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(
            api: api,
            credentials: DiscoveryCredentials(storage: _AutoPairStore()),
            autoScan: true,
            cloudApi: cloud,
            accountId: 'account-a',
            cloudHome: const CloudHome(
              id: _cloudHomeId,
              name: 'Selected home',
              timezone: 'America/Chicago',
              countryCode: 'US',
              postalCode: '60601',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Internal Error, Try again later', skipOffstage: false),
        findsOneWidget,
      );
      cloud.close();
    });
  }
  testWidgets(
    'auto scan waits for selection and attaches only a chosen Cloud appliance',
    (tester) async {
      const applianceId = '55555555-5555-4555-8555-555555555555';
      const newApplianceId = '77777777-7777-4777-8777-777777777777';
      const attachmentId = '66666666-6666-4666-8666-666666666666';
      final api = _ClaimDiscoveryApi();
      final sensors = <Map<String, dynamic>>[];
      final attachments = <Map<String, dynamic>>[];
      final applianceRows = <Map<String, dynamic>>[
        {
          'id': applianceId,
          'home_id': _cloudHomeId,
          'name': 'Desk lamp',
          'category': 'lighting',
          'identity': {
            'brand': 'Example',
            'full_model': 'L123',
            'fuel': 'electricity',
            'match_quality': 'unresolved',
          },
          'version': 2,
        },
      ];
      var attachmentCreates = 0;
      var applianceCreates = 0;
      final client = CloudApiClient(
        session: CloudSession(
          config: _cloudConfig,
          store: _TestTokenStore(),
          authenticator: _TestAuthenticator(),
        ),
        client: MockClient((request) async {
          final path = request.url.path;
          if (path == '/v1/energy-categories') {
            return http.Response(
              jsonEncode({
                'version': 1,
                'groups': [
                  {
                    'key': 'office',
                    'label': 'Office',
                    'types': [
                      {'key': 'computer', 'label': 'Computer'},
                    ],
                  },
                ],
              }),
              200,
              headers: {'etag': '"1"'},
            );
          }
          if (path == '/v1/homes/$_cloudHomeId/hubs') {
            return http.Response(
              jsonEncode({
                'hubs': [
                  {
                    'hub_id': _cloudHubId,
                    'local_hub_id': _localHubId,
                    'home_id': _cloudHomeId,
                    'ownership_epoch': 3,
                    'version': 1,
                  },
                ],
              }),
              200,
            );
          }
          if (path == '/v1/homes/$_cloudHomeId/sensors') {
            if (request.method == 'GET') {
              return http.Response(jsonEncode({'sensors': sensors}), 200);
            }
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            sensors.add({
              'id': _cloudSensorId,
              'home_id': _cloudHomeId,
              'hub_id': body['hub_id'],
              'ownership_epoch': body['ownership_epoch'],
              'local_sensor_id': body['local_sensor_id'],
              'kind': body['kind'],
              'capabilities': body['capabilities'],
              'version': 1,
            });
            return http.Response(jsonEncode(sensors.single), 201);
          }
          if (path == '/v1/homes/$_cloudHomeId/appliances') {
            if (request.method == 'POST') {
              applianceCreates++;
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              final row = {
                'id': newApplianceId,
                'home_id': _cloudHomeId,
                ...body,
                'version': 1,
              };
              applianceRows.add(row);
              return http.Response(jsonEncode(row), 201);
            }
            return http.Response(
              jsonEncode({'appliances': applianceRows}),
              200,
            );
          }
          if (path == '/v1/me/preferences') {
            return http.Response(
              jsonEncode({
                'schema_version': 1,
                'version': 1,
                'email_reports_enabled': false,
              }),
              200,
              headers: {'etag': '"1"'},
            );
          }
          if (path == '/v1/homes/$_cloudHomeId/questions') {
            return http.Response(jsonEncode({'questions': []}), 200);
          }
          if (path == '/v1/homes/$_cloudHomeId/questions/answers') {
            return http.Response(jsonEncode({'answers': []}), 200);
          }
          if (path == '/v1/homes/$_cloudHomeId/attachments') {
            if (request.method == 'GET') {
              return http.Response(
                jsonEncode({'attachments': attachments}),
                200,
              );
            }
            attachmentCreates++;
            expect(
              request.headers['if-match'],
              '"${sensors.single['version']}"',
            );
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(
              body['identity_revision'],
              body['appliance_id'] == applianceId ? 2 : 1,
            );
            for (final item in attachments) {
              if (item['ended_at'] == null) {
                item['ended_at'] = body['started_at'];
              }
            }
            final attached = {
              'id': attachmentCreates == 1
                  ? attachmentId
                  : '88888888-8888-4888-8888-888888888888',
              'home_id': _cloudHomeId,
              ...body,
              'version': 1,
            };
            attachments.add(attached);
            sensors.single['version'] = (sensors.single['version'] as int) + 1;
            return http.Response(jsonEncode(attached), 201);
          }
          return http.Response('{}', 404);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(
            api: api,
            credentials: _ClaimCredentials(),
            autoScan: true,
            cloudHome: const CloudHome(
              id: _cloudHomeId,
              name: 'Selected home',
              timezone: 'America/Chicago',
              countryCode: 'US',
              postalCode: '60601',
            ),
            cloudApi: client,
            accountId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Office meter'), findsWidgets);
      expect(api.plug, isNull);
      expect(sensors, isEmpty);
      expect(attachments, isEmpty);

      await tester.tap(find.text('Office meter').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save this plug'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save this plug'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save plug'));
      await tester.pumpAndSettle();
      expect(api.plug, isNotNull);
      expect(sensors, hasLength(1));
      expect(attachments, isEmpty);

      await tester.ensureVisible(find.text('Identify connected appliance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Identify connected appliance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Desk lamp · lighting'));
      await tester.pumpAndSettle();
      expect(attachmentCreates, 1);
      expect(find.text('Example L123'), findsOneWidget);
      expect(find.text('Desk lamp'), findsWidgets);

      await tester.ensureVisible(find.text('Change connected appliance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change connected appliance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter a new appliance'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('applianceName')));
      await tester.enterText(
        find.byKey(const Key('applianceName')),
        'Office computer',
      );
      await tester.ensureVisible(
        find.byKey(const Key('applianceManufacturer')),
      );
      await tester.enterText(
        find.byKey(const Key('applianceManufacturer')),
        'Example',
      );
      await tester.enterText(find.byKey(const Key('applianceModel')), 'C123');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('applianceGroup-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Office').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('applianceCategory-office-')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Computer').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('saveAppliance')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveAppliance')));
      await tester.pumpAndSettle();
      expect(applianceCreates, 1);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(attachmentCreates, 2);
      expect(
        attachments
            .where((item) => item['ended_at'] == null)
            .single['appliance_id'],
        newApplianceId,
      );
      expect(
        attachments.every((item) => item['sensor_id'] == _cloudSensorId),
        isTrue,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(
            api: api,
            credentials: _ClaimCredentials(),
            autoScan: true,
            cloudHome: const CloudHome(
              id: _cloudHomeId,
              name: 'Selected home',
              timezone: 'America/Chicago',
              countryCode: 'US',
              postalCode: '60601',
            ),
            cloudApi: client,
            accountId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Office computer'), findsWidgets);
      expect(find.text('Example C123'), findsOneWidget);
      await tester.ensureVisible(find.text('Change connected appliance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change connected appliance'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Office computer ·').first);
      await tester.pumpAndSettle();
      expect(attachmentCreates, 2);
    },
  );

  testWidgets(
    'first Cloud home exposes only the link, then restores an owned pairing',
    (tester) async {
      final api = _FirstClaimApi();
      final credentials = _FirstClaimCredentials();
      var owned = false;
      var linkedCalls = 0;
      final cloud = CloudApiClient(
        session: CloudSession(
          config: _cloudConfig,
          store: _TestTokenStore(),
          authenticator: _TestAuthenticator(),
        ),
        client: MockClient((request) async {
          if (request.url.path == '/v1/homes/$_cloudHomeId/hubs') {
            return http.Response(
              jsonEncode({
                'hubs': owned
                    ? [
                        {
                          'hub_id': _cloudHubId,
                          'local_hub_id': _localHubId,
                          'home_id': _cloudHomeId,
                          'ownership_epoch': 2,
                          'version': 1,
                        },
                      ]
                    : [],
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );
      Widget screen() => MaterialApp(
        home: DiscoveryScreen(
          key: UniqueKey(),
          api: api,
          credentials: credentials,
          cloudHome: const CloudHome(
            id: _cloudHomeId,
            name: 'Selected home',
            timezone: 'America/Chicago',
            countryCode: 'US',
            postalCode: '60601',
          ),
          cloudApi: cloud,
          accountId: 'account-a',
          newHomeOnboarding: true,
          onCloudHubLinked: () => linkedCalls++,
        ),
      );

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(find.text('Link paired hub to home'), findsOneWidget);
      expect(api.identityChecks, 1);
      expect(api.customerReads, 0);
      expect(find.text('Hub connected'), findsNothing);
      expect(linkedCalls, 0);

      // The existing claim flow establishes ownership and a fresh pairing.
      owned = true;
      api.failCustomerReads = true;
      credentials.ownedPairing = const StoredPairingCredential(
        address: 'https://192.168.1.20:8787#sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        hubId: _localHubId,
        clientId: 'client-2',
        token: 'claimed-token',
        ownershipEpoch: 2,
      );
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(api.customerReads, greaterThan(0));
      expect(linkedCalls, 0);
      api.failCustomerReads = false;
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(linkedCalls, 1);
      cloud.close();
    },
  );

  testWidgets(
    'first claim ignores a legacy pairing after account scope change',
    (tester) async {
      final pending = Completer<StoredPairingCredential?>();
      final credentials = _FirstClaimCredentials(pendingLegacy: pending);
      final api = _FirstClaimApi();
      final cloud = CloudApiClient(
        session: CloudSession(
          config: _cloudConfig,
          store: _TestTokenStore(),
          authenticator: _TestAuthenticator(),
        ),
        client: MockClient((_) async => http.Response('{"hubs":[]}', 200)),
      );
      Widget screen(String accountId) => MaterialApp(
        home: DiscoveryScreen(
          api: api,
          credentials: credentials,
          cloudHome: const CloudHome(
            id: _cloudHomeId,
            name: 'Selected home',
            timezone: 'America/Chicago',
            countryCode: 'US',
            postalCode: '60601',
          ),
          cloudApi: cloud,
          accountId: accountId,
        ),
      );
      await tester.pumpWidget(screen('account-a'));
      await tester.pump();
      await tester.pumpWidget(screen('account-b'));
      pending.complete(_FirstClaimCredentials.legacyPairing);
      await tester.pumpAndSettle();
      expect(find.text('Link paired hub to home'), findsNothing);
      expect(api.identityChecks, 0);
      expect(api.customerReads, 0);
      cloud.close();
    },
  );

  testWidgets('new-home claim failure offers setup later and keeps retry', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    var linkedCalls = 0;
    final cloud = CloudApiClient(
      session: CloudSession(
        config: _cloudConfig,
        store: _TestTokenStore(),
        authenticator: _TestAuthenticator(),
      ),
      client: MockClient((request) async {
        if (request.url.path == '/v1/homes/$_cloudHomeId/hubs') {
          return http.Response('{"hubs":[]}', 200);
        }
        if (request.url.path == '/v1/homes/$_cloudHomeId/hub-claims') {
          return http.Response('{}', 409);
        }
        return http.Response('{}', 404);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(
          api: _FirstClaimApi(),
          credentials: _FirstClaimCredentials(),
          cloudHome: const CloudHome(
            id: _cloudHomeId,
            name: 'Selected home',
            timezone: 'America/Chicago',
            countryCode: 'US',
            postalCode: '60601',
          ),
          cloudApi: cloud,
          accountId: 'account-a',
          newHomeOnboarding: true,
          onCloudHubLinked: () => linkedCalls++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Set up later'), findsNothing);
    await tester.tap(find.text('Link paired hub to home'));
    await tester.pumpAndSettle();
    expect(find.text('Set up later'), findsOneWidget);
    expect(find.text('Link paired hub to home'), findsOneWidget);
    expect(linkedCalls, 0);
    await tester.tap(find.text('Set up later'));
    await tester.tap(find.text('Set up later'));
    expect(linkedCalls, 1);
    cloud.close();
  });

  testWidgets('first claim ignores a legacy pairing after session change', (
    tester,
  ) async {
    final pending = Completer<StoredPairingCredential?>();
    final credentials = _FirstClaimCredentials(pendingLegacy: pending);
    final api = _FirstClaimApi();
    final session = CloudSession(
      config: _cloudConfig,
      store: _TestTokenStore(),
      authenticator: _TestAuthenticator(),
    );
    final cloud = CloudApiClient(
      session: session,
      client: MockClient((_) async => http.Response('{"hubs":[]}', 200)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(
          api: api,
          credentials: credentials,
          cloudHome: const CloudHome(
            id: _cloudHomeId,
            name: 'Selected home',
            timezone: 'America/Chicago',
            countryCode: 'US',
            postalCode: '60601',
          ),
          cloudApi: cloud,
          accountId: 'account-a',
        ),
      ),
    );
    await tester.pump();
    await session.selectCredentialMethod('oidc');
    pending.complete(_FirstClaimCredentials.legacyPairing);
    await tester.pumpAndSettle();
    expect(find.text('Link paired hub to home'), findsNothing);
    expect(api.identityChecks, 0);
    expect(api.customerReads, 0);
    cloud.close();
  });

  testWidgets(
    'adopting a verified plug registers and reads back its Cloud sensor',
    (tester) async {
      final api = _ClaimDiscoveryApi();
      final credentials = _ClaimCredentials();
      final sensors = <Map<String, dynamic>>[];
      var sensorCreates = 0;
      final client = CloudApiClient(
        session: CloudSession(
          config: _cloudConfig,
          store: _TestTokenStore(),
          authenticator: _TestAuthenticator(),
        ),
        client: MockClient((request) async {
          if (request.url.path == '/v1/homes/$_cloudHomeId/hubs') {
            return http.Response(
              jsonEncode({
                'hubs': [
                  {
                    'hub_id': _cloudHubId,
                    'local_hub_id': _localHubId,
                    'home_id': _cloudHomeId,
                    'ownership_epoch': 3,
                    'version': 1,
                  },
                ],
              }),
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/v1/homes/$_cloudHomeId/hub-claims') {
            return http.Response(
              jsonEncode({
                'claim_id': '44444444-4444-4444-8444-444444444444',
                'hub_id': _cloudHubId,
                'local_hub_id': _localHubId,
                'nonce': 'nonce',
                'expires_at': '2099-01-01T00:00:00Z',
              }),
              201,
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/v1/hubs/claim') {
            return http.Response(
              jsonEncode({
                'hub_id': _cloudHubId,
                'local_hub_id': _localHubId,
                'home_id': _cloudHomeId,
                'ownership_epoch': 3,
                'version': 1,
              }),
              200,
            );
          }
          if (request.url.path == '/v1/homes/$_cloudHomeId/sensors' &&
              request.method == 'GET') {
            return http.Response(jsonEncode({'sensors': sensors}), 200);
          }
          if (request.url.path == '/v1/homes/$_cloudHomeId/sensors' &&
              request.method == 'POST') {
            sensorCreates++;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final registered = {
              'id': _cloudSensorId,
              'home_id': _cloudHomeId,
              'hub_id': body['hub_id'],
              'ownership_epoch': body['ownership_epoch'],
              'local_sensor_id': body['local_sensor_id'],
              'kind': body['kind'],
              'capabilities': body['capabilities'],
              'version': 1,
            };
            sensors.add(registered);
            return http.Response(jsonEncode(registered), 201);
          }
          return http.Response('{}', 404);
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(
            api: api,
            credentials: credentials,
            cloudHome: const CloudHome(
              id: _cloudHomeId,
              name: 'Selected home',
              timezone: 'America/Chicago',
              countryCode: 'US',
              postalCode: '60601',
            ),
            cloudApi: client,
            accountId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Link paired hub to home'), findsNothing);

      expect(sensorCreates, 0);
      await tester.tap(find.text('Scan for plugs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Office meter'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save this plug'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save this plug'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save plug'));
      await tester.pumpAndSettle();

      expect(api.plug, isNotNull);
      expect(sensorCreates, 1);
      expect(sensors.single['local_sensor_id'], 'stable-local-plug-1');
      expect(sensors.single['ownership_epoch'], 3);
      expect(sensors.single['capabilities'], ['power', 'energy']);
      expect(find.byKey(const Key('hubClaimMessage')), findsNothing);
    },
  );

  testWidgets('verified meter shows energy without manufacturer source', (
    tester,
  ) async {
    final api = NameplateDetailApi();
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceEnergyDetailScreen(
          plug: SavedPlug(
            id: 'plug-detail',
            ip: '192.168.1.42',
            model: 'HS110',
            name: 'Office meter',
            room: 'Office',
            meterStatus: 'verified',
            lastVerifiedAt: 100,
            connectedAppliance: api.appliance,
          ),
          api: api,
          hubAddress: 'https://192.168.1.20:8787',
          token: 'test-token',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('OEM rated input (nameplate)'), findsNothing);
    expect(find.text('Manufacturer source'), findsNothing);
    expect(find.text('Energy · 0.2 kWh'), findsOneWidget);
    expect(find.text('Cost · \$0.04'), findsOneWidget);
    expect(find.textContaining('1350 kWh'), findsNothing);
  });

  testWidgets(
    'manual IPv4 field uses decimal keyboard and accepts dotted input',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(home: DiscoveryScreen(api: const FakeDiscoveryApi())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter a plug IP address'));
      await tester.pumpAndSettle();

      final ipField = find.byKey(const Key('manualPlugIp'));
      final field = tester.widget<TextField>(ipField);
      expect(
        field.keyboardType,
        const TextInputType.numberWithOptions(decimal: true),
      );

      // Entering a complete address here exercises the same unrestricted edit
      // path used by paste; validation remains with the hub.
      await tester.enterText(ipField, '192.168.1.42');
      expect(field.controller!.text, '192.168.1.42');
    },
  );

  test('parses explicit stale regional rate metadata and readings', () {
    final energy = DeviceEnergy.fromJson({
      'status': 'measured',
      'period': 'day',
      'total_kwh': 0.1,
      'coverage_fraction': 0.4,
      'covered_secs': 34560,
      'latest_watts': null,
      'observed_cost_usd': 0.02,
      'rate_source_label': 'Regional rate',
      'rate_status': 'stale',
      'rate_source': 'utility',
      'rate_as_of': '2026-04-01',
      'rate_fetched_at': 1775000000,
      'rate_is_stale': true,
      'readings': [
        {'ts': '2026-09-29T12:00:00Z', 'watts': 42, 'kwh_cumulative': null},
      ],
    });
    expect(energy.rateStatus, 'stale');
    expect(energy.rateIsStale, isTrue);
    expect(energy.rateAsOf, '2026-04-01');
    expect(energy.rateFetchedAt, 1775000000);
    expect(energy.readingCount, 1);
  });

  testWidgets('opens concise measured detail without source labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final credentials = FakeCredentials()
      ..address = 'https://192.168.1.20:8787'
      ..token = 'test-token';
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: DeviceDetailApi(), credentials: credentials),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('View energy details').first,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('View energy details').first);
    await tester.pumpAndSettle();
    expect(find.text('Appliance energy'), findsOneWidget);
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.text('Energy · 0.2 kWh'), findsOneWidget);
    expect(find.textContaining('EPA'), findsNothing);
  });

  testWidgets('verified meter ignores attached estimate', (tester) async {
    final api = MeasuredEstimateApi();
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceEnergyDetailScreen(
          plug: SavedPlug(
            id: 'plug-detail',
            ip: '192.168.1.42',
            model: 'HS110',
            name: 'Office meter',
            room: 'Office',
            meterStatus: 'verified',
            lastVerifiedAt: 100,
            connectedAppliance: api.appliance,
          ),
          api: api,
          hubAddress: 'https://192.168.1.20:8787',
          token: 'test-token',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.estimateCalls, 0);
    expect(find.text('Energy · 0.2 kWh'), findsOneWidget);
    expect(find.textContaining('Measurement coverage'), findsNothing);
  });

  testWidgets('shows measured energy without sample metadata', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceEnergyDetailScreen(
          plug: SavedPlug(
            id: 'plug-detail',
            ip: '192.168.1.42',
            model: 'HS110',
            name: 'Office meter',
            room: 'Office',
            meterStatus: 'verified',
            lastVerifiedAt: 100,
            connectedAppliance: DeviceDetailApi().appliance,
          ),
          api: TimestampApi(),
          hubAddress: 'https://192.168.1.20:8787',
          token: 'test-token',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Energy · 0.2 kWh'), findsOneWidget);
    expect(find.textContaining('Sampled '), findsNothing);
  });

  testWidgets('verified meter never uses a retained estimate', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceEnergyDetailScreen(
          plug: SavedPlug(
            id: 'plug-detail',
            ip: '192.168.1.42',
            model: 'HS110',
            name: 'Office meter',
            room: 'Office',
            meterStatus: 'verified',
            lastVerifiedAt: 100,
            connectedAppliance: DeviceDetailApi().appliance,
          ),
          api: OfflineEstimateApi(),
          hubAddress: 'https://192.168.1.20:8787',
          token: 'test-token',
          estimate: const EnergyEstimate(
            status: 'estimated',
            estimatedKwh: 18,
            estimatedCostUsd: 3.24,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Energy · 0.2 kWh'), findsOneWidget);
    expect(find.textContaining('18.0 kWh'), findsNothing);
  });

  testWidgets('requests the monthly meter period', (tester) async {
    final api = PeriodRaceApi();
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceEnergyDetailScreen(
          plug: SavedPlug(
            id: 'plug-detail',
            ip: '192.168.1.42',
            model: 'HS110',
            name: 'Office meter',
            room: 'Office',
            meterStatus: 'verified',
            lastVerifiedAt: 100,
            connectedAppliance: DeviceDetailApi().appliance,
          ),
          api: api,
          hubAddress: 'https://192.168.1.20:8787',
          token: 'test-token',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.text('Energy · 0.7 kWh'), findsOneWidget);
  });

  test('formats electricity rate provenance and unavailable feedback', () {
    const source = EnergyEvidence(
      sourceKind: 'epa_exact',
      datasetId: 'epa-ratings',
      sourceUrl: 'https://example.test/record',
      matchedBrand: 'Example',
      matchedModel: 'Lamp 1',
      annualKwh: 20,
      usageBasis: 'rated',
      retrievedAt: 1,
    );
    expect(energySourceHeading(source), 'EPA rated energy data');
    const manufacturerTest = EnergyEvidence(
      sourceKind: 'oem_exact',
      datasetId: 'manufacturer-pdf-ratings',
      sourceUrl: 'https://example.test/model-test',
      matchedBrand: 'Example',
      matchedModel: 'Lamp 1',
      annualKwh: 20,
      usageBasis: 'rated',
      retrievedAt: 1,
    );
    expect(
      energySourceHeading(manufacturerTest),
      'Manufacturer model test data',
    );
    const enerGuideFamily = EnergyEvidence(
      sourceKind: 'energuide_family',
      datasetId: 'energuide-historical-family-tests',
      sourceUrl: 'https://example.test/energuide-family-test',
      matchedBrand: 'Example',
      matchedModel: 'Family X',
      annualKwh: 20,
      usageBasis: 'Historical family test figure',
      retrievedAt: 1,
    );
    expect(
      energySourceHeading(enerGuideFamily),
      'Historical EnerGuide family test data',
    );
    expect(
      energyRateDescription(
        const EnergyEstimate(
          status: 'estimated',
          rateUsdPerKwh: 0.14,
          rateSourceLabel: 'Regional utility rate',
          rateAsOf: '2026-01-01',
        ),
      ),
      'Regional utility rate: \$0.1400/kWh · 2026-01-01',
    );
    expect(
      energyRateDescription(
        const EnergyEstimate(
          status: 'estimated',
          rateUsdPerKwh: 0.14,
          rateSourceLabel: 'Regional utility rate',
          rateAsOf: '2026-01-01',
          rateStatus: 'stale',
          isStale: true,
        ),
      ),
      'Regional utility rate: \$0.1400/kWh · Cached regional rate from 2026-01-01; fresh regional rate unavailable.',
    );
    expect(
      energyRateDescription(
        const EnergyEstimate(status: 'estimated', rateStatus: 'unavailable'),
      ),
      'Regional rate unavailable. Enter your bill rate for a cost estimate.',
    );
  });

  testWidgets('clears old hub devices when the hub address changes', (
    tester,
  ) async {
    if (!_testDeveloperMode) return;
    final api = SavingApi()
      ..plug = const SavedPlug(
        id: 'old-plug',
        ip: '192.168.1.42',
        model: 'HS103',
        name: 'Old hub plug',
        room: 'Office',
        meterStatus: 'absent',
        lastVerifiedAt: 100,
      );
    final credentials = FakeCredentials()
      ..address = 'https://192.168.1.20:8787'
      ..token = 'test-token';
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: credentials),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Old hub plug'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Old hub plug'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Connection details'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Connection details'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('hubAddress')),
      'https://192.168.1.30:8787',
    );
    await tester.pumpAndSettle();

    expect(find.text('Old hub plug'), findsNothing);
  });

  testWidgets(
    'checks a saved plug on demand and keeps meter capability separate',
    (tester) async {
      final api = SavingApi()
        ..plug = const SavedPlug(
          id: 'plug-1',
          ip: '192.168.1.42',
          model: 'HS103',
          name: 'Living room plug',
          room: 'Living room',
          meterStatus: 'absent',
          lastVerifiedAt: 100,
        );
      final credentials = FakeCredentials()
        ..address = 'https://192.168.1.20:8787'
        ..token = 'test-token';
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(api: api, credentials: credentials),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Check plug connection'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Plug connection not checked'), findsOneWidget);
      await tester.tap(find.text('Check plug connection'));
      await tester.pumpAndSettle();
      expect(api.statusRefreshCalls, 1);
      expect(find.text('Plug connected'), findsOneWidget);
      expect(find.text('No energy monitoring'), findsOneWidget);

      api.refreshedStatus = 'identity_changed';
      await tester.tap(find.text('Check plug connection'));
      await tester.pumpAndSettle();
      expect(
        find.text('Needs verification · different plug at this address'),
        findsOneWidget,
      );
      expect(find.text('No energy monitoring'), findsOneWidget);
    },
  );

  testWidgets('shows a discovered HS103 separately from its unknown load', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: DiscoveryScreen(api: FakeDiscoveryApi())),
    );
    await tester.enterText(
      find.byType(TextField).at(0),
      'https://192.168.1.20:8787',
    );
    await tester.enterText(find.byType(TextField).at(1), 'test-token');
    await tester.tap(find.text('Scan for plugs'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Desk plug'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No energy monitoring'), findsWidgets);
    await tester.tap(find.text('Desk plug'));
    await tester.pumpAndSettle();

    expect(find.text('Desk plug'), findsOneWidget);
    expect(find.text('MAC 00:31:92:43:c5:28'), findsOneWidget);
    expect(find.text('Local API · HTTP 80'), findsOneWidget);
    expect(find.text('Detected · No energy monitoring'), findsOneWidget);
    expect(find.text('Connected appliance or lamp'), findsOneWidget);
    expect(find.textContaining('Not identified yet'), findsOneWidget);
    expect(find.textContaining('Not saved yet'), findsOneWidget);
    expect(
      find.textContaining('Switch on · This is not a power reading'),
      findsOneWidget,
    );
  });

  testWidgets('saves a verified plug and reloads it after screen restart', (
    tester,
  ) async {
    final api = SavingApi();
    final credentials = FakeCredentials();
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: credentials),
      ),
    );
    await tester.enterText(
      find.byType(TextField).at(0),
      'https://192.168.1.20:8787',
    );
    await tester.enterText(find.byType(TextField).at(1), 'test-token');
    await tester.tap(find.text('Scan for plugs'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Desk plug'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Desk plug'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save this plug'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save this plug'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save plug'));
    await tester.pumpAndSettle();
    expect(find.text('Save plug'), findsOneWidget);
    await tester.tap(find.text('I understand this plug cannot measure energy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save plug'));
    await tester.pumpAndSettle();
    expect(api.plug?.name, 'Desk plug');
    expect(credentials.address, 'https://192.168.1.20:8787');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: credentials),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Smart plug · Saved'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Smart plug · Saved'), findsOneWidget);
    expect(find.text('No energy monitoring'), findsOneWidget);
    expect(find.text('Connected appliance or lamp'), findsNothing);
    expect(find.text('Identify connected appliance'), findsOneWidget);
  });

  testWidgets(
    'Delete removes only the chosen saved plug after hub success and restart',
    (tester) async {
      final api = _DeletingSavedApi()..nearbyEnabled = true;
      final credentials = FakeCredentials()
        ..address = 'https://192.168.1.20:8787'
        ..token = 'test-token';
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(api: api, credentials: credentials),
        ),
      );
      await tester.pumpAndSettle();
      final initialReads = api.savedReads.length;
      await tester.scrollUntilVisible(
        find.text('First plug'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      final firstCard = find.ancestor(
        of: find.text('First plug'),
        matching: find.byType(Card),
      );
      final delete = find.descendant(
        of: firstCard,
        matching: find.text('Delete'),
      );
      await tester.ensureVisible(delete);
      await tester.pumpAndSettle();
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(api.deleted, ['plug-a']);
      expect(api.savedReads.length, initialReads + 1);
      expect(api.nearbyReads.length, greaterThanOrEqualTo(2));
      expect(find.text('First plug'), findsNothing);
      expect(find.byKey(const Key('nearby-saved-plug-a')), findsNothing);
      expect(api.plugs.map((plug) => plug.id), ['plug-b']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(api: api, credentials: credentials),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Second plug'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('First plug'), findsNothing);
      expect(find.text('Second plug'), findsOneWidget);
      final secondCard = find.ancestor(
        of: find.text('Second plug'),
        matching: find.byType(Card),
      );
      final secondDelete = find.descendant(
        of: secondCard,
        matching: find.text('Delete'),
      );
      await tester.ensureVisible(secondDelete);
      await tester.pumpAndSettle();
      await tester.tap(secondDelete);
      await tester.pumpAndSettle();
      expect(
        find.text('No smart plugs saved on this hub yet.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Delete waits for Hub success before refreshing either inventory',
    (tester) async {
      final api = _DeletingSavedApi()
        ..nearbyEnabled = true
        ..pending = Completer<void>();
      final credentials = FakeCredentials()
        ..address = 'https://192.168.1.20:8787'
        ..token = 'test-token';
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(api: api, credentials: credentials),
        ),
      );
      await tester.pumpAndSettle();
      final savedBefore = api.savedReads.length;
      final nearbyBefore = api.nearbyReads.length;
      await tester.scrollUntilVisible(
        find.text('First plug'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      final card = find.ancestor(
        of: find.text('First plug'),
        matching: find.byType(Card),
      );
      await tester.tap(
        find.descendant(of: card, matching: find.text('Delete')),
      );
      await tester.pump();
      expect(api.savedReads.length, savedBefore);
      expect(api.nearbyReads.length, nearbyBefore);
      expect(find.text('First plug'), findsOneWidget);
      api.pending!.complete();
      await tester.pumpAndSettle();
      expect(api.savedReads.length, savedBefore + 1);
      expect(api.nearbyReads.length, nearbyBefore + 1);
      expect(find.text('First plug'), findsNothing);
    },
  );

  testWidgets('Delete refresh uses current Hub row data for sibling plugs', (
    tester,
  ) async {
    final api = _DeletingSavedApi()..pending = Completer<void>();
    final credentials = FakeCredentials()
      ..address = 'https://192.168.1.20:8787'
      ..token = 'test-token';
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: credentials),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('First plug').first,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    final card = find.ancestor(
      of: find.text('First plug').first,
      matching: find.byType(Card),
    );
    await tester.tap(find.descendant(of: card, matching: find.text('Delete')));
    api.plugs[1] = const SavedPlug(
      id: 'plug-b',
      ip: '192.168.1.42',
      model: 'HS103',
      name: 'Updated sibling',
      room: 'Kitchen',
      meterStatus: 'absent',
      lastVerifiedAt: 101,
    );
    api.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Updated sibling'), findsOneWidget);
    expect(find.text('Second plug'), findsNothing);
  });

  testWidgets('Failed refresh leaves successful deletion visible', (
    tester,
  ) async {
    final api = _DeletingSavedApi()..pending = Completer<void>();
    final credentials = FakeCredentials()
      ..address = 'https://192.168.1.20:8787'
      ..token = 'test-token';
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: credentials),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('First plug'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    final card = find.ancestor(
      of: find.text('First plug'),
      matching: find.byType(Card),
    );
    await tester.tap(find.descendant(of: card, matching: find.text('Delete')));
    api.savedReadFails = true;
    api.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('First plug'), findsNothing);
    expect(find.text('Second plug'), findsOneWidget);
    expect(api.deleted, ['plug-a']);
  });

  testWidgets('A saved read started before DELETE cannot restore its row', (
    tester,
  ) async {
    final api = _DeletingSavedApi();
    final credentials = FakeCredentials()
      ..address = 'https://192.168.1.20:8787'
      ..token = 'test-token';
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: credentials),
      ),
    );
    await tester.pumpAndSettle();
    final stale = Completer<List<SavedPlug>>();
    api.queuedSavedReads.add(stale);
    await tester.tap(find.byTooltip('Refresh saved plugs'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('First plug'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    final card = find.ancestor(
      of: find.text('First plug'),
      matching: find.byType(Card),
    );
    await tester.tap(find.descendant(of: card, matching: find.text('Delete')));
    await tester.pumpAndSettle();
    expect(find.text('First plug'), findsNothing);
    stale.complete([
      const SavedPlug(
        id: 'plug-a',
        ip: '192.168.1.41',
        model: 'HS103',
        name: 'First plug',
        room: 'Office',
        meterStatus: 'absent',
        lastVerifiedAt: 100,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('First plug'), findsNothing);
    expect(find.text('Second plug'), findsOneWidget);
  });

  testWidgets('A nearby read started before DELETE cannot restore its row', (
    tester,
  ) async {
    final api = _DeletingSavedApi()..nearbyEnabled = true;
    final credentials = FakeCredentials()
      ..address = 'https://192.168.1.20:8787'
      ..token = 'test-token';
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: credentials),
      ),
    );
    await tester.pumpAndSettle();
    final stale = Completer<List<NearbySavedDevice>>();
    api.queuedNearbyReads.add(stale);
    await tester.tap(find.byTooltip('Refresh saved plugs'));
    await tester.pump();
    expect(api.queuedNearbyReads, isEmpty);
    await tester.scrollUntilVisible(
      find.text('First plug'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    final card = find.ancestor(
      of: find.text('First plug'),
      matching: find.byType(Card),
    );
    await tester.tap(find.descendant(of: card, matching: find.text('Delete')));
    await tester.pumpAndSettle();
    stale.complete(const [NearbySavedDevice('plug-a', 'First plug')]);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nearby-saved-plug-a')), findsNothing);
    expect(find.text('First plug'), findsNothing);
  });

  testWidgets(
    'A late saved read cannot show old Hub rows after address switch',
    (tester) async {
      if (!_testDeveloperMode) return;
      final api = _DeletingSavedApi();
      final credentials = FakeCredentials()
        ..address = 'https://192.168.1.20:8787'
        ..token = 'test-token';
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(api: api, credentials: credentials),
        ),
      );
      await tester.pumpAndSettle();
      final stale = Completer<List<SavedPlug>>();
      api.queuedSavedReads.add(stale);
      await tester.tap(find.byTooltip('Refresh saved plugs'));
      await tester.pump();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 1500));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.text('Connection details'));
      await tester.tap(find.text('Connection details'));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('hubAddress')));
      await tester.enterText(
        find.byKey(const Key('hubAddress')),
        'https://192.168.1.21:8787',
      );
      await tester.pump();
      stale.complete(List.of(api.plugs));
      await tester.pumpAndSettle();
      expect(find.text('First plug'), findsNothing);
      expect(find.text('Second plug'), findsNothing);
    },
  );

  testWidgets('Old Hub delete does not block the same ID on a new Hub', (
    tester,
  ) async {
    if (!_testDeveloperMode) return;
    final oldDelete = Completer<void>();
    final newDelete = Completer<void>();
    final api = _DeletingSavedApi()..pending = oldDelete;
    final credentials = FakeCredentials()
      ..address = 'https://192.168.1.20:8787'
      ..token = 'test-token';
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: credentials),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('First plug'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    final oldCard = find.ancestor(
      of: find.text('First plug'),
      matching: find.byType(Card),
    );
    await tester.tap(
      find.descendant(of: oldCard, matching: find.text('Delete')),
    );
    await tester.pump();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1500));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('Connection details'));
    await tester.tap(find.text('Connection details'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('hubAddress')));
    await tester.enterText(
      find.byKey(const Key('hubAddress')),
      'https://192.168.1.21:8787',
    );
    await tester.pump();
    await tester.ensureVisible(find.byTooltip('Refresh saved plugs'));
    await tester.tap(find.byTooltip('Refresh saved plugs'));
    await tester.pumpAndSettle();
    expect(api.savedReads.last, 'https://192.168.1.21:8787');
    api.pending = newDelete;
    await tester.scrollUntilVisible(
      find.text('First plug'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    final newCard = find.ancestor(
      of: find.text('First plug'),
      matching: find.byType(Card),
    );
    final newDeleteLabel = find.descendant(
      of: newCard,
      matching: find.text('Delete'),
    );
    final newButton = find.ancestor(
      of: newDeleteLabel,
      matching: find.byType(TextButton),
    );
    expect(tester.widget<TextButton>(newButton).onPressed, isNotNull);
    await tester.tap(newDeleteLabel);
    await tester.pump();
    expect(api.deleted, ['plug-a', 'plug-a']);
    oldDelete.complete();
    await tester.pump();
    expect(tester.widget<TextButton>(newButton).onPressed, isNull);
    newDelete.complete();
    await tester.pumpAndSettle();
    expect(find.text('First plug'), findsNothing);
  });

  testWidgets(
    'Delete remains pending without duplicate requests and retains row on failure',
    (tester) async {
      final api = _DeletingSavedApi()..pending = Completer<void>();
      final credentials = FakeCredentials()
        ..address = 'https://192.168.1.20:8787'
        ..token = 'test-token';
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(api: api, credentials: credentials),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('First plug'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      final firstCard = find.ancestor(
        of: find.text('First plug'),
        matching: find.byType(Card),
      );
      final delete = find.descendant(
        of: firstCard,
        matching: find.text('Delete'),
      );
      await tester.ensureVisible(delete);
      await tester.pumpAndSettle();
      await tester.tap(delete);
      await tester.pump();
      expect(api.deleted, ['plug-a']);
      expect(
        tester
            .widget<TextButton>(
              find.ancestor(of: delete, matching: find.byType(TextButton)),
            )
            .onPressed,
        isNull,
      );
      api.fail = true;
      api.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('First plug'), findsOneWidget);
      expect(api.plugs.length, 2);
      final error = find.text('Internal Error, Try again later');
      final secondCard = find.ancestor(
        of: find.text('Second plug'),
        matching: find.byType(Card),
      );
      expect(find.descendant(of: firstCard, matching: error), findsOneWidget);
      expect(find.descendant(of: secondCard, matching: error), findsNothing);
      expect(error, findsOneWidget);
      await tester.ensureVisible(error);
      await tester.pump();
      expect(
        tester.getTopLeft(error).dy,
        greaterThan(tester.getBottomLeft(delete).dy),
      );
      expect(
        tester.getBottomLeft(error).dy,
        lessThan(tester.getBottomLeft(firstCard).dy),
      );

      api
        ..pending = Completer<void>()
        ..fail = false;
      await tester.ensureVisible(delete);
      await tester.pump();
      await tester.tap(delete);
      await tester.pump();
      expect(error, findsNothing);
      expect(api.deleted, ['plug-a', 'plug-a']);
      expect(
        tester
            .widget<TextButton>(
              find.ancestor(of: delete, matching: find.byType(TextButton)),
            )
            .onPressed,
        isNull,
      );
      api.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('First plug'), findsNothing);
      expect(find.text('Second plug'), findsOneWidget);
      expect(error, findsNothing);
    },
  );

  testWidgets(
    'Delete errors stay with their plugs when another retry succeeds',
    (tester) async {
      final api = _DeletingSavedApi()..fail = true;
      final credentials = FakeCredentials()
        ..address = 'https://192.168.1.20:8787'
        ..token = 'test-token';
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(api: api, credentials: credentials),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('First plug'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      final firstCard = find.ancestor(
        of: find.text('First plug'),
        matching: find.byType(Card),
      );
      final firstDelete = find.descendant(
        of: firstCard,
        matching: find.text('Delete'),
      );
      await tester.ensureVisible(firstDelete);
      await tester.tap(firstDelete);
      await tester.pumpAndSettle();
      final secondCard = find.ancestor(
        of: find.text('Second plug'),
        matching: find.byType(Card),
      );
      final secondDelete = find.descendant(
        of: secondCard,
        matching: find.text('Delete'),
      );
      await tester.ensureVisible(secondDelete);
      await tester.tap(secondDelete);
      await tester.pumpAndSettle();
      final error = find.text('Internal Error, Try again later');
      expect(error, findsNWidgets(2));
      api.fail = false;
      await tester.ensureVisible(firstDelete);
      await tester.tap(firstDelete);
      await tester.pumpAndSettle();
      expect(find.text('First plug'), findsNothing);
      expect(find.descendant(of: secondCard, matching: error), findsOneWidget);
      expect(error, findsOneWidget);
    },
  );

  testWidgets('stale Delete completion does not change another hub view', (
    tester,
  ) async {
    if (!_testDeveloperMode) return;
    final api = _DeletingSavedApi()..pending = Completer<void>();
    final credentials = FakeCredentials()
      ..address = 'https://192.168.1.20:8787'
      ..token = 'test-token';
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: credentials),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('First plug'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    final firstCard = find.ancestor(
      of: find.text('First plug'),
      matching: find.byType(Card),
    );
    final delete = find.descendant(
      of: firstCard,
      matching: find.text('Delete'),
    );
    await tester.ensureVisible(delete);
    await tester.pumpAndSettle();
    await tester.tap(delete);
    await tester.pump();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1500));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('Connection details'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Connection details'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.byKey(const Key('hubAddress')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const Key('hubAddress')),
      'https://192.168.1.21:8787',
    );
    api.fail = true;
    api.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('First plug'), findsNothing);
    expect(find.text('No smart plugs saved on this hub yet.'), findsOneWidget);
    expect(find.text('Internal Error, Try again later'), findsNothing);
  });

  testWidgets('Delete error clears when hub changes and plug ID reappears', (
    tester,
  ) async {
    if (!_testDeveloperMode) return;
    final api = _DeletingSavedApi()..fail = true;
    final credentials = FakeCredentials()
      ..address = 'https://192.168.1.20:8787'
      ..token = 'test-token';
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: credentials),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('First plug'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    final firstCard = find.ancestor(
      of: find.text('First plug'),
      matching: find.byType(Card),
    );
    final delete = find.descendant(
      of: firstCard,
      matching: find.text('Delete'),
    );
    await tester.ensureVisible(delete);
    await tester.pump();
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.text('Internal Error, Try again later'), findsOneWidget);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1500));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('Connection details'));
    await tester.tap(find.text('Connection details'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('hubAddress')));
    await tester.enterText(
      find.byKey(const Key('hubAddress')),
      'https://192.168.1.21:8787',
    );
    await tester.pump();
    expect(find.text('Internal Error, Try again later'), findsNothing);
    await tester.ensureVisible(find.text('Saved smart plugs'));
    final refresh = find.byTooltip('Refresh saved plugs');
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('First plug'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('First plug'), findsOneWidget);
    expect(find.text('Internal Error, Try again later'), findsNothing);
  });

  testWidgets('refresh drops Delete errors for plugs no longer saved', (
    tester,
  ) async {
    final api = _DeletingSavedApi()..fail = true;
    final credentials = FakeCredentials()
      ..address = 'https://192.168.1.20:8787'
      ..token = 'test-token';
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: credentials),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('First plug'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    final firstCard = find.ancestor(
      of: find.text('First plug'),
      matching: find.byType(Card),
    );
    final delete = find.descendant(
      of: firstCard,
      matching: find.text('Delete'),
    );
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.text('Internal Error, Try again later'), findsOneWidget);

    api.plugs.removeWhere((plug) => plug.id == 'plug-a');
    await tester.ensureVisible(find.byTooltip('Refresh saved plugs'));
    await tester.tap(find.byTooltip('Refresh saved plugs'));
    await tester.pumpAndSettle();
    expect(find.text('First plug'), findsNothing);
    expect(find.text('Second plug'), findsOneWidget);
    expect(find.text('Internal Error, Try again later'), findsNothing);
  });

  testWidgets('links a saved appliance to the plug without making it a meter', (
    tester,
  ) async {
    final api = SavingApi();
    api.plug = const SavedPlug(
      id: 'plug-1',
      ip: '192.168.1.42',
      model: 'HS103',
      name: 'Desk plug',
      room: 'Office',
      meterStatus: 'absent',
      lastVerifiedAt: 100,
    );
    final credentials = FakeCredentials()
      ..address = 'https://192.168.1.20:8787'
      ..token = 'test-token';
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(api: api, credentials: credentials),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Identify connected appliance'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Identify connected appliance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Identify connected appliance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desk lamp · lighting'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Connected load · No live readings'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Desk lamp'), findsOneWidget);
    expect(find.text('Example L123'), findsOneWidget);
    expect(find.text('Connected load · No live readings'), findsOneWidget);
    expect(find.text('No energy monitoring'), findsOneWidget);
    expect(find.text('Change connected appliance'), findsOneWidget);
  });

  testWidgets('hides saved attachment when make or model is missing', (
    tester,
  ) async {
    for (final identity in [('', 'AM07'), ('Dyson', '')]) {
      final api = _FixtureApplianceApi(
        manufacturer: identity.$1,
        model: identity.$2,
      );
      api.plug = SavedPlug(
        id: 'plug-1',
        ip: '192.168.1.42',
        model: 'HS103',
        name: 'Living room plug',
        room: 'Living room',
        meterStatus: 'absent',
        lastVerifiedAt: 100,
        connectedAppliance: api.appliance,
      );
      final credentials = FakeCredentials()
        ..address = 'https://192.168.1.20:8787'
        ..token = 'test-token';
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(api: api, credentials: credentials),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Smart plug · Saved'),
        220,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Identify connected appliance'), findsOneWidget);
      expect(find.text('Change connected appliance'), findsNothing);
      expect(find.text('Living room fan'), findsNothing);
      expect(find.text('fan'), findsNothing);
      expect(find.textContaining('Estimate unavailable'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('shows saved make and model after restart without an estimate', (
    tester,
  ) async {
    final api = _FixtureApplianceApi(manufacturer: 'Dyson', model: 'AM07');
    api.plug = SavedPlug(
      id: 'plug-1',
      ip: '192.168.1.42',
      model: 'HS103',
      name: 'Living room plug',
      room: 'Living room',
      meterStatus: 'absent',
      lastVerifiedAt: 100,
      connectedAppliance: api.appliance,
    );
    final credentials = FakeCredentials()
      ..address = 'https://192.168.1.20:8787'
      ..token = 'test-token';

    Future<void> showScreen() async {
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(api: api, credentials: credentials),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Smart plug · Saved'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
    }

    await showScreen();
    expect(api.estimateCalls, 1);
    expect(find.text('Dyson AM07'), findsOneWidget);
    final attachedSection = find
        .ancestor(of: find.text('Dyson AM07'), matching: find.byType(Column))
        .first;
    expect(
      tester
          .widget<Text>(
            find
                .descendant(of: attachedSection, matching: find.byType(Text))
                .first,
          )
          .data,
      'Dyson AM07',
    );
    expect(find.text('Living room fan'), findsOneWidget);
    expect(find.text('Energy data is not available yet.'), findsOneWidget);
    expect(find.text('Change connected appliance'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await showScreen();
    expect(find.text('Dyson AM07'), findsOneWidget);
    expect(find.text('Connected appliance or lamp'), findsNothing);
  });

  testWidgets('retains paired hub and retry when offline on restart', (
    tester,
  ) async {
    final api = OfflinePairingApi();
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryScreen(
          api: api,
          credentials: OfflinePairedCredentials(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Paired hub: hub-1'),
      _testDeveloperMode ? findsOneWidget : findsNothing,
    );
    expect(
      find.text('Pair with a different hub'),
      _testDeveloperMode ? findsOneWidget : findsNothing,
    );
    expect(
      find.text('Paired hub address'),
      _testDeveloperMode ? findsOneWidget : findsNothing,
    );
    expect(find.text('Connect to your local hub'), findsNothing);
    expect(find.text('Link paired hub to home'), findsNothing);
    expect(find.textContaining('Link this paired hub'), findsNothing);
    expect(find.textContaining('Pair this phone with the hub'), findsNothing);
    expect(find.text('Hub temporarily unavailable.'), findsOneWidget);
    expect(find.text('Retry hub connection'), findsOneWidget);
    expect(api.checks, 1);
    await tester.tap(find.text('Retry hub connection'));
    await tester.pumpAndSettle();
    expect(api.checks, 2);
  });

  testWidgets(
    'energy details use the owner-authorized hub client in Cloud mode',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final api = _OwnerHeaderApi()
        ..plug = SavedPlug(
          id: 'saved-plug',
          ip: '192.168.1.42',
          model: 'KP115',
          name: 'Saved office plug',
          room: 'Office',
          meterStatus: 'verified',
          lastVerifiedAt: 100,
        );
      final store = _AutoPairStore();
      final cloud = CloudApiClient(
        session: CloudSession(
          config: _cloudConfig,
          store: _TestTokenStore(),
          authenticator: _TestAuthenticator(),
        ),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/hubs')) {
            return http.Response(
              jsonEncode({
                'hubs': [
                  {
                    'hub_id': _cloudHubId,
                    'local_hub_id': _localHubId,
                    'home_id': _cloudHomeId,
                    'ownership_epoch': 3,
                    'version': 1,
                    'connection': {
                      'https_origin': 'https://192.168.1.20:18787',
                      'certificate_sha256': 'a' * 64,
                      'expires_at': DateTime.now()
                          .toUtc()
                          .add(const Duration(minutes: 5))
                          .toIso8601String(),
                    },
                  },
                ],
              }),
              200,
            );
          }
          return http.Response('{"sensors":[]}', 200);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(
            api: api,
            credentials: DiscoveryCredentials(storage: store),
            autoScan: true,
            cloudApi: cloud,
            accountId: 'account-a',
            cloudHome: const CloudHome(
              id: _cloudHomeId,
              name: 'Selected home',
              timezone: 'America/Chicago',
              countryCode: 'US',
              postalCode: '60601',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('View energy details').first,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('View energy details').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not load meter history'), findsNothing);
      expect(find.text('Appliance energy'), findsOneWidget);
      expect(api.reads, ['$_cloudHomeId:saved-plug']);
      cloud.close();
    },
  );
  testWidgets(
    'Cloud appliance onboarding gets the owner-authorized hub client',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final api = _OwnerHeaderApi();
      final cloud = CloudApiClient(
        session: CloudSession(
          config: _cloudConfig,
          store: _TestTokenStore(),
          authenticator: _TestAuthenticator(),
        ),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/hubs')) {
            return http.Response(
              jsonEncode({
                'hubs': [
                  {
                    'hub_id': _cloudHubId,
                    'local_hub_id': _localHubId,
                    'home_id': _cloudHomeId,
                    'ownership_epoch': 3,
                    'version': 1,
                    'connection': {
                      'https_origin': 'https://192.168.1.20:18787',
                      'certificate_sha256': 'a' * 64,
                      'expires_at': DateTime.now()
                          .toUtc()
                          .add(const Duration(minutes: 5))
                          .toIso8601String(),
                    },
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path == '/v1/homes/$_cloudHomeId/appliances') {
            return http.Response(jsonEncode({'appliances': []}), 200);
          }
          return http.Response('{"sensors":[]}', 200);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(
            api: api,
            credentials: DiscoveryCredentials(storage: _AutoPairStore()),
            autoScan: true,
            cloudApi: cloud,
            accountId: 'account-a',
            cloudHome: const CloudHome(
              id: _cloudHomeId,
              name: 'Selected home',
              timezone: 'America/Chicago',
              countryCode: 'US',
              postalCode: '60601',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Identify connected appliance'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Identify connected appliance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter a new appliance'));
      await tester.pumpAndSettle();
      final screen = tester.widget<ApplianceOnboardingScreen>(
        find.byType(ApplianceOnboardingScreen),
      );
      expect((screen.api as _OwnerHeaderApi).owner?.homeId, _cloudHomeId);
      expect(
        screen.hubAddress,
        startsWith('https://192.168.1.20:18787#sha256='),
      );
      expect(screen.hubToken, 'auto-paired-token');
      cloud.close();
    },
  );
}
