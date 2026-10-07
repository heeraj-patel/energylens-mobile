import 'package:energylens_mobile/features/design/knowledge_question_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

KnowledgeCatalogEntry _cloud(String id, String question, String intent) =>
    KnowledgeCatalogEntry(
      id: id,
      question: question,
      availability: KnowledgeCatalogAvailability.published,
      cloudIntent: intent,
    );

void main() {
  test('a broad catalog searches beyond the five Cloud operations', () {
    final catalog = KnowledgeQuestionCatalog([
      _cloud(
        'high_use',
        'What could contribute to high use?',
        'high_bill_possible_contributors',
      ),
      _cloud('waste', 'Where could I reduce waste?', 'top_waste_opportunities'),
      _cloud(
        'device_cost',
        'What does a device cost to run?',
        'device_operating_cost',
      ),
      _cloud('lower_cost', 'How could I reduce cost?', 'reduce_cost'),
      _cloud(
        'programs',
        'Are there programs for a device?',
        'programs_for_device',
      ),
      KnowledgeCatalogEntry(
        id: 'kilowatt_hour',
        question: 'What is a kilowatt-hour?',
        aliases: const ['what is a kwh'],
        availability: KnowledgeCatalogAvailability.published,
        preparedAnswer: 'A kilowatt-hour is 1,000 watts used for one hour.',
      ),
      KnowledgeCatalogEntry(
        id: 'data_coverage',
        question: 'What does data coverage mean?',
        availability: KnowledgeCatalogAvailability.published,
        preparedAnswer:
            'It describes the part of a period with valid readings.',
      ),
    ]);

    expect(catalog.search(''), hasLength(7));
    expect(catalog.search('kwh').first.id, 'kilowatt_hour');
    expect(catalog.search('data covreage').first.id, 'data_coverage');
    expect(catalog.find('kilowatt_hour')?.cloudIntent, isNull);
    expect(catalog.find('kilowatt_hour')?.preparedAnswer, isNotNull);
    expect(catalog.find('device_cost')?.needsAppliance, isTrue);
    expect(catalog.find('high_use')?.needsAppliance, isFalse);
  });

  test('retains the three demo questions only in local pilot search', () {
    final catalog = KnowledgeQuestionCatalog([
      for (final (id, question) in <(String, String)>[
        ('ac_afternoon', 'Why did my AC power jump this afternoon?'),
        ('standby_cost', 'How much am I losing to phantom standby loads?'),
        ('laundry_now', 'Is right now a cheap time to run laundry?'),
      ])
        KnowledgeCatalogEntry(
          id: id,
          question: question,
          availability: KnowledgeCatalogAvailability.localPilot,
          preparedAnswer: 'Illustrative demo answer.',
        ),
      KnowledgeCatalogEntry(
        id: 'unapproved',
        question: 'Should this appear?',
        availability: KnowledgeCatalogAvailability.draft,
        preparedAnswer: 'Unapproved.',
      ),
    ]);

    expect(catalog.search(''), isEmpty);
    expect(catalog.search('', localPilot: true), hasLength(3));
    expect(catalog.search('standby'), isEmpty);
    expect(
      catalog.search('standby', localPilot: true).single.id,
      'standby_cost',
    );
    expect(catalog.find('unapproved', localPilot: true), isNull);
  });

  test('rejects ambiguous or unsupported answer bindings', () {
    expect(
      () => KnowledgeCatalogEntry(
        id: 'invalid',
        question: 'Question?',
        availability: KnowledgeCatalogAvailability.published,
        cloudIntent: 'unsupported',
      ),
      throwsFormatException,
    );
    expect(
      () => KnowledgeCatalogEntry(
        id: 'invalid',
        question: 'Question?',
        availability: KnowledgeCatalogAvailability.published,
        cloudIntent: 'reduce_cost',
        preparedAnswer: 'Conflicting answer.',
      ),
      throwsFormatException,
    );
    expect(
      () => KnowledgeQuestionCatalog([
        _cloud('same_id', 'First?', 'reduce_cost'),
        _cloud('same_id', 'Second?', 'reduce_cost'),
      ]),
      throwsFormatException,
    );
  });
}
