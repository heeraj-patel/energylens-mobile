import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../core/cloud_api/cloud_hub_claim.dart';
import '../../core/cloud_api/cloud_energy_categories.dart';
import '../../core/cloud_auth/cloud_auth.dart';

class PairingDetails {
  const PairingDetails._({
    required this.address,
    required this.hubId,
    required this.enrollmentSecret,
  });

  factory PairingDetails.fromJson(Map<String, dynamic> json) {
    if (json['version'] != null && json['version'] != 1) {
      throw const FormatException('Unsupported hub pairing details version.');
    }
    final address = json['address'];
    final hubId = json['hub_id'] ?? json['hubId'];
    final secret = json['enrollment_secret'] ?? json['enrollmentSecret'];
    if (address is! String || hubId is! String || secret is! String) {
      throw const FormatException(
        'Pairing JSON needs an address, hub ID, and enrollment secret.',
      );
    }
    return PairingDetails.fromManualFields(
      address: address,
      hubId: hubId,
      enrollmentSecret: secret,
    );
  }

  factory PairingDetails.fromManualFields({
    required String address,
    required String hubId,
    required String enrollmentSecret,
  }) {
    final endpoint = HubEndpoint.parse(address);
    if (endpoint.pin == null) {
      throw const FormatException(
        'Include the hub certificate SHA-256 pin in the address.',
      );
    }
    if (hubId.trim().isEmpty || enrollmentSecret.isEmpty) {
      throw const FormatException('Hub ID and enrollment secret are required.');
    }
    return PairingDetails._(
      address: address.trim(),
      hubId: hubId.trim(),
      enrollmentSecret: enrollmentSecret,
    );
  }

  final String address;
  final String hubId;
  final String enrollmentSecret;
}

class PairingClaim {
  const PairingClaim({
    required this.hubId,
    required this.clientId,
    required this.token,
    this.ownershipEpoch,
  });

  final String hubId;
  final String clientId;
  final String token;
  final int? ownershipEpoch;
}

class PairingException implements Exception {
  const PairingException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class HubRequestException extends StateError {
  HubRequestException(this.statusCode, this.code, String message)
    : super(message);
  final int statusCode;
  final String? code;
  bool get requiresPairing => statusCode == 401 && code == 'requires_pairing';
}

class PairingHttpResponse {
  const PairingHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

abstract interface class PairingTransport {
  Future<PairingHttpResponse> send(
    String address,
    String path,
    String method, {
    Map<String, dynamic>? body,
    String? bearerToken,
  });
}

class IoPairingTransport implements PairingTransport {
  const IoPairingTransport();

  @override
  Future<PairingHttpResponse> send(
    String address,
    String path,
    String method, {
    Map<String, dynamic>? body,
    String? bearerToken,
  }) async {
    final endpoint = HubEndpoint.parse(address);
    final client = HttpClient(
      context: endpoint.pin == null
          ? null
          : SecurityContext(withTrustedRoots: false),
    )..connectionTimeout = const Duration(seconds: 4);
    if (endpoint.pin case final pin?) {
      client.badCertificateCallback = (certificate, host, port) {
        final now = DateTime.now();
        return host == endpoint.uri.host &&
            port == endpoint.uri.port &&
            !now.isBefore(certificate.startValidity) &&
            !now.isAfter(certificate.endValidity) &&
            matchesHubCertificatePin(certificate.der, pin);
      };
    }
    try {
      final request = await client
          .openUrl(method, endpoint.uri.replace(path: path))
          .timeout(const Duration(seconds: 5));
      request.followRedirects = false;
      if (bearerToken != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $bearerToken',
        );
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      return PairingHttpResponse(
        statusCode: response.statusCode,
        body: await utf8.decoder.bind(response).join(),
      );
    } finally {
      client.close(force: true);
    }
  }
}

class IdentificationCandidate {
  const IdentificationCandidate({
    required this.manufacturer,
    required this.model,
    required this.confidence,
    required this.source,
    required this.matchedKinds,
    this.category,
    this.sourceUrl,
  });

  factory IdentificationCandidate.fromJson(Map<String, dynamic> json) =>
      IdentificationCandidate(
        manufacturer: json['manufacturer'] as String,
        model: json['model'] as String,
        category: json['category'] as String?,
        confidence: (json['confidence'] as num).toDouble(),
        source: json['source'] as String,
        sourceUrl: json['source_url'] as String?,
        matchedKinds: (json['matched_kinds'] as List<dynamic>).cast<String>(),
      );

  final String manufacturer;
  final String model;
  final String? category;
  final double confidence;
  final String source;
  final String? sourceUrl;
  final List<String> matchedKinds;

  String get evidenceLabel => switch (source) {
    'upc_exact' => 'Reviewed catalog · exact barcode',
    'ocr_catalog_exact' => 'Reviewed catalog · model text',
    _ => 'Text read from label',
  };
}

class DiscoveredPlug {
  const DiscoveredPlug({
    required this.id,
    required this.ip,
    required this.model,
    required this.meterStatus,
    this.alias,
    this.mac,
    this.localProtocol,
    this.httpPort,
    this.hardwareVersion,
    this.firmwareVersion,
    this.relayOn,
  });

  factory DiscoveredPlug.fromJson(Map<String, dynamic> json) => DiscoveredPlug(
    id: json['id'] as String,
    ip: json['ip'] as String,
    model: json['model'] as String,
    meterStatus: json['meter_status'] as String,
    alias: json['alias'] as String?,
    mac: json['mac'] as String?,
    localProtocol: json['local_protocol'] as String?,
    httpPort: json['http_port'] as int?,
    hardwareVersion: json['hardware_version'] as String?,
    firmwareVersion: json['firmware_version'] as String?,
    relayOn: json['relay_on'] as bool?,
  );

  final String id;
  final String ip;
  final String model;
  final String meterStatus;
  final String? alias;
  final String? mac;
  final String? localProtocol;
  final int? httpPort;
  final String? hardwareVersion;
  final String? firmwareVersion;
  final bool? relayOn;
}

/// A temporary discovery result. Identity and energy capability are independent
/// of network address, so this DTO does not inherit the legacy plug shape.
class NearbyDeviceCandidate {
  const NearbyDeviceCandidate({
    required this.id,
    required this.scanId,
    required this.expiresAtMs,
    required this.requiresAction,
    required this.addresses,
    this.sources = const [],
    required this.capabilities,
    this.manufacturer,
    this.model,
    this.category,
    this.name,
    this.reasonCode,
  });

  factory NearbyDeviceCandidate.fromJson(Map<String, dynamic> json) =>
      NearbyDeviceCandidate(
        id: json['candidate_id'] as String,
        scanId: json['scan_id'] as String,
        expiresAtMs: json['expires_at_ms'] as int,
        manufacturer: json['manufacturer'] as String?,
        model: json['model'] as String?,
        category: json['category'] as String?,
        name: json['name'] as String?,
        requiresAction: json['requires_action'] as bool,
        reasonCode: json['reason_code'] as String?,
        addresses: (json['addresses'] as List<dynamic>)
            .map(
              (value) =>
                  NearbyDeviceAddress.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
        sources: (json['sources'] as List<dynamic>).cast<String>(),
        capabilities: (json['capabilities'] as List<dynamic>)
            .map(
              (value) => NearbyDeviceCapability.fromJson(
                value as Map<String, dynamic>,
              ),
            )
            .toList(growable: false),
      );

  final String id;
  final String scanId;
  final int expiresAtMs;
  final String? manufacturer;
  final String? model;
  final String? category;
  final String? name;
  final bool requiresAction;
  final String? reasonCode;
  final List<NearbyDeviceAddress> addresses;
  final List<String> sources;
  final List<NearbyDeviceCapability> capabilities;

  String get displayName {
    final value = name?.trim().isNotEmpty == true
        ? name!.trim()
        : model?.trim();
    return value == null || value.isEmpty ? 'Unnamed device' : value;
  }

  bool get canAdopt =>
      !requiresAction && DateTime.now().millisecondsSinceEpoch < expiresAtMs;

  String? get manualProtocol {
    for (final source in sources) {
      if (const {'kasa', 'shelly_gen2', 'tasmota'}.contains(source)) {
        return source;
      }
    }
    return null;
  }

  String? get manualIpv4 => addresses
      .where((address) => address.kind == 'ipv4')
      .map((address) => address.value)
      .firstOrNull;
}

class NearbyDeviceAddress {
  const NearbyDeviceAddress(this.kind, this.value, this.interfaceName);

  factory NearbyDeviceAddress.fromJson(Map<String, dynamic> json) =>
      NearbyDeviceAddress(
        json['kind'] as String,
        json['value'] as String,
        json['interface'] as String?,
      );

  final String kind;
  final String value;
  final String? interfaceName;
}

class NearbyDeviceCapability {
  const NearbyDeviceCapability(this.name, this.supportState);

  factory NearbyDeviceCapability.fromJson(Map<String, dynamic> json) =>
      NearbyDeviceCapability(
        json['name'] as String,
        json['support_state'] as String,
      );

  final String name;
  final String supportState;
}

class NearbyScan {
  const NearbyScan({
    required this.id,
    required this.state,
    required this.expiresAtMs,
    this.candidates = const [],
    this.nextCursor,
  });

  factory NearbyScan.fromJson(Map<String, dynamic> json) => NearbyScan(
    id: json['scan_id'] as String,
    state: json['state'] as String,
    expiresAtMs: json['expires_at_ms'] as int,
    candidates: ((json['candidates'] as List<dynamic>?) ?? const [])
        .map(
          (value) =>
              NearbyDeviceCandidate.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false),
    nextCursor: json['next_cursor'] as String?,
  );

  final String id;
  final String state;
  final int expiresAtMs;
  final List<NearbyDeviceCandidate> candidates;
  final String? nextCursor;
  bool get isTerminal =>
      const {'complete', 'partial', 'failed', 'cancelled'}.contains(state);
}

class NearbySavedDevice {
  const NearbySavedDevice(
    this.id,
    this.name, {
    this.manufacturer,
    this.model,
    this.endpoints = const [],
    this.bindings = const [],
  });

  factory NearbySavedDevice.fromJson(Map<String, dynamic> json) =>
      NearbySavedDevice(
        json['id'] as String,
        json['name'] as String,
        manufacturer: json['manufacturer'] as String?,
        model: json['model'] as String?,
        endpoints: ((json['endpoints'] as List<dynamic>?) ?? const [])
            .map(
              (item) =>
                  NearbyDeviceEndpoint.fromJson(item as Map<String, dynamic>),
            )
            .toList(growable: false),
        bindings: ((json['bindings'] as List<dynamic>?) ?? const [])
            .map(
              (item) =>
                  NearbyDeviceBinding.fromJson(item as Map<String, dynamic>),
            )
            .toList(growable: false),
      );

  final String id;
  final String name;
  final String? manufacturer;
  final String? model;
  final List<NearbyDeviceEndpoint> endpoints;
  final List<NearbyDeviceBinding> bindings;
}

class NearbyDeviceEndpoint {
  const NearbyDeviceEndpoint(
    this.id,
    this.componentId,
    this.measurementScope,
    this.parentEndpointId,
    this.capabilities,
  );

  factory NearbyDeviceEndpoint.fromJson(Map<String, dynamic> json) =>
      NearbyDeviceEndpoint(
        json['id'] as String,
        json['component_id'] as String,
        json['measurement_scope'] as String,
        json['parent_endpoint_id'] as String?,
        (json['capabilities'] as List<dynamic>)
            .map(
              (item) =>
                  NearbyDeviceCapability.fromJson(item as Map<String, dynamic>),
            )
            .toList(growable: false),
      );

  final String id;
  final String componentId;
  final String measurementScope;
  final String? parentEndpointId;
  final List<NearbyDeviceCapability> capabilities;
}

class NearbyDeviceBinding {
  const NearbyDeviceBinding(
    this.id,
    this.protocol,
    this.adapterInstanceId,
    this.securityDomainId,
    this.nativeDeviceId,
  );

  factory NearbyDeviceBinding.fromJson(Map<String, dynamic> json) =>
      NearbyDeviceBinding(
        json['id'] as String,
        json['protocol'] as String,
        json['adapter_instance_id'] as String,
        json['security_domain_id'] as String,
        json['native_device_id'] as String,
      );

  final String id;
  final String protocol;
  final String adapterInstanceId;
  final String securityDomainId;
  final String nativeDeviceId;
}

class SavedPlug {
  const SavedPlug({
    required this.id,
    required this.ip,
    required this.model,
    required this.name,
    required this.room,
    required this.meterStatus,
    required this.lastVerifiedAt,
    this.connectionStatus = 'unverified',
    this.statusCheckedAt,
    this.connectedAppliance,
    this.mac,
    this.localProtocol,
    this.httpPort,
  });

  factory SavedPlug.fromJson(Map<String, dynamic> json) => SavedPlug(
    id: json['id'] as String,
    ip: json['ip'] as String,
    model: json['model'] as String,
    name: json['name'] as String,
    room: json['room'] as String,
    meterStatus: json['meter_status'] as String,
    lastVerifiedAt: json['last_verified_at'] as int,
    connectionStatus: json['connection_status'] as String? ?? 'unverified',
    statusCheckedAt: json['status_checked_at'] as int?,
    mac: json['mac'] as String?,
    localProtocol: json['local_protocol'] as String?,
    httpPort: json['http_port'] as int?,
    connectedAppliance: json['connected_appliance'] == null
        ? null
        : SavedAppliance.fromJson(
            json['connected_appliance'] as Map<String, dynamic>,
          ),
  );

  final String id;
  final String ip;
  final String model;
  final String name;
  final String room;
  final String meterStatus;
  final int lastVerifiedAt;
  final String connectionStatus;
  final int? statusCheckedAt;
  final SavedAppliance? connectedAppliance;
  final String? mac;
  final String? localProtocol;
  final int? httpPort;
}

class AttachmentHistoryEntry {
  const AttachmentHistoryEntry({
    required this.applianceId,
    required this.attachedAt,
    this.detachedAt,
    this.snapshotVersion,
    this.snapshotRecordedAt,
    this.applianceSnapshot,
    this.evidenceSnapshot,
    this.estimateSnapshot,
  });

  factory AttachmentHistoryEntry.fromJson(Map<String, dynamic> json) =>
      AttachmentHistoryEntry(
        applianceId: json['appliance_id'] as int,
        attachedAt: json['attached_at'] as int,
        detachedAt: json['detached_at'] as int?,
        snapshotVersion: json['snapshot_version'] as int?,
        snapshotRecordedAt: json['snapshot_recorded_at'] as int?,
        applianceSnapshot: json['appliance_snapshot'] as Map<String, dynamic>?,
        evidenceSnapshot: json['evidence_snapshot'] as Map<String, dynamic>?,
        estimateSnapshot: json['estimate_snapshot'] as Map<String, dynamic>?,
      );

  final int applianceId;
  final int attachedAt;
  final int? detachedAt;
  final int? snapshotVersion;
  final int? snapshotRecordedAt;
  final Map<String, dynamic>? applianceSnapshot;
  final Map<String, dynamic>? evidenceSnapshot;
  final Map<String, dynamic>? estimateSnapshot;
}

class DeviceEnergy {
  const DeviceEnergy({
    required this.status,
    required this.period,
    required this.totalKwh,
    required this.coverageFraction,
    required this.coveredSecs,
    this.deviceId,
    this.latestWatts,
    this.observedCostUsd,
    this.rateSourceLabel,
    this.rateUsdPerKwh,
    this.rateSource,
    this.rateAsOf,
    this.rateSourceUrl,
    this.rateFetchedAt,
    this.rateIsStale = false,
    this.rateStatus,
    this.readingCount = 0,
    this.readings = const [],
  });

  factory DeviceEnergy.fromJson(Map<String, dynamic> json) => DeviceEnergy(
    status: json['status'] as String,
    period: json['period'] as String,
    deviceId: json['device_id'] as String?,
    totalKwh: (json['total_kwh'] as num).toDouble(),
    coverageFraction: (json['coverage_fraction'] as num).toDouble(),
    coveredSecs: (json['covered_secs'] as num).toDouble(),
    latestWatts: (json['latest_watts'] as num?)?.toDouble(),
    observedCostUsd: (json['observed_cost_usd'] as num?)?.toDouble(),
    rateSourceLabel: json['rate_source_label'] as String?,
    rateUsdPerKwh: (json['rate_usd_per_kwh'] as num?)?.toDouble(),
    rateSource: json['rate_source'] as String?,
    rateAsOf: json['rate_as_of'] as String?,
    rateSourceUrl: json['rate_source_url'] as String?,
    rateFetchedAt: (json['rate_fetched_at'] as num?)?.toInt(),
    rateIsStale: json['rate_is_stale'] == true,
    rateStatus: json['rate_status'] as String?,
    readings: (json['readings'] as List<dynamic>? ?? const [])
        .map((item) => EnergyReading.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
    readingCount: (json['readings'] as List<dynamic>?)?.length ?? 0,
  );

  final String status;
  final String period;
  final String? deviceId;
  final double totalKwh;
  final double coverageFraction;
  final double coveredSecs;
  final double? latestWatts;
  final double? observedCostUsd;
  final String? rateSourceLabel;
  final double? rateUsdPerKwh;
  final String? rateSource;
  final String? rateAsOf;
  final String? rateSourceUrl;
  final int? rateFetchedAt;
  final bool rateIsStale;
  final String? rateStatus;
  final int readingCount;
  final List<EnergyReading> readings;

  EnergyReading? get latestSample => readings.isEmpty ? null : readings.last;
}

class DeviceBaselineCoverage {
  const DeviceBaselineCoverage({
    required this.deviceId,
    required this.applianceId,
    required this.windowStart,
    required this.windowEnd,
    required this.latestSampleAt,
    required this.sampleCount,
    required this.coveredSecs,
    required this.coverageFraction,
    required this.coveredDays,
    required this.requiredDays,
    required this.status,
    required this.reason,
  });

  factory DeviceBaselineCoverage.fromJson(Map<String, dynamic> json) =>
      DeviceBaselineCoverage(
        deviceId: json['device_id'] as String,
        applianceId: json['appliance_id'] as int?,
        windowStart: DateTime.parse(json['window_start'] as String),
        windowEnd: DateTime.parse(json['window_end'] as String),
        latestSampleAt: json['latest_sample_at'] == null
            ? null
            : DateTime.parse(json['latest_sample_at'] as String),
        sampleCount: json['sample_count'] as int,
        coveredSecs: (json['covered_secs'] as num).toDouble(),
        coverageFraction: (json['coverage_fraction'] as num).toDouble(),
        coveredDays: json['covered_days'] as int,
        requiredDays: json['required_days'] as int,
        status: json['status'] as String,
        reason: json['reason'] as String,
      );

  final String deviceId;
  final int? applianceId;
  final DateTime windowStart;
  final DateTime windowEnd;
  final DateTime? latestSampleAt;
  final int sampleCount;
  final double coveredSecs;
  final double coverageFraction;
  final int coveredDays;
  final int requiredDays;
  final String status;
  final String reason;
}

class AppliancePerUseBaseline {
  const AppliancePerUseBaseline({
    required this.applianceId,
    required this.status,
    required this.reason,
    required this.plugId,
    required this.attachmentStartedAt,
    required this.policyId,
    required this.policyRevision,
    required this.evaluationId,
    required this.ownershipScope,
    required this.ownershipEpoch,
    required this.windowStart,
    required this.windowEnd,
    required this.qualifyingSessions,
    required this.requiredSessions,
    required this.medianKwhPerUse,
  });

  factory AppliancePerUseBaseline.fromJson(Map<String, dynamic> json) {
    final evaluation = json['evaluation'] as Map<String, dynamic>?;
    return AppliancePerUseBaseline(
      applianceId: json['appliance_id'] as int,
      status: json['status'] as String,
      reason: json['reason'] as String,
      plugId: json['plug_id'] as String?,
      attachmentStartedAt: json['attachment_started_at'] as int?,
      policyId: json['policy_id'] as int?,
      policyRevision: json['policy_revision'] as int?,
      evaluationId: json['evaluation_id'] as int?,
      ownershipScope: json['ownership_scope'] as String?,
      ownershipEpoch: json['ownership_epoch'] as int?,
      windowStart: evaluation?['window_start'] == null
          ? null
          : DateTime.parse(evaluation!['window_start'] as String),
      windowEnd: evaluation?['window_end'] == null
          ? null
          : DateTime.parse(evaluation!['window_end'] as String),
      qualifyingSessions: evaluation?['qualifying_sessions'] as int?,
      requiredSessions: evaluation?['required_sessions'] as int?,
      medianKwhPerUse: (evaluation?['median_kwh_per_use'] as num?)?.toDouble(),
    );
  }

  final int applianceId;
  final String status;
  final String reason;
  final String? plugId;
  final int? attachmentStartedAt;
  final int? policyId;
  final int? policyRevision;
  final int? evaluationId;
  final String? ownershipScope;
  final int? ownershipEpoch;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final int? qualifyingSessions;
  final int? requiredSessions;
  final double? medianKwhPerUse;

  bool get hasQualifiedValue =>
      status == 'ready' &&
      policyId != null &&
      attachmentStartedAt != null &&
      evaluationId != null &&
      ownershipScope != null &&
      ownershipEpoch != null &&
      medianKwhPerUse != null;
}

class EnergyReading {
  const EnergyReading({
    required this.ts,
    required this.watts,
    this.kwhCumulative,
  });

  factory EnergyReading.fromJson(Map<String, dynamic> json) => EnergyReading(
    ts: DateTime.parse(json['ts'] as String),
    watts: (json['watts'] as num).toDouble(),
    kwhCumulative: (json['kwh_cumulative'] as num?)?.toDouble(),
  );

  final DateTime ts;
  final double watts;
  final double? kwhCumulative;
}

class SavedAppliance {
  const SavedAppliance({
    required this.id,
    required this.name,
    required this.room,
    required this.category,
    required this.manufacturer,
    required this.model,
    required this.loadKind,
    required this.onboardingMethod,
    this.hoursPerWeek,
    this.initialHoursPerWeek,
    this.bulbCount,
    this.combinedInputWatts,
  });

  factory SavedAppliance.fromJson(Map<String, dynamic> json) => SavedAppliance(
    id: json['id'] as int,
    name: json['name'] as String,
    room: json['room'] as String,
    category: json['category'] as String,
    manufacturer: json['manufacturer'] as String,
    model: json['model'] as String,
    loadKind: json['load_kind'] as String,
    onboardingMethod: json['onboarding_method'] as String,
    hoursPerWeek: (json['hours_per_week'] as num?)?.toDouble(),
    initialHoursPerWeek: (json['initial_hours_per_week'] as num?)?.toDouble(),
    bulbCount: json['bulb_count'] as int?,
    combinedInputWatts: (json['combined_input_watts'] as num?)?.toDouble(),
  );

  final int id;
  final String name;
  final String room;
  final String category;
  final String manufacturer;
  final String model;
  final String loadKind;
  final String onboardingMethod;
  final double? hoursPerWeek;
  final double? initialHoursPerWeek;
  final int? bulbCount;
  final double? combinedInputWatts;
}

class ApplianceInput {
  const ApplianceInput({
    required this.name,
    required this.room,
    required this.category,
    required this.manufacturer,
    required this.model,
    required this.loadKind,
    required this.onboardingMethod,
    this.hoursPerWeek,
    this.bulbCount,
    this.combinedInputWatts,
  });

  final String name;
  final String room;
  final String category;
  final String manufacturer;
  final String model;
  final String loadKind;
  final String onboardingMethod;
  final double? hoursPerWeek;
  final int? bulbCount;
  final double? combinedInputWatts;

  Map<String, dynamic> toJson() => {
    'name': name,
    'room': room,
    'category': category,
    'manufacturer': manufacturer,
    'model': model,
    'load_kind': loadKind,
    'onboarding_method': onboardingMethod,
    'hours_per_week': hoursPerWeek,
    'bulb_count': bulbCount,
    'combined_input_watts': combinedInputWatts,
  };
}

class EnergyEvidence {
  const EnergyEvidence({
    required this.sourceKind,
    required this.datasetId,
    required this.sourceUrl,
    required this.matchedBrand,
    required this.matchedModel,
    required this.annualKwh,
    this.energyStarModelIdentifier,
    this.standbyWatts,
    required this.usageBasis,
    required this.retrievedAt,
  });

  factory EnergyEvidence.fromJson(Map<String, dynamic> json) => EnergyEvidence(
    sourceKind: json['source_kind'] as String,
    datasetId: json['dataset_id'] as String,
    sourceUrl: json['source_url'] as String,
    matchedBrand: json['matched_brand'] as String,
    matchedModel: json['matched_model'] as String,
    annualKwh: (json['annual_kwh'] as num).toDouble(),
    energyStarModelIdentifier: json['energy_star_model_identifier'] as String?,
    standbyWatts: (json['standby_watts'] as num?)?.toDouble(),
    usageBasis: json['usage_basis'] as String,
    retrievedAt: json['retrieved_at'] as int,
  );

  final String sourceKind;
  final String datasetId;
  final String sourceUrl;
  final String matchedBrand;
  final String matchedModel;
  final double annualKwh;
  final String? energyStarModelIdentifier;
  final double? standbyWatts;
  final String usageBasis;
  final int retrievedAt;
}

String energySourceHeading(EnergyEvidence source) =>
    switch (source.sourceKind) {
      'epa_exact' => 'EPA rated energy data',
      'energy_star' => 'ENERGY STAR data (EPA)',
      'energy_star_archive' => 'Historical ENERGY STAR data (EPA)',
      'oem_exact' => 'Manufacturer model test data',
      'oem' => 'Manufacturer data',
      'oem_family' => 'Manufacturer family test data',
      'energuide_family' => 'Historical EnerGuide family test data',
      'user_label' => 'Bulb ratings you entered',
      'category_typical' => 'Category typical use',
      _ => 'Source details',
    };

class EnergyLookup {
  const EnergyLookup({required this.status, this.evidence});
  factory EnergyLookup.fromJson(Map<String, dynamic> json) => EnergyLookup(
    status: json['status'] as String,
    evidence: json['evidence'] == null
        ? null
        : EnergyEvidence.fromJson(json['evidence'] as Map<String, dynamic>),
  );
  final String status;
  final EnergyEvidence? evidence;
}

class ApplianceSpecEvidence {
  const ApplianceSpecEvidence({
    required this.sourceKind,
    required this.ratedInputWatts,
    required this.sourceUrl,
    required this.matchedBrand,
    required this.matchedModel,
    required this.usageBasis,
    required this.retrievedAt,
  });

  factory ApplianceSpecEvidence.fromJson(Map<String, dynamic> json) =>
      ApplianceSpecEvidence(
        sourceKind: json['source_kind'] as String,
        ratedInputWatts: (json['rated_input_watts'] as num).toDouble(),
        sourceUrl: json['source_url'] as String,
        matchedBrand: json['matched_brand'] as String,
        matchedModel: json['matched_model'] as String,
        usageBasis: json['usage_basis'] as String,
        retrievedAt: (json['retrieved_at'] as num).toInt(),
      );

  final String sourceKind;
  final double ratedInputWatts;
  final String sourceUrl;
  final String matchedBrand;
  final String matchedModel;
  final String usageBasis;
  final int retrievedAt;
}

class ApplianceSpec {
  const ApplianceSpec({required this.status, this.evidence});

  factory ApplianceSpec.fromJson(Map<String, dynamic> json) => ApplianceSpec(
    status: json['status'] as String,
    evidence: json['evidence'] == null
        ? null
        : ApplianceSpecEvidence.fromJson(
            json['evidence'] as Map<String, dynamic>,
          ),
  );

  final String status;
  final ApplianceSpecEvidence? evidence;
}

class EnergyEstimate {
  const EnergyEstimate({
    required this.status,
    this.period = 'month',
    this.reason,
    this.estimatedKwh,
    this.estimatedCostUsd,
    this.activeKwh,
    this.standbyKwh,
    this.activeCostUsd,
    this.standbyCostUsd,
    this.rateSource,
    this.rateUsdPerKwh,
    this.rateSourceLabel,
    this.rateAsOf,
    this.rateSourceUrl,
    this.rateStatus,
    this.bulbCount,
    this.evidence,
    this.measurementCoverageFraction,
    this.fetchedAt,
    this.isStale = false,
  });
  factory EnergyEstimate.fromJson(Map<String, dynamic> json) => EnergyEstimate(
    status: json['status'] as String,
    period: json['period'] as String? ?? 'month',
    reason: json['reason'] as String?,
    estimatedKwh: (json['estimated_kwh'] as num?)?.toDouble(),
    estimatedCostUsd: (json['estimated_cost_usd'] as num?)?.toDouble(),
    activeKwh: (json['active_kwh'] as num?)?.toDouble(),
    standbyKwh: (json['standby_kwh'] as num?)?.toDouble(),
    activeCostUsd: (json['active_cost_usd'] as num?)?.toDouble(),
    standbyCostUsd: (json['standby_cost_usd'] as num?)?.toDouble(),
    rateSource: json['rate_source'] as String?,
    rateUsdPerKwh: (json['rate_usd_per_kwh'] as num?)?.toDouble(),
    rateSourceLabel: json['rate_source_label'] as String?,
    rateAsOf: json['rate_as_of'] as String?,
    rateSourceUrl: json['rate_source_url'] as String?,
    rateStatus: json['rate_status'] as String?,
    bulbCount: json['bulb_count'] as int?,
    evidence: json['evidence'] == null
        ? null
        : EnergyEvidence.fromJson(json['evidence'] as Map<String, dynamic>),
    measurementCoverageFraction: (json['measurement_coverage_fraction'] as num?)
        ?.toDouble(),
    fetchedAt: ((json['fetched_at'] ?? json['rate_fetched_at']) as num?)
        ?.toInt(),
    isStale: json['is_stale'] == true || json['rate_is_stale'] == true,
  );
  final String status;
  final String period;
  final String? reason;
  final double? estimatedKwh;
  final double? estimatedCostUsd;
  final double? activeKwh;
  final double? standbyKwh;
  final double? activeCostUsd;
  final double? standbyCostUsd;
  final String? rateSource;
  final double? rateUsdPerKwh;
  final String? rateSourceLabel;
  final String? rateAsOf;
  final String? rateSourceUrl;
  final String? rateStatus;
  final int? bulbCount;
  final EnergyEvidence? evidence;
  final double? measurementCoverageFraction;
  final int? fetchedAt;
  final bool isStale;
}

class ElectricitySettings {
  const ElectricitySettings({this.postalCode, this.rateUsdPerKwh});

  factory ElectricitySettings.fromJson(Map<String, dynamic> json) =>
      ElectricitySettings(
        postalCode: json['postal_code'] as String?,
        rateUsdPerKwh: (json['rate_usd_per_kwh'] as num?)?.toDouble(),
      );

  final String? postalCode;
  final double? rateUsdPerKwh;
}

String energyRateDescription(EnergyEstimate estimate) {
  final isStale = estimate.isStale || estimate.rateStatus == 'stale';
  if (estimate.rateUsdPerKwh case final rate?) {
    final label = estimate.rateSourceLabel ?? 'Electricity rate';
    if (isStale) {
      return '$label: \$${rate.toStringAsFixed(4)}/kWh · Cached regional rate${estimate.rateAsOf == null ? '' : ' from ${estimate.rateAsOf}'}; fresh regional rate unavailable.';
    }
    final asOf = estimate.rateAsOf == null ? '' : ' · ${estimate.rateAsOf}';
    return '$label: \$${rate.toStringAsFixed(4)}/kWh$asOf';
  }
  if (isStale) {
    return 'Cached regional rate is stale${estimate.rateAsOf == null ? '' : ' (from ${estimate.rateAsOf})'}; fresh regional rate unavailable.';
  }
  if (estimate.rateStatus == 'unavailable') {
    return 'Regional rate unavailable. Enter your bill rate for a cost estimate.';
  }
  return 'Add a ZIP code or your bill rate to see estimated cost.';
}

class ApplianceUsageProfile {
  const ApplianceUsageProfile({
    required this.applianceId,
    required this.usageKind,
    required this.value,
    required this.initialValue,
    required this.min,
    required this.max,
    required this.step,
  });

  factory ApplianceUsageProfile.fromJson(Map<String, dynamic> json) =>
      ApplianceUsageProfile(
        applianceId: json['appliance_id'] as int,
        usageKind: json['usage_kind'] as String,
        value: (json['value'] as num).toDouble(),
        initialValue: (json['initial_value'] as num).toDouble(),
        min: (json['min'] as num).toDouble(),
        max: (json['max'] as num).toDouble(),
        step: (json['step'] as num).toDouble(),
      );

  final int applianceId;
  final String usageKind;
  final double value;
  final double initialValue;
  final double min;
  final double max;
  final double step;
}

class DiscoveryApi {
  Future<EnergyCategories?> energyCategories(
    String baseUrl,
    String token, {
    String? etag,
  }) async {
    final body = await _request(baseUrl, token, '/v1/energy-categories', 'GET');
    final json = body as Map<String, dynamic>;
    return EnergyCategories.fromJson(json, '"${json['version']}"');
  }

  const DiscoveryApi({
    this.pairingTransport = const IoPairingTransport(),
    this.ownerAuthorization,
  });

  final PairingTransport pairingTransport;
  final HubOwnerAuthorization? ownerAuthorization;

  DiscoveryApi authorizedFor(HubOwnerAuthorization owner) => DiscoveryApi(
    pairingTransport: pairingTransport,
    ownerAuthorization: owner,
  );

  /// A 404 means an older Hub. Other failures must remain visible instead of
  /// silently changing the user's scan to the legacy plug-only path.
  Future<bool> supportsNearbyDiscovery(String baseUrl, String token) async {
    try {
      final response = await _request(baseUrl, token, '/v2/adapters', 'GET');
      if (response is! Map<String, dynamic> || response['version'] != 2) {
        throw const FormatException('Unsupported Hub adapter version.');
      }
      return true;
    } on _V2UnavailableException {
      return false;
    }
  }

  Future<NearbyScan> startNearbyScan(String baseUrl, String token) async {
    final response = await _post(baseUrl, token, '/v2/discovery/scans', {});
    return NearbyScan.fromJson(response);
  }

  Future<NearbyScan> nearbyScan(
    String baseUrl,
    String token,
    String scanId, {
    String? cursor,
  }) async {
    final response = await _request(
      baseUrl,
      token,
      '/v2/discovery/scans/${Uri.encodeComponent(scanId)}',
      'GET',
      null,
      cursor == null ? null : {'cursor': cursor},
    );
    return NearbyScan.fromJson(response as Map<String, dynamic>);
  }

  Future<NearbyScan> cancelNearbyScan(
    String baseUrl,
    String token,
    String scanId,
  ) async {
    final response = await _post(
      baseUrl,
      token,
      '/v2/discovery/scans/${Uri.encodeComponent(scanId)}/cancel',
      {},
    );
    return NearbyScan.fromJson(response);
  }

  Future<List<NearbySavedDevice>> nearbyInventory(
    String baseUrl,
    String token,
  ) async {
    final response = await _request(baseUrl, token, '/v2/devices', 'GET');
    return (response as List<dynamic>)
        .map((item) => NearbySavedDevice.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<NearbySavedDevice> adoptNearby(
    String baseUrl,
    String token,
    NearbyDeviceCandidate candidate,
    String name,
  ) async {
    if (!candidate.canAdopt) {
      throw StateError('Candidate requires setup or a new scan.');
    }
    final response = await _post(baseUrl, token, '/v2/devices', {
      'candidate_id': candidate.id,
      'name': name,
      'room': '',
    });
    return NearbySavedDevice.fromJson(response);
  }

  Future<HubClaimProof> claimProof(
    HubClaimChallenge challenge, {
    required String address,
    required String hubId,
    required String token,
  }) async {
    await verifyStoredPairing(
      StoredHubIdentity(address: address, hubId: hubId),
    );
    if (challenge.localHubId != hubId) {
      throw const PairingException(
        'The cloud challenge is for a different hub.',
      );
    }
    final response = await pairingTransport.send(
      address,
      '/v1/cloud/claim-proofs',
      'POST',
      body: challenge.toJson(),
      bearerToken: token,
    );
    final json = _decodePairingResponse(response);
    final proof = HubClaimProof.fromJson(json);
    if (proof.claimId != challenge.claimId || proof.localHubId != hubId) {
      throw const PairingException(
        'The hub returned a proof for a different claim.',
      );
    }
    return proof;
  }

  /// Rechecks the pinned endpoint and saved hub identity on app restart.
  Future<void> verifyStoredPairing(StoredHubIdentity pairing) async {
    final endpoint = HubEndpoint.parse(pairing.address);
    if (endpoint.pin == null) {
      throw const PairingException(
        'Pair this hub again with its certificate pin.',
      );
    }
    final health = await pairingTransport.send(
      pairing.address,
      '/healthz',
      'GET',
    );
    final healthJson = _decodePairingResponse(health);
    if (healthJson['hub_id'] != pairing.hubId) {
      throw const PairingException(
        'The saved hub identity has changed. Pair again.',
      );
    }
  }

  /// Checks the out-of-band hub identity before sending the enrollment secret.
  Future<PairingClaim> claimPairing(
    PairingDetails details, {
    required String clientId,
  }) async {
    final health = await pairingTransport.send(
      details.address,
      '/healthz',
      'GET',
    );
    final healthJson = _decodePairingResponse(health);
    if (healthJson['hub_id'] != details.hubId) {
      throw const PairingException('The hub identity does not match.');
    }

    final claim = await pairingTransport.send(
      details.address,
      '/v1/pairing/claim',
      'POST',
      body: {
        'hub_id': details.hubId,
        'enrollment_secret': details.enrollmentSecret,
        'client_id': clientId,
      },
    );
    final claimJson = _decodePairingResponse(claim);
    final token = claimJson['token'];
    if (claimJson['hub_id'] != details.hubId ||
        claimJson['client_id'] != clientId ||
        claimJson['token_type'] != 'Bearer' ||
        token is! String ||
        token.isEmpty) {
      throw const PairingException('The hub returned no client token.');
    }
    final epoch = claimJson['ownership_epoch'];
    if (epoch != null && (epoch is! int || epoch < 0)) {
      throw const PairingException('The hub returned no client token.');
    }
    return PairingClaim(
      hubId: details.hubId,
      clientId: clientId,
      token: token,
      ownershipEpoch: epoch as int?,
    );
  }

  /// Cloud-authenticated endpoint metadata is the trust anchor. Check the pin
  /// and local identity before obtaining or sending the owner's Cloud JWT.
  Future<PairingClaim> claimOwnedPairing(
    HubOwnership ownership, {
    required String clientId,
    required HubOwnerAuthorization owner,
  }) async {
    final connection = ownership.connection;
    final generation = owner.session.generation;
    bool current() =>
        owner.isCurrent() &&
        owner.session.generation == generation &&
        ownership.homeId == owner.homeId &&
        connection != null &&
        connection.isFresh;
    if (!current() || ownership.ownershipEpoch < 2 || clientId.isEmpty) {
      throw StateError('Hub owner authorization is no longer current');
    }
    final address =
        '${connection!.httpsOrigin}#sha256=${connection.certificateSha256}';
    final endpoint = HubEndpoint.parse(address);
    if (endpoint.pin == null) throw StateError('Missing Hub certificate pin');
    await verifyStoredPairing(
      StoredHubIdentity(address: address, hubId: ownership.localHubId),
    );
    if (!current()) throw StateError('Hub owner authorization changed');
    final token = await owner.session.accessToken();
    if (token == null || !current()) {
      throw StateError('Hub owner authorization changed');
    }
    final response = await pairingTransport.send(
      address,
      '/v1/pairing/owner-claim',
      'POST',
      bearerToken: token,
      body: {
        'cloud_hub_id': ownership.hubId,
        'hub_id': ownership.localHubId,
        'home_id': ownership.homeId,
        'ownership_epoch': ownership.ownershipEpoch,
        'client_id': clientId,
      },
    );
    if (!current()) throw StateError('Hub owner authorization changed');
    final json = _decodePairingResponse(response);
    if (json['hub_id'] != ownership.localHubId ||
        json['client_id'] != clientId ||
        json['ownership_epoch'] != ownership.ownershipEpoch ||
        json['token_type'] != 'Bearer' ||
        json['token'] is! String ||
        (json['token'] as String).isEmpty) {
      throw StateError('Invalid owned Hub pairing response');
    }
    return PairingClaim(
      hubId: ownership.localHubId,
      clientId: clientId,
      token: json['token'] as String,
      ownershipEpoch: ownership.ownershipEpoch,
    );
  }

  static Map<String, dynamic> _decodePairingResponse(
    PairingHttpResponse response,
  ) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const PairingException('The hub returned an invalid response.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PairingException(
        decoded is Map<String, dynamic> && decoded['error'] is Map
            ? (decoded['error'] as Map)['message'] as String? ??
                  'Hub pairing failed.'
            : 'Hub pairing failed.',
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const PairingException('The hub returned an invalid response.');
    }
    return decoded;
  }

  Future<ElectricitySettings> electricitySettings(
    String baseUrl,
    String token,
  ) async {
    final response = await _request(
      baseUrl,
      token,
      '/v1/settings/electricity',
      'GET',
    );
    return ElectricitySettings.fromJson(response as Map<String, dynamic>);
  }

  Future<ElectricitySettings> updateElectricitySettings(
    String baseUrl,
    String token, {
    required String? postalCode,
    required double? rateUsdPerKwh,
  }) async {
    final response = await _request(
      baseUrl,
      token,
      '/v1/settings/electricity',
      'PUT',
      {'postal_code': postalCode, 'rate_usd_per_kwh': rateUsdPerKwh},
    );
    return ElectricitySettings.fromJson(response as Map<String, dynamic>);
  }

  Future<ApplianceUsageProfile> applianceUsageProfile(
    String baseUrl,
    String token,
    int applianceId,
  ) async {
    final response = await _request(
      baseUrl,
      token,
      '/v1/appliances/$applianceId/usage-profile',
      'GET',
    );
    return ApplianceUsageProfile.fromJson(response as Map<String, dynamic>);
  }

  Future<ApplianceUsageProfile> updateApplianceUsageProfile(
    String baseUrl,
    String token,
    int applianceId,
    String usageKind,
    double value,
  ) async {
    final response = await _request(
      baseUrl,
      token,
      '/v1/appliances/$applianceId/usage-profile',
      'PUT',
      {'usage_kind': usageKind, 'value': value},
    );
    return ApplianceUsageProfile.fromJson(response as Map<String, dynamic>);
  }

  Future<List<IdentificationCandidate>> identifyCandidates(
    String baseUrl,
    String token, {
    required String targetKind,
    String? ocrText,
    String? upc,
  }) async {
    final body = <String, dynamic>{'target_kind': targetKind};
    if (ocrText != null) body['ocr_text'] = ocrText;
    if (upc != null) body['upc'] = upc;
    final response = await _post(
      baseUrl,
      token,
      '/v1/identification/candidates',
      body,
    );
    return (response['candidates'] as List<dynamic>)
        .map(
          (item) =>
              IdentificationCandidate.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<DiscoveredPlug>> scan(String baseUrl, String token) async {
    final response = await _post(baseUrl, token, '/v1/discovery/scans', {});
    return (response['candidates'] as List<dynamic>)
        .map((item) => DiscoveredPlug.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<DiscoveredPlug> probe(
    String baseUrl,
    String token,
    String ip, {
    String protocol = 'kasa',
  }) async {
    final response = await _post(baseUrl, token, '/v1/discovery/probes', {
      'ipv4': ip,
      'protocol': protocol,
    });
    return DiscoveredPlug.fromJson(response);
  }

  Future<List<SavedPlug>> saved(String baseUrl, String token) async {
    final response = await _request(baseUrl, token, '/v1/devices', 'GET');
    return (response as List<dynamic>)
        .map((item) => SavedPlug.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<SavedPlug> refreshPlugStatus(
    String baseUrl,
    String token,
    String plugId,
  ) async {
    final response = await _post(
      baseUrl,
      token,
      '/v1/devices/${Uri.encodeComponent(plugId)}/status/refresh',
      {},
    );
    return SavedPlug.fromJson(response);
  }

  Future<DeviceEnergy> deviceEnergy(
    String baseUrl,
    String token,
    String plugId, {
    String period = 'day',
    String? timezone,
    String? postalCode,
    double? rateUsdPerKwh,
  }) async {
    final query = <String, String>{'period': period};
    if (timezone != null) query['timezone'] = timezone;
    if (postalCode != null) query['postal_code'] = postalCode;
    if (rateUsdPerKwh != null) {
      query['rate_usd_per_kwh'] = rateUsdPerKwh.toString();
    }
    final response = await _request(
      baseUrl,
      token,
      '/v1/devices/${Uri.encodeComponent(plugId)}/energy',
      'GET',
      null,
      query,
    );
    return DeviceEnergy.fromJson(response as Map<String, dynamic>);
  }

  Future<DeviceBaselineCoverage> deviceBaselineCoverage(
    String baseUrl,
    String token,
    String deviceId,
  ) async {
    final response = await _request(
      baseUrl,
      token,
      '/v1/devices/${Uri.encodeComponent(deviceId)}/baseline-coverage',
      'GET',
    );
    return DeviceBaselineCoverage.fromJson(response as Map<String, dynamic>);
  }

  Future<AppliancePerUseBaseline> appliancePerUseBaseline(
    String baseUrl,
    String token,
    int applianceId,
  ) async {
    final response = await _request(
      baseUrl,
      token,
      '/v1/appliances/$applianceId/baseline/per-use',
      'GET',
    );
    return AppliancePerUseBaseline.fromJson(response as Map<String, dynamic>);
  }

  Future<SavedPlug> adopt(
    String baseUrl,
    String token,
    DiscoveredPlug plug,
    String name,
    String room,
    bool acknowledgeNoMeter,
  ) async {
    final response = await _post(baseUrl, token, '/v1/devices', {
      'candidate_id': plug.id,
      'ipv4': plug.ip,
      'name': name,
      'room': room,
      'acknowledge_no_meter': acknowledgeNoMeter,
      'protocol': plug.localProtocol,
    });
    return SavedPlug.fromJson(response);
  }

  Future<SavedPlug> attachAppliance(
    String baseUrl,
    String token,
    String plugId,
    int applianceId,
  ) async {
    final response = await _request(
      baseUrl,
      token,
      '/v1/devices/${Uri.encodeComponent(plugId)}/appliance',
      'PUT',
      {'appliance_id': applianceId},
    );
    return SavedPlug.fromJson(response as Map<String, dynamic>);
  }

  Future<List<AttachmentHistoryEntry>> attachmentHistory(
    String baseUrl,
    String token,
    String plugId,
  ) async {
    final response = await _request(
      baseUrl,
      token,
      '/v1/devices/${Uri.encodeComponent(plugId)}/appliance/history',
      'GET',
    );
    return (response as List<dynamic>)
        .map(
          (item) =>
              AttachmentHistoryEntry.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Future<List<SavedAppliance>> appliances(String baseUrl, String token) async {
    final response = await _request(baseUrl, token, '/v1/appliances', 'GET');
    return (response as List<dynamic>)
        .map((item) => SavedAppliance.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<SavedAppliance> addAppliance(
    String baseUrl,
    String token,
    ApplianceInput input,
  ) async {
    final response = await _post(
      baseUrl,
      token,
      '/v1/appliances',
      input.toJson(),
    );
    return SavedAppliance.fromJson(response);
  }

  Future<EnergyLookup> checkModel(
    String baseUrl,
    String token, {
    required String category,
    required String manufacturer,
    required String model,
  }) async {
    final response = await _post(baseUrl, token, '/v1/appliances/model-check', {
      'category': category,
      'manufacturer': manufacturer,
      'model': model,
    });
    return EnergyLookup.fromJson(response);
  }

  Future<void> deleteManualAppliance(
    String baseUrl,
    String token,
    int applianceId,
  ) async {
    await _request(baseUrl, token, '/v1/appliances/$applianceId', 'DELETE');
  }

  Future<SavedAppliance> updateApplianceHours(
    String baseUrl,
    String token,
    int applianceId,
    double hoursPerWeek,
  ) async {
    final response = await _request(
      baseUrl,
      token,
      '/v1/appliances/$applianceId/hours',
      'PATCH',
      {'hours_per_week': hoursPerWeek},
    );
    return SavedAppliance.fromJson(response as Map<String, dynamic>);
  }

  Future<EnergyLookup> lookupEnergy(
    String baseUrl,
    String token,
    int applianceId,
  ) async {
    final response = await _post(
      baseUrl,
      token,
      '/v1/appliances/$applianceId/energy-lookup',
      {},
    );
    return EnergyLookup.fromJson(response);
  }

  Future<EnergyEstimate> estimate(
    String baseUrl,
    String token,
    int applianceId, {
    double? rateUsdPerKwh,
    String? postalCode,
  }) async {
    final response = await _request(
      baseUrl,
      token,
      '/v1/appliances/$applianceId/estimate',
      'GET',
      null,
      {
        if (rateUsdPerKwh != null) 'rate_usd_per_kwh': rateUsdPerKwh.toString(),
        if (postalCode != null && postalCode.isNotEmpty)
          'postal_code': postalCode,
      },
    );
    return EnergyEstimate.fromJson(response as Map<String, dynamic>);
  }

  Future<ApplianceSpec> applianceSpec(
    String baseUrl,
    String token,
    int applianceId,
  ) async {
    final response = await _request(
      baseUrl,
      token,
      '/v1/appliances/$applianceId/spec',
      'GET',
    );
    return ApplianceSpec.fromJson(response as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> _post(
    String baseUrl,
    String token,
    String path,
    Map<String, dynamic> body,
  ) async {
    return (await _request(baseUrl, token, path, 'POST', body))
        as Map<String, dynamic>;
  }

  Future<dynamic> _request(
    String baseUrl,
    String token,
    String path,
    String method, [
    Map<String, dynamic>? body,
    Map<String, String>? query,
  ]) async {
    final owner = ownerAuthorization;
    final sessionGeneration = owner?.session.generation;
    final ownerToken = owner == null ? null : await owner.session.accessToken();
    if (owner != null &&
        (ownerToken == null ||
            owner.session.generation != sessionGeneration ||
            !owner.isCurrent())) {
      throw StateError('Hub owner authorization is no longer current');
    }
    final endpoint = HubEndpoint.parse(baseUrl);
    // An empty trust store makes the pin callback run even for CA-trusted
    // certificates. Without a pin, HttpClient uses platform CA validation.
    final client = HttpClient(
      context: endpoint.pin == null
          ? null
          : SecurityContext(withTrustedRoots: false),
    )..connectionTimeout = const Duration(seconds: 4);
    if (endpoint.pin case final pin?) {
      client.badCertificateCallback = (certificate, host, port) {
        final now = DateTime.now();
        return host == endpoint.uri.host &&
            port == endpoint.uri.port &&
            !now.isBefore(certificate.startValidity) &&
            !now.isAfter(certificate.endValidity) &&
            matchesHubCertificatePin(certificate.der, pin);
      };
    }
    try {
      final request = await client
          .openUrl(
            method,
            endpoint.uri.replace(path: path, queryParameters: query),
          )
          .timeout(const Duration(seconds: 5));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (owner != null) {
        if (owner.session.generation != sessionGeneration ||
            !owner.isCurrent()) {
          throw StateError('Hub owner authorization changed');
        }
        request.headers.set(
          'X-EnergyLens-Owner-Authorization',
          'Bearer $ownerToken',
        );
        request.headers.set('X-EnergyLens-Home-ID', owner.homeId);
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final text = await utf8.decoder.bind(response).join();
      if (owner != null &&
          (owner.session.generation != sessionGeneration ||
              !owner.isCurrent())) {
        throw StateError('Hub owner authorization changed');
      }
      if (response.statusCode == 404 && path.startsWith('/v2/')) {
        throw const _V2UnavailableException();
      }
      final decoded = jsonDecode(text);
      if (response.statusCode != 200 &&
          response.statusCode != 202 &&
          response.statusCode != 201) {
        final error = decoded is Map<String, dynamic>
            ? decoded['error'] as Map<String, dynamic>?
            : null;
        throw HubRequestException(
          response.statusCode,
          error?['code'] as String?,
          error?['message'] as String? ?? 'Hub request failed',
        );
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }
}

class HubOwnerAuthorization {
  const HubOwnerAuthorization({
    required this.session,
    required this.homeId,
    required this.isCurrent,
  });
  final CloudSession session;
  final String homeId;
  final bool Function() isCurrent;
}

class _V2UnavailableException implements Exception {
  const _V2UnavailableException();
}

class StoredHubIdentity {
  const StoredHubIdentity({required this.address, required this.hubId});
  final String address;
  final String hubId;
}

class HubEndpoint {
  const HubEndpoint(this.uri, this.pin);

  final Uri uri;
  final String? pin;

  static HubEndpoint parse(String address) {
    final base = Uri.tryParse(address);
    final ip = base == null ? null : InternetAddress.tryParse(base.host);
    final fragment = base?.fragment;
    final pin =
        fragment != null &&
            fragment.isNotEmpty &&
            RegExp(r'^sha256=[0-9a-f]{64}$').hasMatch(fragment)
        ? fragment.substring(7)
        : null;
    if (base == null ||
        base.scheme != 'https' ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        (base.path.isNotEmpty && base.path != '/') ||
        (base.hasFragment && pin == null) ||
        ip == null ||
        ip.type != InternetAddressType.IPv4 ||
        !_isPrivateIpv4(base.host)) {
      throw const FormatException(
        'Enter a hub HTTPS address on your LAN or Tailscale network, such as https://100.115.133.73:18787#sha256=<64 lowercase hex digits>',
      );
    }
    return HubEndpoint(base.removeFragment(), pin);
  }
}

bool matchesHubCertificatePin(List<int> certificateDer, String pin) =>
    sha256.convert(certificateDer).toString() == pin;

bool _isPrivateIpv4(String value) {
  final parts = value.split('.').map(int.tryParse).toList();
  if (parts.length != 4 ||
      parts.any((part) => part == null || part < 0 || part > 255)) {
    return false;
  }
  return value == '127.0.0.1' ||
      parts[0] == 10 ||
      (parts[0] == 100 && parts[1]! >= 64 && parts[1]! <= 127) ||
      (parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31) ||
      (parts[0] == 192 && parts[1] == 168);
}
