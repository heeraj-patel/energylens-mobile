import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../backend_error.dart';
import '../cloud_auth/cloud_auth.dart';
import '../cloud_auth/cloud_local_auth.dart';
import '../cloud_auth/cloud_dev_tls.dart';
import 'cloud_home.dart';
import 'cloud_appliance.dart';
import 'cloud_appliance_list.dart';
import 'cloud_appliance_detail.dart';
import 'cloud_catalog.dart';
import 'cloud_estimate.dart';
import 'cloud_hub_claim.dart';
import 'cloud_preferences.dart';
import 'cloud_question.dart';
import 'cloud_metered_history.dart';
import 'cloud_metered_summary.dart';
import 'cloud_kasa_runtime.dart';
import 'cloud_faq.dart';
import 'cloud_recommendations.dart';
import 'cloud_interventions.dart';
import 'cloud_appliance_facts.dart';
import 'cloud_programs.dart';
import 'cloud_report_preview.dart';
import 'cloud_report_delivery.dart';
import 'cloud_tariff.dart';
import 'cloud_cycle_comparison.dart';
import 'cloud_sensor.dart';
import 'cloud_household_energy.dart';
import 'cloud_top_savings_move.dart';
import 'cloud_regional_rate.dart';
import 'cloud_usage_facts.dart';
import 'cloud_device_states.dart';
import 'cloud_energy_categories.dart';
import 'cloud_energy_resolution.dart';

class CloudApiException implements Exception {
  const CloudApiException(
    this.statusCode,
    this.code, {
    this.details = const {},
    this.path,
  });
  final int statusCode;
  final String code;
  final Map<String, dynamic> details;
  final String? path;

  /// Seconds to wait after a 429 `refresh_rate_limited`; null otherwise.
  int? get retryAfterSeconds {
    final value = details['retry_after_seconds'];
    return statusCode == 429 && value is int && value >= 0 ? value : null;
  }

  @override
  String toString() => 'Cloud API error $statusCode ($code)';
}

class CloudRequestFailureContext {
  const CloudRequestFailureContext(this.type, this.statusCode, this.path);
  final String type;
  final int? statusCode;
  final String path;
}

final Expando<CloudRequestFailureContext> _requestFailureContexts =
    Expando<CloudRequestFailureContext>();
final Expando<String> _responsePaths = Expando<String>();

CloudRequestFailureContext? cloudRequestFailureContext(Object error) {
  if (error is CloudApiException) {
    return CloudRequestFailureContext(
      'CloudApiException',
      error.statusCode,
      error.path == null
          ? 'unavailable'
          : Uri.tryParse(error.path!)?.path ?? 'unavailable',
    );
  }
  return _requestFailureContexts[error];
}

class CloudResponseFormatException extends FormatException {
  CloudResponseFormatException();
}

class CloudAccount {
  const CloudAccount({
    required this.id,
    required this.email,
    required this.emailVerified,
    this.authMethod,
    this.username,
    this.displayName,
    this.profileVersion,
  });
  final String id;
  final String? email;
  final bool emailVerified;
  final String? authMethod;
  final String? username;
  final String? displayName;
  final int? profileVersion;

  factory CloudAccount.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final verified = json['email_verified'];
    if (id is! String || id.isEmpty || verified is! bool) {
      throw const FormatException('Invalid account response');
    }
    return CloudAccount(
      id: id,
      email: json['email'] as String?,
      emailVerified: verified,
      authMethod: json['auth_method'] as String?,
      username: json['username'] as String?,
      displayName: json['display_name'] as String?,
      profileVersion: json['profile_version'] as int?,
    );
  }
}

class _FactsCacheEntry {
  const _FactsCacheEntry(this.etag, this.facts, this.generation);
  final String etag;
  final CloudApplianceFacts facts;
  final int generation;
}

/// Cloud bearer requests never read or send hub pairing credentials.
class CloudApiClient {
  CloudApiClient({required this.session, http.Client? client})
    : _client = client ?? cloudHttpClient(session.config);
  final CloudSession session;
  final http.Client _client;

  T _parseResponse<T>(http.Response response, T Function() parse) {
    final path = _responsePaths[response] ?? 'unavailable';
    try {
      return parse();
    } on FormatException catch (error) {
      final contextual = CloudResponseFormatException();
      _requestFailureContexts[contextual] = CloudRequestFailureContext(
        error.runtimeType == FormatException
            ? 'FormatException'
            : error.runtimeType.toString(),
        response.statusCode,
        path,
      );
      throw contextual;
    } catch (error) {
      _requestFailureContexts[error] = CloudRequestFailureContext(
        error.runtimeType.toString(),
        response.statusCode,
        path,
      );
      rethrow;
    }
  }

  /// Called once when Cloud rejects the current session (401/403) or a signed-in
  /// request has no usable token. The session owner signs the user out.
  void Function()? onSessionRejected;

  void _rejectSession(int generation) {
    if (generation == session.generation) onSessionRejected?.call();
  }

  Future<CloudEnergyResolution?> energyResolution(
    String homeId,
    String applianceId,
  ) async {
    try {
      final response = await get(
        '/v1/homes/${Uri.encodeComponent(homeId)}/appliances/${Uri.encodeComponent(applianceId)}/energy-resolution',
      );
      return CloudEnergyResolution.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on CloudApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Queues an owner re-resolve. A 429 surfaces as [CloudApiException]
  /// (`refresh_rate_limited`, [CloudApiException.retryAfterSeconds]).
  Future<CloudEnergyResolutionRefresh> refreshEnergyResolution(
    String homeId,
    String applianceId, {
    required String idempotencyKey,
  }) async {
    _validateIdempotencyKey(idempotencyKey);
    final response = await _request(
      'POST',
      '/v1/homes/${Uri.encodeComponent(homeId)}/appliances/${Uri.encodeComponent(applianceId)}/energy-resolution/refresh',
      idempotencyKey: idempotencyKey,
    );
    if (response.statusCode != 202) {
      throw const FormatException('Unexpected energy refresh response');
    }
    final refresh = CloudEnergyResolutionRefresh.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    if (refresh.applianceId.toLowerCase() != applianceId.toLowerCase()) {
      throw const FormatException('Energy refresh appliance changed');
    }
    return refresh;
  }

  Future<EnergyCategories?> energyCategories({String? etag}) async {
    final response = await _request(
      'GET',
      '/v1/energy-categories',
      ifNoneMatch: etag,
    );
    if (response.statusCode == 304) return null;
    final responseEtag = _caseInsensitiveHeader(response.headers, 'etag');
    if (responseEtag == null) {
      throw const FormatException('Missing energy categories ETag');
    }
    return EnergyCategories.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      responseEtag,
    );
  }

  Future<CloudAuthCapabilities?> authCapabilities() async {
    final origin = Uri.parse(session.config.apiUrl);
    final response = await _client
        .get(
          origin.resolve('/v1/auth/config'),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw CloudApiException(response.statusCode, 'auth_config_unavailable');
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw const FormatException('Invalid Cloud auth capabilities');
    }
    return CloudAuthCapabilities.fromJson(body, session.config);
  }

  /// A home that is missing or answers for a different ID cannot be verified
  /// for this user, so the session is rejected like a 401/403.
  Future<CloudVersioned<CloudHome>> home(String homeId) async {
    final generation = session.generation;
    final http.Response response;
    try {
      response = await get('/v1/homes/${Uri.encodeComponent(homeId)}');
    } on CloudApiException catch (error) {
      if (error.statusCode == 404) _rejectSession(generation);
      rethrow;
    }
    final value = CloudHome.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    if (value.id != homeId) {
      _rejectSession(generation);
      throw const FormatException('Cloud home ID changed');
    }
    return CloudVersioned(value: value, etag: _requiredEtag(response));
  }

  Future<CloudHouseholdDashboard> householdDashboard(String homeId) async {
    _validateHouseholdHomeId(homeId);
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/dashboard',
    );
    return _parseResponse(
      response,
      () => CloudHouseholdDashboard.fromJson(
        _decodeObject(response.body),
        expectedHomeId: homeId,
      ),
    );
  }

  Future<CloudTopSavingsMove> topSavingsMove(String homeId) async {
    _validateHouseholdHomeId(homeId);
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/top-savings-move',
    );
    return _parseResponse(
      response,
      () => CloudTopSavingsMove.fromJson(
        _decodeObject(response.body),
        expectedHomeId: homeId,
      ),
    );
  }

  Future<CloudHouseholdEnergyTrends> householdEnergyTrends(
    String homeId, {
    required String granularity,
    String? window,
  }) async {
    _validateHouseholdHomeId(homeId);
    if (!const {'hour', 'day', 'week', 'month'}.contains(granularity)) {
      throw ArgumentError.value(granularity, 'granularity');
    }
    if (window != null &&
        !((window == 'month_to_date' && granularity == 'day') ||
            (window == 'trailing_30_days' && granularity == 'day') ||
            (window == 'last_5_occurrences' &&
                const {'day', 'week', 'month'}.contains(granularity)))) {
      throw ArgumentError.value(window, 'window');
    }
    final query = Uri(
      queryParameters: window == null
          ? {'granularity': granularity}
          : {'granularity': granularity, 'window': window},
    ).query;
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/energy-trends?$query',
    );
    final value = _parseResponse(
      response,
      () => CloudHouseholdEnergyTrends.fromJson(
        _decodeObject(response.body),
        expectedHomeId: homeId,
      ),
    );
    return _parseResponse(response, () {
      if (value.granularity != granularity) {
        throw const FormatException('Household energy granularity changed');
      }
      return value;
    });
  }

  static final RegExp _householdHomeUuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static void _validateHouseholdHomeId(String homeId) {
    if (!_householdHomeUuid.hasMatch(homeId)) {
      throw ArgumentError.value(homeId, 'homeId');
    }
  }

  static Map<String, dynamic> _decodeObject(String body) {
    final value = jsonDecode(body);
    if (value is Map<String, dynamic>) return value;
    throw const FormatException('Invalid household energy response object');
  }

  static String? _caseInsensitiveHeader(
    Map<String, String> headers,
    String name,
  ) {
    final matches = headers.entries
        .where((entry) => entry.key.toLowerCase() == name)
        .map((entry) => entry.value)
        .toList();
    if (matches.length > 1) {
      throw const FormatException('Duplicate appliance provenance header');
    }
    return matches.isEmpty ? null : matches.single;
  }

  Future<CloudVersioned<CloudHome>> updateHome(
    String homeId,
    CloudHomePatch input, {
    required String ifMatch,
    required String idempotencyKey,
  }) async {
    _validateMutationHeaders(ifMatch, idempotencyKey);
    final response = await _request(
      'PATCH',
      '/v1/homes/${Uri.encodeComponent(homeId)}',
      jsonBody: jsonEncode(input.toJson()),
      ifMatch: ifMatch,
      idempotencyKey: idempotencyKey,
    );
    final value = CloudHome.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    if (value.id != homeId) {
      throw const FormatException('Cloud home ID changed');
    }
    return CloudVersioned(value: value, etag: _requiredEtag(response));
  }

  Future<CloudVersioned<CloudAppliance>> appliance(
    String homeId,
    String applianceId,
  ) async {
    final detail = await applianceDetail(homeId, applianceId);
    return CloudVersioned(value: detail.appliance, etag: detail.etag);
  }

  /// Reads one appliance while retaining its response validator and source.
  /// Missing provenance headers are the legacy household response contract.
  Future<CloudApplianceDetail> applianceDetail(
    String homeId,
    String applianceId,
  ) async {
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/appliances/${Uri.encodeComponent(applianceId)}',
    );
    final value = CloudAppliance.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    if (value.id != applianceId || value.homeId != homeId) {
      throw const FormatException('Cloud appliance ownership changed');
    }
    final modeHeader = _caseInsensitiveHeader(
      response.headers,
      'x-energylens-data-mode',
    );
    final revisionHeader = _caseInsensitiveHeader(
      response.headers,
      'x-energylens-fixture-revision',
    );
    final CloudApplianceDataMode dataMode;
    final String? fixtureRevision;
    if (modeHeader == null && revisionHeader == null) {
      dataMode = CloudApplianceDataMode.household;
      fixtureRevision = null;
    } else if (modeHeader == 'household' && revisionHeader == null) {
      dataMode = CloudApplianceDataMode.household;
      fixtureRevision = null;
    } else if (modeHeader == 'sample' &&
        revisionHeader != null &&
        RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$')
            .hasMatch(revisionHeader)) {
      dataMode = CloudApplianceDataMode.sample;
      fixtureRevision = revisionHeader;
    } else if (modeHeader == 'mixed' &&
        revisionHeader != null &&
        RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$')
            .hasMatch(revisionHeader)) {
      dataMode = CloudApplianceDataMode.mixed;
      fixtureRevision = revisionHeader;
    } else {
      throw const FormatException('Invalid cloud appliance provenance');
    }
    return CloudApplianceDetail(
      appliance: value,
      etag: _requiredEtag(response),
      dataMode: dataMode,
      fixtureRevision: fixtureRevision,
    );
  }

  Future<CloudVersioned<CloudAppliance>> updateAppliance(
    String homeId,
    String applianceId,
    CloudAppliancePatch input, {
    required String ifMatch,
    required String idempotencyKey,
  }) async {
    _validateMutationHeaders(ifMatch, idempotencyKey);
    final response = await _request(
      'PATCH',
      '/v1/homes/${Uri.encodeComponent(homeId)}/appliances/${Uri.encodeComponent(applianceId)}',
      jsonBody: jsonEncode(input.toJson()),
      ifMatch: ifMatch,
      idempotencyKey: idempotencyKey,
    );
    final value = CloudAppliance.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    if (value.id != applianceId || value.homeId != homeId) {
      throw const FormatException('Cloud appliance ownership changed');
    }
    return CloudVersioned(value: value, etag: _requiredEtag(response));
  }

  /// Archives an active appliance. The backend requires its strong version
  /// ETag and an idempotency key; success has no response body.
  Future<void> archiveAppliance(
    String homeId,
    String applianceId, {
    required String ifMatch,
    required String idempotencyKey,
  }) async {
    _validateMutationHeaders(ifMatch, idempotencyKey);
    if (!RegExp(r'^"[1-9][0-9]*"$').hasMatch(ifMatch)) {
      throw ArgumentError.value(ifMatch, 'ifMatch');
    }
    await _request(
      'DELETE',
      '/v1/homes/${Uri.encodeComponent(homeId)}/appliances/${Uri.encodeComponent(applianceId)}',
      ifMatch: ifMatch,
      idempotencyKey: idempotencyKey,
    );
  }

  /// Reads at most two exact-scope, active reviewed usage facts. This owner
  /// route is bearer authenticated; Hub mTLS routes are intentionally separate.
  Future<CloudReviewedUsageFacts> usageFacts(CloudUsageFactScope scope) async {
    if (!_validScopeField(scope.category, 60) ||
        !_validScopeField(scope.manufacturer, 120) ||
        !_validScopeField(scope.model, 120) ||
        !_validScopeField(scope.variant, 100) ||
        (scope.fuel != 'electricity' &&
            !(scope.fuel == 'natural_gas' && scope.category == 'dryer'))) {
      throw ArgumentError.value(scope, 'scope');
    }
    final query = Uri(queryParameters: scope.toQueryParameters()).query;
    final response = await get('/v1/usage-facts?$query');
    return _parseResponse(response, () {
      final result = CloudReviewedUsageFacts.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      if (result.scope.category != scope.category ||
          result.scope.manufacturer != scope.manufacturer ||
          result.scope.model != scope.model ||
          result.scope.fuel != scope.fuel ||
          result.scope.variant != scope.variant) {
        throw const FormatException('Reviewed usage fact scope changed');
      }
      return result;
    });
  }

  static bool _validScopeField(String value, int maxLength) =>
      value.isNotEmpty &&
      value.length <= maxLength &&
      value.trim() == value &&
      !value.codeUnits.any((unit) => unit < 32 || unit == 127);

  Future<List<CloudSensor>> sensors(String homeId) async {
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/sensors',
    );
    final rows = (jsonDecode(response.body) as Map<String, dynamic>)['sensors'];
    if (rows is! List) throw const FormatException('Invalid cloud sensor list');
    return rows
        .map((row) => CloudSensor.fromJson(row as Map<String, dynamic>, homeId))
        .toList();
  }

  Future<CloudSensor> createSensor(
    String homeId,
    CloudSensorCreate input, {
    required String idempotencyKey,
  }) async {
    _validateIdempotencyKey(idempotencyKey);
    final response = await _request(
      'POST',
      '/v1/homes/${Uri.encodeComponent(homeId)}/sensors',
      jsonBody: jsonEncode(input.toJson()),
      idempotencyKey: idempotencyKey,
    );
    return CloudSensor.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      homeId,
    );
  }

  Future<CloudAttachment> createAttachment(
    String homeId,
    CloudAttachmentCreate input, {
    required String ifMatch,
    required String idempotencyKey,
  }) async {
    _validateMutationHeaders(ifMatch, idempotencyKey);
    final response = await _request(
      'POST',
      '/v1/homes/${Uri.encodeComponent(homeId)}/attachments',
      jsonBody: jsonEncode(input.toJson()),
      ifMatch: ifMatch,
      idempotencyKey: idempotencyKey,
    );
    final value = CloudAttachment.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      homeId,
    );
    if (value.sensorId != input.sensorId ||
        value.applianceId != input.applianceId) {
      throw const FormatException('Attachment target changed');
    }
    return value;
  }

  Future<CloudAttachment> closeAttachment(
    String homeId,
    String attachmentId,
    CloudAttachmentClose input, {
    required String ifMatch,
    required String idempotencyKey,
  }) async {
    _validateMutationHeaders(ifMatch, idempotencyKey);
    final response = await _request(
      'PATCH',
      '/v1/homes/${Uri.encodeComponent(homeId)}/attachments/${Uri.encodeComponent(attachmentId)}',
      jsonBody: jsonEncode(input.toJson()),
      ifMatch: ifMatch,
      idempotencyKey: idempotencyKey,
    );
    final value = CloudAttachment.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      homeId,
    );
    if (value.id != attachmentId || value.endedAt == null) {
      throw const FormatException('Attachment was not closed');
    }
    return value;
  }

  Future<CloudReportPreview> createReportPreview(
    String homeId,
    List<String> applianceIds,
    Set<String> ownedApplianceIds, {
    required String idempotencyKey,
  }) async {
    if (applianceIds.isEmpty ||
        applianceIds.length > 25 ||
        applianceIds.map((id) => id.toLowerCase()).toSet().length !=
            applianceIds.length ||
        applianceIds.any(
          (id) => !ownedApplianceIds.contains(id.toLowerCase()),
        ) ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(idempotencyKey)) {
      throw ArgumentError('Invalid report selection or idempotency key');
    }
    final response = await _request(
      'POST',
      '/v1/homes/${Uri.encodeComponent(homeId)}/reports/preview',
      jsonBody: jsonEncode({'appliance_ids': applianceIds}),
      idempotencyKey: idempotencyKey,
    );
    final preview = CloudReportPreview.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      homeId,
      ownedApplianceIds,
    );
    if (preview.items.length != applianceIds.length ||
        preview.items.any(
          (item) => !applianceIds.any(
            (id) => id.toLowerCase() == item.applianceId.toLowerCase(),
          ),
        )) {
      throw const FormatException('Report selection changed');
    }
    return preview;
  }

  Future<CloudReportPreview> reportPreview(
    String homeId,
    String previewId,
    Set<String> ownedApplianceIds,
  ) async {
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/reports/previews/${Uri.encodeComponent(previewId)}',
    );
    final preview = CloudReportPreview.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      homeId,
      ownedApplianceIds,
    );
    if (preview.id != previewId) {
      throw const FormatException('Report preview ID changed');
    }
    return preview;
  }

  Future<Uint8List> reportPDF(
    String homeId,
    String previewId,
    String snapshotSha256,
  ) async {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshotSha256)) {
      throw ArgumentError.value(snapshotSha256, 'snapshotSha256');
    }
    final response = await _request(
      'GET',
      '/v1/homes/${Uri.encodeComponent(homeId)}/reports/previews/${Uri.encodeComponent(previewId)}/pdf',
      reportSnapshotSha256: snapshotSha256,
    );
    final contentType = _caseInsensitiveHeader(
      response.headers,
      'content-type',
    );
    final bytes = response.bodyBytes;
    if (contentType?.split(';').first.trim() != 'application/pdf' ||
        bytes.length < 5 ||
        bytes.length > 8 * 1024 * 1024 ||
        bytes[0] != 0x25 ||
        bytes[1] != 0x50 ||
        bytes[2] != 0x44 ||
        bytes[3] != 0x46 ||
        bytes[4] != 0x2d) {
      throw const FormatException('Invalid report PDF response');
    }
    return bytes;
  }

  Future<CloudReportDelivery> queueReportDelivery(
    String homeId,
    String previewId,
    String approvedSnapshotSha256,
    List<String> recipients, {
    required String idempotencyKey,
    bool sendNow = false,
  }) async {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(approvedSnapshotSha256) ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(idempotencyKey) ||
        validatedReportRecipients(recipients.join(',')) == null) {
      throw ArgumentError('Invalid report delivery request');
    }
    final response = await _request(
      'POST',
      '/v1/homes/${Uri.encodeComponent(homeId)}/reports/previews/${Uri.encodeComponent(previewId)}/deliveries',
      jsonBody: jsonEncode({
        'approved_snapshot_sha256': approvedSnapshotSha256,
        'recipients': recipients,
        'approved': true,
        if (sendNow) 'send_now': true,
      }),
      idempotencyKey: idempotencyKey,
    );
    final delivery = CloudReportDelivery.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      previewId,
    );
    if (delivery.recipients.join(',') != recipients.join(',')) {
      throw const FormatException('Report delivery recipients changed');
    }
    return delivery;
  }

  Future<CloudAccount> me() async {
    final response = await get('/v1/me');
    return _parseResponse(
      response,
      () => CloudAccount.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      ),
    );
  }

  Future<CloudVersioned<CloudAccount>> accountProfile() async {
    final response = await get('/v1/me');
    final account = CloudAccount.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    return CloudVersioned(value: account, etag: _requiredEtag(response));
  }

  Future<CloudVersioned<CloudAccount>> updateAccountOwner(
    String name, {
    required String ifMatch,
    required String idempotencyKey,
  }) async {
    _validateMutationHeaders(ifMatch, idempotencyKey);
    final response = await _request(
      'PATCH',
      '/v1/me/profile',
      jsonBody: jsonEncode({'display_name': name}),
      ifMatch: ifMatch,
      idempotencyKey: idempotencyKey,
    );
    return CloudVersioned(
      value: CloudAccount.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      ),
      etag: _requiredEtag(response),
    );
  }

  Future<CloudVersioned<CloudAccount>> changeLocalEmail(
    String email,
    String currentPassword, {
    required String ifMatch,
    required String idempotencyKey,
  }) async {
    _validateMutationHeaders(ifMatch, idempotencyKey);
    final response = await _request(
      'POST',
      '/v1/auth/local/change-email',
      jsonBody: jsonEncode({
        'new_email': email,
        'current_password': currentPassword,
      }),
      ifMatch: ifMatch,
      idempotencyKey: idempotencyKey,
    );
    return CloudVersioned(
      value: CloudAccount.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      ),
      etag: _requiredEtag(response),
    );
  }

  Future<void> changeLocalPassword(
    String currentPassword,
    String newPassword,
  ) async {
    await _request(
      'POST',
      '/v1/auth/local/change-password',
      jsonBody: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    );
  }

  Future<List<CloudHome>> homes() async {
    final response = await get('/v1/homes');
    return _parseResponse(response, () {
      final value = jsonDecode(response.body) as Map<String, dynamic>;
      final items = value['homes'];
      if (items is! List) {
        throw const FormatException('Invalid cloud home list');
      }
      return items
          .map((item) => CloudHome.fromJson(item as Map<String, dynamic>))
          .toList();
    });
  }

  Future<List<CloudAppliance>> appliances(String homeId) async {
    return (await applianceList(homeId)).appliances;
  }

  Future<CloudApplianceList> applianceList(String homeId) async {
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/appliances',
    );
    return _parseResponse(response, () {
      final body = _decodeObject(response.body);
      final modeHeader = _caseInsensitiveHeader(
        response.headers,
        'x-energylens-data-mode',
      );
      final revisionHeader = _caseInsensitiveHeader(
        response.headers,
        'x-energylens-fixture-revision',
      );
      final inventoryRevision = _caseInsensitiveHeader(
        response.headers,
        'x-energylens-inventory-revision',
      );
      if (inventoryRevision != null &&
          !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$')
              .hasMatch(inventoryRevision)) {
        throw const FormatException('Invalid cloud inventory revision');
      }
      final CloudApplianceDataMode dataMode;
      final String? fixtureRevision;
      if (modeHeader == null && revisionHeader == null) {
        dataMode = CloudApplianceDataMode.household;
        fixtureRevision = null;
      } else if (modeHeader == 'household' && revisionHeader == null) {
        dataMode = CloudApplianceDataMode.household;
        fixtureRevision = null;
      } else if (modeHeader == 'sample' &&
          revisionHeader != null &&
          RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$')
              .hasMatch(revisionHeader)) {
        dataMode = CloudApplianceDataMode.sample;
        fixtureRevision = revisionHeader;
      } else if (modeHeader == 'mixed' &&
          revisionHeader != null &&
          RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$')
              .hasMatch(revisionHeader)) {
        dataMode = CloudApplianceDataMode.mixed;
        fixtureRevision = revisionHeader;
      } else {
        throw const FormatException('Invalid cloud appliance provenance');
      }
      final rows = body['appliances'];
      if (rows is! List || rows.any((row) => row is! Map<String, dynamic>)) {
        throw const FormatException('Invalid cloud appliance list');
      }
      final appliances = rows
          .map((row) => CloudAppliance.fromJson(row as Map<String, dynamic>))
          .toList();
      if (appliances.any((item) => item.homeId != homeId)) {
        throw const FormatException('Cloud appliance belongs to another home');
      }
      return CloudApplianceList(
        appliances: List.unmodifiable(appliances),
        dataMode: dataMode,
        fixtureRevision: fixtureRevision,
        inventoryRevision: inventoryRevision,
      );
    });
  }

  Future<List<CloudTariff>> electricityTariffs(String homeId) =>
      _tariffs(homeId, 'electricity');

  Future<List<CloudTariff>> gasTariffs(String homeId) =>
      _tariffs(homeId, 'natural_gas');

  Future<List<CloudTariff>> _tariffs(String homeId, String fuel) async {
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/tariffs',
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = body['tariffs'];
    if (rows is! List) throw const FormatException('Invalid tariff list');
    if (rows.any((row) => row is! Map<String, dynamic>)) {
      throw const FormatException('Invalid tariff list');
    }
    return rows
        .where((row) => row is Map<String, dynamic> && row['fuel'] == fuel)
        .map(
          (row) => CloudTariff.fromJson(
            row as Map<String, dynamic>,
            homeId,
            fuel: fuel,
          ),
        )
        .toList();
  }

  Future<CloudTariff> createElectricityTariff(
    String homeId,
    Map<String, dynamic> body, {
    required String idempotencyKey,
  }) => _createTariff(
    homeId,
    body,
    fuel: 'electricity',
    idempotencyKey: idempotencyKey,
  );

  Future<CloudTariff> createGasTariff(
    String homeId,
    Map<String, dynamic> body, {
    required String idempotencyKey,
  }) => _createTariff(
    homeId,
    body,
    fuel: 'natural_gas',
    idempotencyKey: idempotencyKey,
  );

  Future<CloudTariff> _createTariff(
    String homeId,
    Map<String, dynamic> body, {
    required String fuel,
    required String idempotencyKey,
  }) async {
    final response = await _request(
      'POST',
      '/v1/homes/${Uri.encodeComponent(homeId)}/tariffs',
      jsonBody: jsonEncode(body),
      idempotencyKey: idempotencyKey,
    );
    return CloudTariff.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      homeId,
      fuel: fuel,
    );
  }

  Future<CloudAppliance> createAppliance(
    String homeId,
    CloudApplianceCreate input, {
    required String idempotencyKey,
  }) async {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(idempotencyKey)) {
      throw ArgumentError.value(idempotencyKey, 'idempotencyKey');
    }
    final response = await _request(
      'POST',
      '/v1/homes/${Uri.encodeComponent(homeId)}/appliances',
      jsonBody: jsonEncode(input.toJson()),
      idempotencyKey: idempotencyKey,
    );
    final appliance = CloudAppliance.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    if (appliance.homeId != homeId) {
      throw const FormatException('Cloud appliance belongs to another home');
    }
    return appliance;
  }

  Future<List<CloudCatalogProduct>> searchCatalogModels({
    String? brand,
    required String model,
    String? fuel,
    String? region,
  }) async {
    final query = <String, dynamic>{'model': model};
    if (brand != null) query['brand'] = brand;
    if (fuel != null) query['fuel'] = fuel;
    if (region != null) query['region'] = region;
    final response = await _request(
      'POST',
      '/v1/catalog/model-search',
      jsonBody: jsonEncode(query),
      idempotencyKey: newCloudIdempotencyKey(),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = body['products'];
    if (rows is! List) {
      throw const FormatException('Invalid reviewed catalog results');
    }
    return rows
        .map((row) => CloudCatalogProduct.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<CloudCatalogProduct> catalogProduct(String productId) async {
    final response = await get(
      '/v1/catalog/products/${Uri.encodeComponent(productId)}',
    );
    return CloudCatalogProduct.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<CloudEstimateBatch> estimates(String homeId) async {
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/estimates',
    );
    return _parseResponse(response, () {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final rows = body['estimates'];
      final asOf = body['as_of'] is String
          ? DateTime.tryParse(body['as_of'] as String)
          : null;
      if (rows is! List || asOf == null) {
        throw const FormatException('Invalid cloud estimate list');
      }
      return CloudEstimateBatch(
        estimates: rows
            .map((row) => CloudEstimate.fromJson(row as Map<String, dynamic>))
            .toList(),
        asOf: asOf,
      );
    });
  }

  Future<CloudDeviceStates> deviceStates(String homeId) async {
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/device-states',
    );
    return CloudDeviceStates.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      homeId,
    );
  }

  Future<CloudMeteredHistoryPage> meteredHistory(
    String homeId, {
    String? cursor,
  }) async {
    final query = Uri(queryParameters: {'limit': '50', 'cursor': ?cursor})
        .query;
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/metered-history?$query',
    );
    return CloudMeteredHistoryPage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<CloudKasaRuntimePage> kasaRuntimeHistory(
    String homeId, {
    String? cursor,
  }) async {
    final query = Uri(queryParameters: {'limit': '50', 'cursor': ?cursor})
        .query;
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/kasa-runtime?$query',
    );
    return CloudKasaRuntimePage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      homeId: homeId,
    );
  }

  Future<CloudFaqAnswer> faqAnswer(
    String homeId,
    String intent, {
    String? applianceId,
  }) async {
    if (!isFaqIntent(intent) ||
        (intent == 'device_operating_cost') != (applianceId != null)) {
      throw ArgumentError('Invalid FAQ intent or appliance');
    }
    final query = applianceId == null
        ? ''
        : '?${Uri(queryParameters: {'appliance_id': applianceId}).query}';
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/faq/answers/${Uri.encodeComponent(intent)}$query',
    );
    return CloudFaqAnswer.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      intent,
      applianceId: applianceId,
    );
  }

  Future<CloudRecommendationBatch> recommendations(
    String homeId,
    Set<String> applianceIds,
  ) async {
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/recommendations?capability=peak_demand_v1',
    );
    return _parseResponse(
      response,
      () => CloudRecommendationBatch.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
        applianceIds.map((id) => id.toLowerCase()).toSet(),
      ),
    );
  }

  Future<CloudCycleReferenceOption> dishwasherCycleReference(
    String homeId,
    String applianceId,
    Set<String> ownedApplianceIds,
  ) async {
    if (!_programUuid.hasMatch(homeId) ||
        !_programUuid.hasMatch(applianceId) ||
        !ownedApplianceIds.any(
          (id) => id.toLowerCase() == applianceId.toLowerCase(),
        )) {
      throw ArgumentError('Invalid dishwasher selection');
    }
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/appliances/${Uri.encodeComponent(applianceId)}/cycle-comparison/reference',
    );
    return CloudCycleReferenceOption.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<CloudCycleComparisonResult> compareDishwasherCycle(
    String homeId,
    String applianceId,
    Set<String> ownedApplianceIds,
    CloudCycleComparisonRequest input,
  ) async {
    if (!_programUuid.hasMatch(homeId) ||
        !_programUuid.hasMatch(applianceId) ||
        !ownedApplianceIds.any(
          (id) => id.toLowerCase() == applianceId.toLowerCase(),
        )) {
      throw ArgumentError('Invalid dishwasher selection');
    }
    final response = await _request(
      'POST',
      '/v1/homes/${Uri.encodeComponent(homeId)}/appliances/${Uri.encodeComponent(applianceId)}/cycle-comparison',
      jsonBody: jsonEncode(input.toJson()),
    );
    return CloudCycleComparisonResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      input,
    );
  }

  Future<CloudSavedCycleEvidence> saveDishwasherCycleEvidence(
    String homeId,
    String applianceId,
    Set<String> ownedApplianceIds,
    CloudCycleComparisonRequest input, {
    required String idempotencyKey,
  }) async {
    if (!_programUuid.hasMatch(homeId) ||
        !_programUuid.hasMatch(applianceId) ||
        !_programUuid.hasMatch(idempotencyKey) ||
        !ownedApplianceIds.any(
          (id) => id.toLowerCase() == applianceId.toLowerCase(),
        )) {
      throw ArgumentError('Invalid dishwasher evidence selection or key');
    }
    final response = await _request(
      'POST',
      '/v1/homes/${Uri.encodeComponent(homeId)}/appliances/${Uri.encodeComponent(applianceId)}/cycle-comparison/evidence',
      jsonBody: jsonEncode(input.toJson()),
      idempotencyKey: idempotencyKey,
    );
    if (response.statusCode != 201) {
      throw const FormatException('Cycle evidence was not created');
    }
    final saved = CloudSavedCycleEvidence.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      homeId: homeId,
      applianceId: applianceId,
      request: input,
    );
    if (saved.status != 'available') {
      throw const FormatException('New cycle evidence is unavailable');
    }
    return saved;
  }

  Future<CloudSavedCycleEvidence> dishwasherCycleEvidence(
    String homeId,
    String applianceId,
    Set<String> ownedApplianceIds,
    String evidenceId,
    CloudCycleComparisonRequest input,
  ) async {
    if (!_programUuid.hasMatch(homeId) ||
        !_programUuid.hasMatch(applianceId) ||
        !_programUuid.hasMatch(evidenceId) ||
        !ownedApplianceIds.any(
          (id) => id.toLowerCase() == applianceId.toLowerCase(),
        )) {
      throw ArgumentError('Invalid dishwasher evidence selection');
    }
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/appliances/${Uri.encodeComponent(applianceId)}/cycle-comparison/evidence/${Uri.encodeComponent(evidenceId)}',
    );
    return CloudSavedCycleEvidence.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      homeId: homeId,
      applianceId: applianceId,
      request: input,
      evidenceId: evidenceId,
    );
  }

  Future<List<CloudAttachment>> attachments(String homeId) async {
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/attachments',
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = body['attachments'];
    if (rows is! List) throw const FormatException('Invalid attachment list');
    return rows
        .map(
          (row) =>
              CloudAttachment.fromJson(row as Map<String, dynamic>, homeId),
        )
        .toList();
  }

  Future<bool> hasExactMeterEvidence(String homeId, String attachmentId) async {
    final query = Uri(
      queryParameters: {
        'granularity': 'day',
        'attachment_id': attachmentId,
        'limit': '100',
      },
    ).query;
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/metered-summaries?$query',
    );
    final page = CloudMeteredSummaryPage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    if (page.granularity != 'day') {
      throw const FormatException('Unexpected summary granularity');
    }
    return page.summaries.any(
      (row) =>
          row.kind == 'energy' &&
          row.attachmentId == attachmentId &&
          row.status == 'complete' &&
          row.allocationMethod == 'exact' &&
          (row.coveredSeconds ?? 0) > 0,
    );
  }

  Future<CloudIntervention> createIntervention(
    String homeId,
    CloudInterventionCreate input, {
    required String idempotencyKey,
  }) async {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(idempotencyKey)) {
      throw ArgumentError.value(idempotencyKey, 'idempotencyKey');
    }
    final response = await _request(
      'POST',
      '/v1/homes/${Uri.encodeComponent(homeId)}/interventions',
      jsonBody: jsonEncode(input.toJson()),
      idempotencyKey: idempotencyKey,
    );
    return CloudIntervention.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<CloudOutcome> interventionOutcome(
    String homeId,
    String interventionId,
  ) async {
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/interventions/${Uri.encodeComponent(interventionId)}/outcome',
    );
    return CloudOutcome.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      homeId,
      interventionId,
    );
  }

  final Map<String, _FactsCacheEntry> _factsCache = {};

  /// One owner-scoped facts read; a 304 reuses the cached parsed body.
  Future<CloudApplianceFacts> applianceFacts(
    String homeId,
    String applianceId, {
    String capability = 'gas_appliance_recommendations_v1',
  }) async {
    if (!_programUuid.hasMatch(homeId)) {
      throw ArgumentError.value(homeId, 'homeId');
    }
    if (!_programUuid.hasMatch(applianceId)) {
      throw ArgumentError.value(applianceId, 'applianceId');
    }
    final key = '$homeId/$applianceId/$capability';
    final generation = session.generation;
    var cached = _factsCache[key];
    if (cached != null && cached.generation != generation) {
      _factsCache.remove(key);
      cached = null;
    }
    final query = Uri(queryParameters: {'capability': capability}).query;
    final response = await _request(
      'GET',
      '/v1/homes/${Uri.encodeComponent(homeId)}/appliances/${Uri.encodeComponent(applianceId)}/facts?$query',
      ifNoneMatch: cached?.etag,
    );
    if (response.statusCode == 304) {
      if (cached == null) throw const FormatException('Unexpected 304');
      return cached.facts;
    }
    final etag = response.headers['etag'];
    final facts = _parseResponse(
      response,
      () => CloudApplianceFacts.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      ),
    );
    if (etag != null && RegExp(r'^"[^"]+"$').hasMatch(etag)) {
      _factsCache[key] = _FactsCacheEntry(etag, facts, generation);
    } else {
      _factsCache.remove(key);
    }
    return facts;
  }

  Future<CloudProgramPage> programs(
    String homeId,
    String applianceId,
    Set<String> ownedApplianceIds,
  ) async {
    _validateProgramSelection(homeId, applianceId, ownedApplianceIds);
    final query = Uri(queryParameters: {'appliance_id': applianceId}).query;
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/programs?$query',
    );
    return _parseResponse(
      response,
      () => CloudProgramPage.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      ),
    );
  }

  Future<CloudProgramPage> homePrograms(String homeId) async {
    if (!_programUuid.hasMatch(homeId)) {
      throw ArgumentError.value(homeId, 'homeId');
    }
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/programs',
    );
    return _parseResponse(
      response,
      () => CloudProgramPage.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      ),
    );
  }

  Future<CloudProgramRefresh> requestProgramRefresh(
    String homeId,
    String applianceId,
    Set<String> ownedApplianceIds, {
    required String idempotencyKey,
  }) async {
    _validateProgramSelection(homeId, applianceId, ownedApplianceIds);
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89ab][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(idempotencyKey)) {
      throw ArgumentError.value(idempotencyKey, 'idempotencyKey');
    }
    final response = await _request(
      'POST',
      '/v1/homes/${Uri.encodeComponent(homeId)}/programs/discovery-refresh',
      jsonBody: jsonEncode({'appliance_id': applianceId}),
      idempotencyKey: idempotencyKey,
    );
    if (response.statusCode != 202) {
      throw const FormatException('Unexpected program refresh response');
    }
    return CloudProgramRefresh.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<CloudProgramRefresh> programRefresh(
    String homeId,
    String requestId,
  ) async {
    if (!_programUuid.hasMatch(homeId) || !_programUuid.hasMatch(requestId)) {
      throw ArgumentError('Invalid home or refresh request');
    }
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/programs/discovery-refresh/${Uri.encodeComponent(requestId)}',
    );
    final refresh = CloudProgramRefresh.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    if (refresh.requestId.toLowerCase() != requestId.toLowerCase()) {
      throw const FormatException('Program refresh request ID changed');
    }
    return refresh;
  }

  static final _programUuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89ab][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  void _validateProgramSelection(
    String homeId,
    String applianceId,
    Set<String> ownedApplianceIds,
  ) {
    if (!_programUuid.hasMatch(homeId) ||
        !_programUuid.hasMatch(applianceId) ||
        !ownedApplianceIds.any(
          (id) => id.toLowerCase() == applianceId.toLowerCase(),
        )) {
      throw ArgumentError('Invalid home or appliance selection');
    }
  }

  Future<CloudMeteredSummaryPage> meteredSummaries(
    String homeId, {
    required String granularity,
    String? cursor,
  }) async {
    if (granularity != 'hour' && granularity != 'day') {
      throw ArgumentError.value(granularity, 'granularity');
    }
    final query = Uri(
      queryParameters: cursor == null
          ? {'granularity': granularity, 'limit': '50'}
          : {'cursor': cursor, 'limit': '50'},
    ).query;
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/metered-summaries?$query',
    );
    final page = CloudMeteredSummaryPage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    if (page.granularity != granularity) {
      throw const FormatException('Metered summary granularity changed');
    }
    final modeHeader = _caseInsensitiveHeader(
      response.headers,
      'x-energylens-data-mode',
    );
    final revisionHeader = _caseInsensitiveHeader(
      response.headers,
      'x-energylens-fixture-revision',
    );
    final evidenceRevision = _caseInsensitiveHeader(
      response.headers,
      'x-energylens-evidence-revision',
    );
    if (evidenceRevision != null &&
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$')
            .hasMatch(evidenceRevision)) {
      throw const FormatException('Invalid metered evidence revision');
    }
    if (modeHeader == null && revisionHeader == null ||
        modeHeader == 'household' && revisionHeader == null) {
      return CloudMeteredSummaryPage(
        granularity: page.granularity,
        summaries: page.summaries,
        nextCursor: page.nextCursor,
        evidenceRevision: evidenceRevision,
      );
    }
    if (modeHeader == 'sample' &&
        revisionHeader != null &&
        RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$')
            .hasMatch(revisionHeader)) {
      return CloudMeteredSummaryPage(
        granularity: page.granularity,
        summaries: page.summaries,
        nextCursor: page.nextCursor,
        dataMode: CloudApplianceDataMode.sample,
        fixtureRevision: revisionHeader,
        evidenceRevision: evidenceRevision,
      );
    }
    if (modeHeader == 'mixed' &&
        revisionHeader != null &&
        RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$')
            .hasMatch(revisionHeader)) {
      return CloudMeteredSummaryPage(
        granularity: page.granularity,
        summaries: page.summaries,
        nextCursor: page.nextCursor,
        dataMode: CloudApplianceDataMode.mixed,
        fixtureRevision: revisionHeader,
        evidenceRevision: evidenceRevision,
      );
    }
    throw const FormatException('Invalid metered summary provenance');
  }

  Future<List<CloudQuestion>> onboardingQuestions(
    String homeId,
    String applianceId,
  ) => questions(homeId, applianceId, purpose: 'onboarding');

  Future<List<CloudQuestion>> questions(
    String homeId,
    String applianceId, {
    required String purpose,
  }) async {
    if (purpose != 'onboarding' && purpose != 'avoid' && purpose != 'faq') {
      throw ArgumentError.value(purpose, 'purpose');
    }
    final query = Uri(
      queryParameters: {'purpose': purpose, 'appliance_id': applianceId},
    ).query;
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/questions?$query',
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = body['questions'];
    if (rows is! List) throw const FormatException('Invalid cloud questions');
    final questions = rows
        .map((row) => CloudQuestion.fromJson(row as Map<String, dynamic>))
        .toList();
    if (questions.any(
      (q) => q.applianceId != applianceId || q.purpose != purpose,
    )) {
      throw const FormatException(
        'Cloud question belongs to another appliance',
      );
    }
    if (questions.map((question) => question.id).toSet().length !=
        questions.length) {
      throw const FormatException('Duplicate cloud questions');
    }
    return questions;
  }

  Future<List<CloudSavedAnswer>> currentQuestionAnswers(
    String homeId,
    String applianceId,
  ) async {
    final query = Uri(queryParameters: {'appliance_id': applianceId}).query;
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/questions/answers?$query',
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = body['answers'];
    if (rows is! List) {
      throw const FormatException('Invalid saved cloud answers');
    }
    final answers = rows
        .map((row) => CloudSavedAnswer.fromJson(row as Map<String, dynamic>))
        .toList();
    if (answers.any((answer) => answer.applianceId != applianceId)) {
      throw const FormatException('Saved answer belongs to another appliance');
    }
    if (answers.map((answer) => answer.questionId).toSet().length !=
        answers.length) {
      throw const FormatException('Duplicate saved cloud answers');
    }
    return answers;
  }

  Future<void> submitQuestionAnswers(
    String homeId,
    List<CloudAnswerCreate> answers, {
    required String idempotencyKey,
  }) async {
    if (answers.isEmpty || answers.length > 50) {
      throw ArgumentError.value(answers, 'answers');
    }
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(idempotencyKey)) {
      throw ArgumentError.value(idempotencyKey, 'idempotencyKey');
    }
    final response = await _request(
      'POST',
      '/v1/homes/${Uri.encodeComponent(homeId)}/questions/answers',
      jsonBody: jsonEncode({
        'answers': answers.map((answer) => answer.toJson()).toList(),
      }),
      idempotencyKey: idempotencyKey,
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['answers'] is! List ||
        (body['answers'] as List).length != answers.length) {
      throw const FormatException('Invalid cloud answer response');
    }
    final returnedRows = (body['answers'] as List)
        .map((row) => row as Map<String, dynamic>)
        .toList();
    final returned = returnedRows.map(CloudSavedAnswer.fromJson).toList();
    for (var index = 0; index < answers.length; index++) {
      final expected = answers[index];
      final actual = returned[index];
      if (returnedRows[index]['home_id'] != homeId ||
          actual.questionId != expected.question.id ||
          actual.questionVersion != expected.question.version ||
          actual.applianceId != expected.question.applianceId ||
          actual.identityRevision != expected.question.identityRevision ||
          actual.status != (expected.value == null ? 'unknown' : 'confirmed') ||
          actual.value != expected.value) {
        throw const FormatException('Cloud answer acknowledgement changed');
      }
    }
  }

  Future<CloudHome> createHome(
    CloudHomeCreate input, {
    required String idempotencyKey,
  }) async {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(idempotencyKey)) {
      throw ArgumentError.value(idempotencyKey, 'idempotencyKey');
    }
    final response = await _request(
      'POST',
      '/v1/homes',
      jsonBody: jsonEncode(input.toJson()),
      idempotencyKey: idempotencyKey,
    );
    return CloudHome.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<HubClaimChallenge> beginHubClaim(
    String homeId,
    String localHubId,
  ) async {
    final response = await _request(
      'POST',
      '/v1/homes/${Uri.encodeComponent(homeId)}/hub-claims',
      jsonBody: jsonEncode({'local_hub_id': localHubId}),
      idempotencyKey: newCloudIdempotencyKey(),
    );
    return HubClaimChallenge.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<HubOwnership>> hubs(String homeId) async {
    final response = await get('/v1/homes/${Uri.encodeComponent(homeId)}/hubs');
    return _parseResponse(response, () {
      final rows = (jsonDecode(response.body) as Map<String, dynamic>)['hubs'];
      if (rows is! List) throw const FormatException('Invalid cloud hub list');
      return rows.map((row) {
        final hub = HubOwnership.fromJson(row as Map<String, dynamic>);
        if (hub.homeId != homeId) {
          throw const FormatException('Cloud hub belongs to another home');
        }
        return hub;
      }).toList();
    });
  }

  Future<HubOwnership> finishHubClaim(
    HubClaimProof proof, {
    required String idempotencyKey,
  }) async {
    final response = await _request(
      'POST',
      '/v1/hubs/claim',
      jsonBody: jsonEncode(proof.toJson()),
      idempotencyKey: idempotencyKey,
    );
    return HubOwnership.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<CloudVersioned<CloudAccountPreferences>> accountPreferences() async {
    final response = await get('/v1/me/preferences');
    final value = CloudAccountPreferences.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    return checkedPreference(value, response.headers['etag'], value.version);
  }

  Future<CloudVersioned<CloudAccountPreferences>> updateAccountPreferences(
    Map<String, dynamic> patch, {
    required String ifMatch,
    required String idempotencyKey,
  }) async {
    if (patch.isEmpty ||
        patch.keys.any((key) => key != 'email_reports_enabled')) {
      throw ArgumentError.value(patch, 'patch');
    }
    final response = await _request(
      'PATCH',
      '/v1/me/preferences',
      jsonBody: jsonEncode(patch),
      idempotencyKey: idempotencyKey,
      ifMatch: ifMatch,
    );
    final value = CloudAccountPreferences.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    return checkedPreference(value, response.headers['etag'], value.version);
  }

  Future<CloudVersioned<CloudHomePreferences>> homePreferences(
    String homeId,
  ) async {
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/preferences',
    );
    final value = CloudHomePreferences.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    return checkedPreference(value, response.headers['etag'], value.version);
  }

  Future<CloudVersioned<CloudHomePreferences>> updateHomePreferences(
    String homeId,
    CloudHomePreferences input, {
    required String ifMatch,
    required String idempotencyKey,
  }) async {
    final response = await _request(
      'PATCH',
      '/v1/homes/${Uri.encodeComponent(homeId)}/preferences',
      jsonBody: jsonEncode({
        'goal': input.goal,
        'comfort_priority': input.comfortPriority,
      }),
      idempotencyKey: idempotencyKey,
      ifMatch: ifMatch,
    );
    final value = CloudHomePreferences.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    return checkedPreference(value, response.headers['etag'], value.version);
  }

  Future<http.Response> get(String path) => _request('GET', path);

  /// Public lookup. No bearer token is sent or refreshed for this route.
  Future<CloudRegionalRate> regionalElectricityRate({
    required String country,
    required String postalCode,
  }) async {
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(country) || postalCode.trim().isEmpty) {
      throw ArgumentError('Invalid regional rate location');
    }
    final base = Uri.parse(session.config.apiUrl);
    if (!base.hasScheme ||
        base.host.isEmpty ||
        base.path != '' && base.path != '/') {
      throw StateError('Cloud API URL must be an origin without a path');
    }
    final query = Uri(
      queryParameters: {'country': country, 'postal_code': postalCode},
    ).query;
    final response = await _client.get(base.resolve('/v1/energy/rates?$query'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String code = 'http_${response.statusCode}';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        code = body['code'] as String? ?? code;
      } catch (_) {}
      throw CloudApiException(response.statusCode, code);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid regional rate response');
    }
    return CloudRegionalRate.fromJson(decoded);
  }

  static String _requiredEtag(http.Response response) {
    final value = response.headers['etag'];
    if (value == null || value.trim().isEmpty) {
      throw const FormatException('Missing resource ETag');
    }
    return value;
  }

  static void _validateIdempotencyKey(String key) {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(key)) {
      throw ArgumentError.value(key, 'idempotencyKey');
    }
  }

  static void _validateMutationHeaders(String ifMatch, String idempotencyKey) {
    if (ifMatch.trim().isEmpty ||
        ifMatch.contains('\r') ||
        ifMatch.contains('\n')) {
      throw ArgumentError.value(ifMatch, 'ifMatch');
    }
    _validateIdempotencyKey(idempotencyKey);
  }

  Future<http.Response> _request(
    String method,
    String path, {
    String? jsonBody,
    String? idempotencyKey,
    String? ifMatch,
    String? ifNoneMatch,
    String? reportSnapshotSha256,
  }) async {
    final sessionGeneration = session.generation;
    if (!session.config.hasCloudSignIn) {
      throw StateError('Cloud API is not configured');
    }
    if (!path.startsWith('/') || path.startsWith('//')) {
      throw ArgumentError.value(path, 'path');
    }
    final base = Uri.parse(session.config.apiUrl);
    if (base.path != '' && base.path != '/') {
      throw StateError('Cloud API URL must be an origin without a path');
    }
    final uri = base.resolve(path);
    final token = await session.accessToken();
    if (token == null || sessionGeneration != session.generation) {
      _rejectSession(sessionGeneration);
      throw const CloudApiException(401, 'not_authenticated');
    }
    Future<http.Response> send(String bearer) async {
      if (sessionGeneration != session.generation) {
        throw const CloudApiException(401, 'not_authenticated');
      }
      final request = http.Request(method, uri)
        ..headers['Authorization'] = 'Bearer $bearer';
      if (jsonBody != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonBody;
      }
      if (idempotencyKey != null) {
        request.headers['Idempotency-Key'] = idempotencyKey;
      }
      if (ifMatch != null) request.headers['If-Match'] = ifMatch;
      if (ifNoneMatch != null) request.headers['If-None-Match'] = ifNoneMatch;
      if (reportSnapshotSha256 != null) {
        request.headers['X-Report-Snapshot-SHA256'] = reportSnapshotSha256;
      }
      return http.Response.fromStream(await _client.send(request));
    }

    http.Response body;
    try {
      body = await send(token);
    } catch (error) {
      _requestFailureContexts[error] = CloudRequestFailureContext(
        error.runtimeType.toString(),
        null,
        uri.path,
      );
      rethrow;
    }
    if (sessionGeneration != session.generation) {
      throw const CloudApiException(401, 'not_authenticated');
    }
    if (body.statusCode == 401) {
      final fresh = await session.refreshAccessToken();
      if (fresh != null && sessionGeneration == session.generation) {
        try {
          body = await send(fresh);
        } catch (error) {
          _requestFailureContexts[error] = CloudRequestFailureContext(
            error.runtimeType.toString(),
            null,
            uri.path,
          );
          rethrow;
        }
      }
    }
    if (sessionGeneration != session.generation) {
      throw const CloudApiException(401, 'not_authenticated');
    }
    if ((body.statusCode < 200 || body.statusCode >= 300) &&
        !(ifNoneMatch != null && body.statusCode == 304)) {
      if (isSessionRejectionStatus(body.statusCode)) {
        _rejectSession(sessionGeneration);
      }
      String code = 'http_${body.statusCode}';
      Map<String, dynamic> details = const {};
      try {
        final json = jsonDecode(body.body) as Map<String, dynamic>;
        code = json['code'] as String? ?? code;
        if (json['details'] is Map<String, dynamic>) {
          details = json['details'] as Map<String, dynamic>;
        }
      } catch (_) {}
      throw CloudApiException(
        body.statusCode,
        code,
        details: details,
        path: uri.path,
      );
    }
    _responsePaths[body] = uri.path;
    return body;
  }

  void close() => _client.close();
}
