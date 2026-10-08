import '../../core/cloud_api/cloud_api_client.dart';
import '../../core/cloud_api/cloud_faq.dart';
import 'knowledge_question_catalog.dart';

/// Search results contain only questions with an approved answer route.
class KnowledgeQuestion {
  const KnowledgeQuestion({required this.id, required this.label});

  final String id;
  final String label;
}

abstract interface class KnowledgeDomainSource {
  Future<CloudFaqAnswer> faqAnswer(
    String homeId,
    String questionId, {
    String? applianceId,
  });
}

class CloudKnowledgeDomainSource implements KnowledgeDomainSource {
  const CloudKnowledgeDomainSource(this.api);

  final CloudApiClient api;

  @override
  Future<CloudFaqAnswer> faqAnswer(
    String homeId,
    String questionId, {
    String? applianceId,
  }) => api.faqAnswer(homeId, questionId, applianceId: applianceId);
}

sealed class KnowledgeAnswerResult {
  const KnowledgeAnswerResult();
}

class KnowledgeAnswerAvailable extends KnowledgeAnswerResult {
  const KnowledgeAnswerAvailable(this.answer);

  final CloudFaqAnswer answer;
}

class KnowledgePreparedAnswerAvailable extends KnowledgeAnswerResult {
  const KnowledgePreparedAnswerAvailable(this.questionId, this.text);

  final String questionId;
  final String text;
}

class KnowledgeAnswerUnavailable extends KnowledgeAnswerResult {
  const KnowledgeAnswerUnavailable(this.questionId);

  final String questionId;
}

/// Nonvisual FAQ adapter. It does not synthesize answers.
class KnowledgeDomainRepository {
  KnowledgeDomainRepository(this.source, {KnowledgeQuestionCatalog? catalog})
    : catalog = catalog ?? _defaultCatalog();

  final KnowledgeDomainSource source;
  final KnowledgeQuestionCatalog catalog;
  static KnowledgeQuestionCatalog get bundledCatalog => _defaultCatalog();
  String? _homeId;
  int _generation = 0;

  static List<KnowledgeQuestion> get questions => List.unmodifiable(
    faqIntents.entries.map(
      (entry) => KnowledgeQuestion(id: entry.key, label: entry.value),
    ),
  );

  /// A bundled reviewed catalog can contain general and contextual questions
  /// beyond the five existing Cloud answer operations.
  List<KnowledgeQuestion> search(String query, {bool localPilot = false}) =>
      List.unmodifiable(
        catalog
            .search(query, localPilot: localPilot)
            .map(
              (entry) => KnowledgeQuestion(id: entry.id, label: entry.question),
            ),
      );

  Future<KnowledgeAnswerResult?> answerEntry(
    String? homeId,
    String questionId, {
    String? applianceId,
    bool localPilot = false,
  }) async {
    final entry = catalog.find(questionId, localPilot: localPilot);
    if (entry == null) return KnowledgeAnswerUnavailable(questionId);
    if (entry.preparedAnswer case final text?) {
      return KnowledgePreparedAnswerAvailable(questionId, text);
    }
    if (homeId == null) return KnowledgeAnswerUnavailable(questionId);
    return answer(homeId, entry.cloudIntent!, applianceId: applianceId);
  }

  void clear() {
    _homeId = null;
    _generation++;
  }

  Future<KnowledgeAnswerResult?> answer(
    String homeId,
    String questionId, {
    String? applianceId,
  }) async {
    if (!_uuid.hasMatch(homeId)) throw ArgumentError.value(homeId, 'homeId');
    _homeId = homeId;
    final generation = ++_generation;
    bool stale() => generation != _generation || _homeId != homeId;

    if (!faqIntents.containsKey(questionId) ||
        (questionId == 'device_operating_cost') != (applianceId != null)) {
      return KnowledgeAnswerUnavailable(questionId);
    }
    try {
      final answer = await source.faqAnswer(
        homeId,
        questionId,
        applianceId: applianceId,
      );
      if (stale()) return null;
      return KnowledgeAnswerAvailable(answer);
    } catch (_) {
      if (stale()) return null;
      rethrow;
    }
  }
}

KnowledgeQuestionCatalog _defaultCatalog() => KnowledgeQuestionCatalog([
  // Prepared entries have approved exact text. Evidence-gated drafts stay hidden.
  _prepared(
    'energy_power_difference',
    'What is the difference between power and energy?',
    'Power is how quickly electricity is used, measured in watts. Energy is how much electricity is used over time, measured in kilowatt-hours.',
    ['watts vs kilowatt hours'],
  ),
  _prepared(
    'kilowatt_hour',
    'What is a kilowatt-hour?',
    'One kilowatt-hour is the energy used by a 1,000-watt device running for one hour.',
    ['kwh', 'electricity unit'],
  ),
  _prepared(
    'estimated_cost_math',
    'How is my electricity cost estimated?',
    'An estimated cost combines an estimate of energy use with an electricity rate for the same period.',
    ['cost calculation', 'electric bill math'],
  ),
  _prepared(
    'why_estimate',
    'Why is a device cost an estimate?',
    'A device cost is an estimate when its energy use or electricity rate is based on available information rather than complete measurements for that period.',
    ['estimated device cost', 'accuracy'],
  ),
  _prepared(
    'useful_waste_meaning',
    'What do useful and wasted power mean here?',
    "Useful use is classified as serving a device's intended function. Wasted use is classified as avoidable. Use that cannot be classified stays separate.",
    ['productive power', 'energy waste meaning'],
  ),
  _prepared(
    'unknown_cost_meaning',
    'Why is some cost unclassified?',
    'Unclassified cost has not been assigned to useful or wasted use.',
    ['unknown cost', 'unclassified energy'],
  ),
  _prepared(
    'home_vs_devices',
    "Why don't my device totals add up to my home total?",
    'Your home total can include electricity that has not been assigned to a device. Compare home and device totals for the same period.',
    ['missing load', 'unattributed electricity'],
  ),
  _prepared(
    'data_coverage',
    'What does data coverage mean?',
    'Data coverage is the share of a selected period with usable energy readings.',
    ['missing readings', 'meter coverage'],
  ),
  _draft('latest_reading', 'How recent are my energy readings?', [
    'last meter reading',
    'data freshness',
  ]),
  _draft('home_top_use', 'Which devices use the most electricity in my home?', [
    'biggest energy users',
    'top consuming appliances',
  ]),
  _cloudEntry(
    'high_use',
    'What could contribute to high use?',
    'high_bill_possible_contributors',
  ),
  _cloudEntry(
    'reduce_waste',
    'Where could I reduce waste?',
    'top_waste_opportunities',
  ),
  _cloudEntry('reduce_cost', 'How could I reduce cost?', 'reduce_cost'),
  _draft('week_change', 'What changed in my energy use this week?', [
    'weekly energy change',
    'usage trend',
  ]),
  _draft('away_use', 'Why does my home use electricity when no one is there?', [
    'away energy use',
    'empty home power',
  ]),
  _draft('idle_devices', 'Which devices use power while idle?', [
    'standby devices',
    'idle power',
  ]),
  _pilot(
    'ac_afternoon',
    'Why did my AC power jump this afternoon?',
    'Outdoor heat peaked at 91°F. Your heat pump cycled more frequently between 2 PM and 5 PM.',
    ['air conditioner spike', 'ac usage jump', 'hvac afternoon'],
  ),
  _pilot(
    'standby_cost',
    'How much am I losing to phantom standby loads?',
    r'Around $0.11/day (~$3.30/mo), mostly from your study workstation and living room AV dock.',
    ['phantom load cost', 'vampire power', 'standby waste'],
  ),
  _draft('device_inventory', 'Which devices are in my home?', [
    'my appliances',
    'device list',
  ]),
  _cloudEntry(
    'device_cost',
    'What does a device cost to run?',
    'device_operating_cost',
  ),
  _draft('fridge_use', 'How much electricity did my refrigerator use?', [
    'fridge energy',
    'refrigerator consumption',
  ]),
  _draft('device_missing', "Why isn't a device showing up?", [
    'missing device',
    'appliance not found',
  ]),
  _draft('add_device', 'How do I add a device?', [
    'new appliance',
    'device onboarding',
  ]),
  _draft('correct_device', "How do I correct a device's make or model?", [
    'edit appliance model',
    'wrong manufacturer',
  ]),
  _pilot(
    'laundry_now',
    'Is right now a cheap time to run laundry?',
    'Yes! Tier 1 off-peak pricing is active until 4:00 PM.',
    ['washer time of use', 'laundry off peak', 'cheap washing'],
  ),
  _draft('peak_hours', 'When are my peak-rate hours?', [
    'time of use schedule',
    'expensive hours',
  ]),
  _draft('shift_cycle', 'Could moving a laundry cycle lower its cost?', [
    'shift washer',
    'laundry savings',
  ]),
  _cloudEntry(
    'device_programs',
    'Are there programs for a device?',
    'programs_for_device',
  ),
  _draft('home_programs', 'Are there energy programs for my home?', [
    'utility rebates',
    'home incentives',
  ]),
  _prepared(
    'program_missing',
    "Why isn't a program shown for my device?",
    'A program may be absent because we do not have reviewed information showing that it applies to this device. An absent listing does not confirm ineligibility.',
    ['missing rebate', 'program eligibility'],
  ),
  _draft('reduce_standby', 'How can I reduce standby use?', [
    'reduce phantom loads',
    'idle energy tips',
  ]),
  _draft('hvac_filter', 'When should I check my HVAC filter?', [
    'air filter maintenance',
    'furnace filter',
  ]),
  _draft(
    'refrigerator_care',
    'How can I check my refrigerator for avoidable energy use?',
    ['fridge maintenance', 'refrigerator care'],
  ),
  _draft('upgrade_choice', 'Would an efficient replacement help me save?', [
    'appliance upgrade savings',
    'energy efficient replacement',
  ]),
]);

KnowledgeCatalogEntry _draft(
  String id,
  String question,
  List<String> aliases,
) => KnowledgeCatalogEntry(
  id: id,
  question: question,
  aliases: aliases,
  availability: KnowledgeCatalogAvailability.draft,
);

KnowledgeCatalogEntry _prepared(
  String id,
  String question,
  String answer,
  List<String> aliases,
) => KnowledgeCatalogEntry(
  id: id,
  question: question,
  aliases: aliases,
  availability: KnowledgeCatalogAvailability.published,
  preparedAnswer: answer,
);

KnowledgeCatalogEntry _cloudEntry(String id, String question, String intent) =>
    KnowledgeCatalogEntry(
      id: id,
      question: question,
      aliases: [id, intent, ...?_questionAliases[intent]],
      availability: KnowledgeCatalogAvailability.published,
      cloudIntent: intent,
    );

KnowledgeCatalogEntry _pilot(
  String id,
  String question,
  String answer,
  List<String> aliases,
) => KnowledgeCatalogEntry(
  id: id,
  question: question,
  aliases: aliases,
  availability: KnowledgeCatalogAvailability.localPilot,
  preparedAnswer: answer,
);

const _questionAliases = <String, List<String>>{
  'high_bill_possible_contributors': [
    'why is my bill high',
    'high electricity bill',
    'what uses the most energy',
    'energy use increase',
    'power bill spike',
  ],
  'top_waste_opportunities': [
    'energy waste',
    'standby waste',
    'idle power',
    'reduce wasted energy',
    'biggest waste',
  ],
  'device_operating_cost': [
    'appliance running cost',
    'how much does my device cost',
    'cost of running my fridge',
    'device electricity cost',
  ],
  'reduce_cost': [
    'save money',
    'lower my bill',
    'cut electricity costs',
    'how to save energy',
  ],
  'programs_for_device': [
    'rebates',
    'utility programs',
    'incentives for appliances',
    'energy efficiency programs',
  ],
};

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
