import 'dart:convert';

import 'package:http/http.dart' as http;

import '../cloud_auth/cloud_auth.dart';
import 'cloud_home.dart';
import 'cloud_appliance.dart';
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
import 'cloud_programs.dart';
import 'cloud_report_preview.dart';
import 'cloud_report_delivery.dart';
import 'cloud_tariff.dart';

class CloudApiException implements Exception {
  const CloudApiException(this.statusCode, this.code);
  final int statusCode;
  final String code;
  @override
  String toString() => 'Cloud API error $statusCode ($code)';
}

class CloudAccount {
  const CloudAccount({
    required this.id,
    required this.email,
    required this.emailVerified,
  });
  final String id;
  final String? email;
  final bool emailVerified;

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
    );
  }
}

/// Cloud bearer requests never read or send hub pairing credentials.
class CloudApiClient {
  CloudApiClient({required this.session, http.Client? client})
    : _client = client ?? http.Client();
  final CloudSession session;
  final http.Client _client;

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

  Future<CloudReportDelivery> queueReportDelivery(
    String homeId,
    String previewId,
    String approvedSnapshotSha256,
    List<String> recipients, {
    required String idempotencyKey,
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
    return CloudAccount.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<CloudHome>> homes() async {
    final response = await get('/v1/homes');
    final value = jsonDecode(response.body) as Map<String, dynamic>;
    final items = value['homes'];
    if (items is! List) throw const FormatException('Invalid cloud home list');
    return items
        .map((item) => CloudHome.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<CloudAppliance>> appliances(String homeId) async {
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/appliances',
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = body['appliances'];
    if (rows is! List) {
      throw const FormatException('Invalid cloud appliance list');
    }
    final appliances = rows
        .map((row) => CloudAppliance.fromJson(row as Map<String, dynamic>))
        .toList();
    if (appliances.any((item) => item.homeId != homeId)) {
      throw const FormatException('Cloud appliance belongs to another home');
    }
    return appliances;
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
    required String brand,
    required String model,
    required String fuel,
    String? region,
  }) async {
    final response = await _request(
      'POST',
      '/v1/catalog/model-search',
      jsonBody: jsonEncode({
        'brand': brand,
        'model': model,
        'fuel': fuel,
        'region': region,
      }),
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
    if (!faqIntents.containsKey(intent) ||
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
    );
  }

  Future<CloudRecommendationBatch> recommendations(
    String homeId,
    Set<String> applianceIds,
  ) async {
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/recommendations?capability=gas_dryer_recommendations_v1',
    );
    return CloudRecommendationBatch.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      applianceIds.map((id) => id.toLowerCase()).toSet(),
    );
  }

  Future<List<CloudAttachment>> attachments(String homeId) async {
    final response = await get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/attachments/',
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
    return CloudProgramPage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
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
    return page;
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
        patch.keys.any(
          (key) =>
              key != 'email_reports_enabled' &&
              key != 'history_disclosure_accepted_at',
        )) {
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

  Future<http.Response> _request(
    String method,
    String path, {
    String? jsonBody,
    String? idempotencyKey,
    String? ifMatch,
  }) async {
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
    if (token == null) throw const CloudApiException(401, 'not_authenticated');
    Future<http.Response> send(String bearer) async {
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
      return http.Response.fromStream(await _client.send(request));
    }

    var body = await send(token);
    if (body.statusCode == 401) {
      final fresh = await session.refreshAccessToken();
      if (fresh != null) body = await send(fresh);
    }
    if (body.statusCode < 200 || body.statusCode >= 300) {
      String code = 'http_${body.statusCode}';
      try {
        final json = jsonDecode(body.body) as Map<String, dynamic>;
        code = json['code'] as String? ?? code;
      } catch (_) {}
      throw CloudApiException(body.statusCode, code);
    }
    return body;
  }

  void close() => _client.close();
}
