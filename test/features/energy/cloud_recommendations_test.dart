import 'package:energylens_mobile/core/cloud_api/cloud_recommendations.dart';
import 'package:flutter_test/flutter_test.dart';

const appliance = '22222222-2222-4222-8222-222222222222';
const foreign = '33333333-3333-4333-8333-333333333333';

Map<String, dynamic> action() => {
  'rule_id': 'computer.sleep_settings',
  'rule_version': 1,
  'appliance_id': appliance,
  'state': 'candidate',
  'title': 'Review sleep settings',
  'explanation': 'Check manufacturer-supported settings.',
  'next_question': 'hours_per_week',
  'benefit_group': 'computer_idle',
  'evidence_refs': <Map<String, dynamic>>[],
  'savings_amount': null,
};

void main() {
  test('accepts owner-scoped candidate and rejects unsupported savings', () {
    final body = {
      'actions': [action()],
      'as_of': '2026-10-01T12:00:00Z',
    };
    expect(
      CloudRecommendationBatch.fromJson(body, {appliance}).actions.single.state,
      'candidate',
    );
    expect(
      () => CloudRecommendationBatch.fromJson(
        {
          'actions': [
            {...action(), 'appliance_id': foreign},
          ],
          'as_of': body['as_of'],
        },
        {appliance},
      ),
      throwsFormatException,
    );
    expect(
      () => CloudRecommendationBatch.fromJson(
        {
          'actions': [
            {...action(), 'savings_amount': '20'},
          ],
          'as_of': body['as_of'],
        },
        {appliance},
      ),
      throwsFormatException,
    );
  });

  test('active action requires evidence and duplicate rules fail closed', () {
    expect(
      () => CloudRecommendationBatch.fromJson(
        {
          'actions': [
            {...action(), 'state': 'active', 'next_question': null},
          ],
          'as_of': '2026-10-01T12:00:00Z',
        },
        {appliance},
      ),
      throwsFormatException,
    );
    expect(
      () => CloudRecommendationBatch.fromJson(
        {
          'actions': [action(), action()],
          'as_of': '2026-10-01T12:00:00Z',
        },
        {appliance},
      ),
      throwsFormatException,
    );
  });
}
