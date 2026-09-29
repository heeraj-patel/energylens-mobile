import 'dart:convert';
import 'dart:io';

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

class SavedPlug {
  const SavedPlug({
    required this.id,
    required this.ip,
    required this.model,
    required this.name,
    required this.room,
    required this.meterStatus,
    required this.lastVerifiedAt,
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
  final SavedAppliance? connectedAppliance;
  final String? mac;
  final String? localProtocol;
  final int? httpPort;
}

class DeviceEnergy {
  const DeviceEnergy({
    required this.status,
    required this.period,
    required this.totalKwh,
    required this.coverageFraction,
    required this.coveredSecs,
    this.latestWatts,
    this.observedCostUsd,
    this.rateSourceLabel,
  });

  factory DeviceEnergy.fromJson(Map<String, dynamic> json) => DeviceEnergy(
    status: json['status'] as String,
    period: json['period'] as String,
    totalKwh: (json['total_kwh'] as num).toDouble(),
    coverageFraction: (json['coverage_fraction'] as num).toDouble(),
    coveredSecs: (json['covered_secs'] as num).toDouble(),
    latestWatts: (json['latest_watts'] as num?)?.toDouble(),
    observedCostUsd: (json['observed_cost_usd'] as num?)?.toDouble(),
    rateSourceLabel: json['rate_source_label'] as String?,
  );

  final String status;
  final String period;
  final double totalKwh;
  final double coverageFraction;
  final double coveredSecs;
  final double? latestWatts;
  final double? observedCostUsd;
  final String? rateSourceLabel;
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
  final double? standbyWatts;
  final String usageBasis;
  final int retrievedAt;
}

String energySourceLabel(EnergyEvidence source) => switch (source.sourceKind) {
  'energy_star' => 'Estimated · ENERGY STAR data (EPA)',
  'energy_star_archive' => 'Estimated · Historical ENERGY STAR data (EPA)',
  'oem' => 'Estimated · Manufacturer data',
  'oem_family' => 'Estimated · Manufacturer family test data',
  'user_label' => 'Estimated · Bulb ratings you entered',
  _ => 'Estimated · Source details',
};

String energySourceHeading(EnergyEvidence source) =>
    switch (source.sourceKind) {
      'energy_star' => 'ENERGY STAR data (EPA)',
      'energy_star_archive' => 'Historical ENERGY STAR data (EPA)',
      'oem' => 'Manufacturer data',
      'oem_family' => 'Manufacturer family test data',
      'user_label' => 'Bulb ratings you entered',
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

class EnergyEstimate {
  const EnergyEstimate({
    required this.status,
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
  });
  factory EnergyEstimate.fromJson(Map<String, dynamic> json) => EnergyEstimate(
    status: json['status'] as String,
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
  );
  final String status;
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
}

String energyRateDescription(EnergyEstimate estimate) {
  if (estimate.rateUsdPerKwh case final rate?) {
    final label = estimate.rateSourceLabel ?? 'Electricity rate';
    final asOf = estimate.rateAsOf == null ? '' : ' · ${estimate.rateAsOf}';
    return '$label: \$${rate.toStringAsFixed(4)}/kWh$asOf';
  }
  if (estimate.rateStatus == 'unavailable') {
    return 'Regional rate unavailable. Enter your bill rate for a cost estimate.';
  }
  return 'Add a ZIP code or your bill rate to see estimated cost.';
}

class DiscoveryApi {
  const DiscoveryApi();

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

  Future<DiscoveredPlug> probe(String baseUrl, String token, String ip) async {
    final response = await _post(baseUrl, token, '/v1/discovery/probes', {
      'ipv4': ip,
    });
    return DiscoveredPlug.fromJson(response);
  }

  Future<List<SavedPlug>> saved(String baseUrl, String token) async {
    final response = await _request(baseUrl, token, '/v1/devices', 'GET');
    return (response as List<dynamic>)
        .map((item) => SavedPlug.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<DeviceEnergy> deviceEnergy(
    String baseUrl,
    String token,
    String plugId, {
    String period = 'day',
    String? postalCode,
    double? rateUsdPerKwh,
  }) async {
    final query = <String, String>{'period': period};
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
    final base = Uri.tryParse(baseUrl);
    final ip = base == null ? null : InternetAddress.tryParse(base.host);
    if (base == null ||
        base.scheme != 'http' ||
        base.userInfo.isNotEmpty ||
        ip == null ||
        ip.type != InternetAddressType.IPv4 ||
        !_isPrivateIpv4(base.host)) {
      throw const FormatException(
        'Enter the hub’s LAN or Tailscale HTTP address, such as http://100.115.133.73:18787',
      );
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client
          .openUrl(method, base.replace(path: path, queryParameters: query))
          .timeout(const Duration(seconds: 5));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final text = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(text);
      if (response.statusCode != 200) {
        final error = decoded is Map<String, dynamic>
            ? decoded['error'] as Map<String, dynamic>?
            : null;
        throw StateError(error?['message'] as String? ?? 'Hub request failed');
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }
}

bool _isPrivateIpv4(String value) {
  final parts = value.split('.').map(int.tryParse).toList();
  if (parts.length != 4 ||
      parts.any((part) => part == null || part < 0 || part > 255)) {
    return false;
  }
  return parts[0] == 10 ||
      (parts[0] == 100 && parts[1]! >= 64 && parts[1]! <= 127) ||
      (parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31) ||
      (parts[0] == 192 && parts[1] == 168);
}
