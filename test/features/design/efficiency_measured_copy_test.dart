import 'package:energylens_mobile/core/cloud_api/cloud_household_energy.dart';
import 'package:energylens_mobile/features/design/design_page_bridge.dart';
import 'package:energylens_mobile/features/design/efficiency_measured_copy.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> money(String a) => {'amount': a, 'currency': 'USD'};

const idA = '22222222-2222-4222-8222-222222222222';
const idB = '33333333-3333-4333-8333-333333333333';
const names = {idA: 'Dryer', idB: 'Pool pump'};

Map<String, dynamic> device(
  String id, {
  Map<String, String>? amounts,
  Map<String, String>? basis,
}) => {
  'appliance_id': id,
  'night': amounts?['night'] == null ? null : money(amounts!['night']!),
  'away': amounts?['away'] == null ? null : money(amounts!['away']!),
  'peak': amounts?['peak'] == null ? null : money(amounts!['peak']!),
  'habits': amounts?['habits'] == null ? null : money(amounts!['habits']!),
  'basis': {
    'night': 'measured',
    'away': 'measured',
    'peak': 'measured',
    'habits': 'measured',
    ...?basis,
  },
};

Map<String, dynamic> measured({
  String? night = '3.100000',
  String? away = '1.200000',
  String? peak,
  String? habits,
  Map<String, String> bases = const {},
  List<Map<String, dynamic>> devices = const [],
}) => {
  'period_cost': money('40.000000'),
  'identified_opportunity': money('4.300000'),
  'optimal_base': money('30.000000'),
  'waste_opportunity': money('4.300000'),
  'away_opportunity': away == null ? null : money(away),
  'peak_rates_opportunity': peak == null ? null : money(peak),
  'habits_opportunity': habits == null ? null : money(habits),
  'night_total_opportunity': night == null ? null : money(night),
  'away_total_opportunity': away == null ? null : money(away),
  'chart_segment_width_percent': {
    'night': '72.09',
    'away': '27.91',
    'peak_rates': '0.00',
    'habits': '0.00',
  },
  'waste_timing_basis': 'measured_local_time',
  'evidence_basis': 'measured',
  'night_basis': night == null ? 'unmetered' : 'measured',
  'away_basis': away == null ? 'not_configured' : 'measured',
  'peak_rates_basis': peak == null ? 'flat_tariff' : 'measured',
  'habits_basis': habits == null ? 'insufficient_data' : 'measured',
  'waste_basis': 'measured',
  'night_window': {
    'start_local': '23:00',
    'end_local': '06:00',
    'timezone': 'America/Chicago',
  },
  'away_source': away == null ? 'none' : 'user_schedule',
  ...bases.map((k, v) => MapEntry(k, v)),
  'devices': devices,
};

Map<String, dynamic> synthetic() => {
  'period_cost': money('37.42'),
  'identified_opportunity': money('18.60'),
  'optimal_base': money('12.00'),
  'waste_opportunity': money('1.00'),
  'away_opportunity': money('4.20'),
  'peak_rates_opportunity': money('4.70'),
  'habits_opportunity': money('6.40'),
  'night_total_opportunity': money('3.30'),
  'away_total_opportunity': money('4.20'),
  'chart_segment_width_percent': {
    'night': '17.70',
    'away': '22.50',
    'peak_rates': '25.30',
    'habits': '34.50',
  },
  'waste_timing_basis': 'unknown_75_25_demo_fallback',
  'evidence_basis': 'synthetic',
};

CloudEfficiencyTrailing30Days parse(Map<String, dynamic> j) =>
    CloudEfficiencyTrailing30Days.fromJson(j);

void main() {
  test('synthetic payload parses as before and has no copy', () {
    final s = parse(synthetic());
    expect(s.evidenceBasis, 'synthetic');
    expect(s.nightTotalOpportunity!.amount, '3.30');
    expect(efficiencyMeasuredCopy(s, names), isNull);
  });

  test('synthetic stays strict about null amounts and measured-only keys', () {
    expect(
      () => parse({...synthetic(), 'night_total_opportunity': null}),
      throwsFormatException,
    );
    expect(
      () => parse({...synthetic(), 'night_basis': 'measured'}),
      throwsFormatException,
    );
    expect(
      () =>
          parse({...synthetic(), 'waste_timing_basis': 'measured_local_time'}),
      throwsFormatException,
    );
  });

  test('measured payload parses with null amounts, bases and devices', () {
    final s = parse(
      measured(
        devices: [
          device(idA, amounts: {'night': '3.1', 'away': '1.2'}),
        ],
      ),
    );
    expect(s.evidenceBasis, 'measured');
    expect(s.peakRatesOpportunity, isNull);
    expect(s.bases!.peakRates, 'flat_tariff');
    expect(s.awaySource, 'user_schedule');
    expect(s.nightWindow!.startLocal, '23:00');
    expect(s.devices.single.night!.amount, '3.1');
    final month = measured()..['month_to_date_cost'] = money('40.000000');
    month.remove('period_cost');
    expect(
      CloudEfficiencyMonthToDate.fromJson(month).evidenceBasis,
      'measured',
    );
  });

  test('measured rejects unknown basis and missing required fields', () {
    expect(
      () => parse(measured(bases: {'night_basis': 'guess'})),
      throwsFormatException,
    );
    expect(
      () => parse(measured()..remove('night_window')),
      throwsFormatException,
    );
  });

  test('measured amounts map to E-G1-1, 2, 3 and 4', () {
    final copy = efficiencyMeasuredCopy(
      parse(
        measured(
          peak: '2.500000',
          habits: '1.750000',
          devices: [
            device(idA, amounts: {'peak': '1.5', 'habits': '1.75'}),
            device(idB, amounts: {'peak': '1.0'}),
          ],
        ),
      ),
      names,
    )!;
    expect(copy['night'], [
      'Overnight standby cost you \$3.10 so far this month.',
    ]);
    expect(copy['away'], [
      'While you were away, devices on standby used \$1.20.',
    ]);
    expect(copy['peak'], [
      'Running Dryer and Pool pump during peak hours cost \$2.50 more than off-peak.',
    ]);
    expect(copy['habits'], [
      'Dryer used more per cycle than a typical model, about \$1.75 this month.',
    ]);
  });

  test('null components route their basis to E-G1-5, 6, 7', () {
    final copy = efficiencyMeasuredCopy(parse(measured(away: null)), names)!;
    expect(copy['away'], [
      "Set your usual away hours to see what runs while you're out.",
    ]);
    expect(copy['peak'], [
      'Your rate is the same all day. Add time-of-use rates if your plan has them.',
    ]);
    expect(copy['habits'], [
      "Answer a few usage questions and we'll compare your cycles.",
    ]);
  });

  test('unmetered and gas devices route to E-G1-8 and E-G1-9', () {
    final copy = efficiencyMeasuredCopy(
      parse(
        measured(
          devices: [
            device(idA, basis: {'night': 'unmetered', 'peak': 'unmetered'}),
            device(
              idB,
              basis: {
                'night': 'fuel_not_applicable',
                'peak': 'fuel_not_applicable',
              },
            ),
          ],
        ),
      ),
      names,
    )!;
    expect(
      copy['night'],
      contains('Connect a smart plug to see when Dryer uses energy.'),
    );
    expect(
      copy['night'],
      contains(
        "Gas use isn't tracked by time of day, so night and peak don't apply.",
      ),
    );
    expect(
      copy['peak'],
      contains('Connect a smart plug to see when Dryer uses energy.'),
    );
  });

  test('null-derived values never produce blank or null text', () {
    final s = parse(measured(away: null));
    final copy = efficiencyMeasuredCopy(s, names)!;
    for (final line in copy.values.expand((l) => l)) {
      expect(line, isNot(contains('null')));
      expect(line, isNot(contains('{')));
    }
    expect(copy['peak']!.any((l) => l.contains('cost')), isFalse);
    final script = buildEfficiencyMeasuredCopyScript(
      const DesignPageTicket('h', 'efficiency', 1),
      s,
      copy,
    );
    expect(
      script,
      contains(
        '"hide":["efficiency_text_017","efficiency_text_019","efficiency_text_021"]',
      ),
    );
    expect(script, contains('textContent'));
    expect(script, isNot(contains('innerHTML')));
  });
}
