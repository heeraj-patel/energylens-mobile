import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/features/energy/useful_waste_cost_card.dart';

void main() {
  Widget subject({
    double? useful = 1.25,
    double? waste = 0.5,
    double? unclassified = 0.15,
  }) => MaterialApp(
    home: Scaffold(
      body: UsefulWasteCostPanel(
        scopeLabel: 'Cost breakdown',
        periodLabel: 'Monthly',
        usefulCostUsd: useful,
        wasteCostUsd: waste,
        unclassifiedCostUsd: unclassified,
        detail: 'Waste is energy used while devices are idle.',
      ),
    ),
  );

  testWidgets('shows each cost, period and explanation', (tester) async {
    await tester.pumpWidget(subject());

    expect(find.text('Useful cost'), findsOneWidget);
    expect(find.text('Waste cost'), findsOneWidget);
    expect(find.text('Unclassified cost'), findsOneWidget);
    expect(find.text('\$1.25'), findsOneWidget);
    expect(find.text('\$0.50'), findsOneWidget);
    expect(find.text('\$0.15'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Cost breakdown'), findsOneWidget);
    expect(
      find.text('Waste is energy used while devices are idle.'),
      findsOneWidget,
    );
  });

  testWidgets('shows unavailable for each missing amount, not zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(useful: null, waste: null, unclassified: null),
    );

    expect(find.text('Unavailable'), findsNWidgets(3));
    expect(find.text('\$0.00'), findsNothing);
  });

  testWidgets('shows zero only when zero is explicitly provided', (
    tester,
  ) async {
    await tester.pumpWidget(subject(useful: 0, waste: 0, unclassified: 0));

    expect(find.text('\$0.00'), findsNWidgets(3));
    expect(find.text('Unavailable'), findsNothing);
  });
}
