import 'package:energylens_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the disconnected state without invented readings', (tester) async {
    await tester.pumpWidget(const EnergyLensApp());
    expect(find.text('No device connected'), findsOneWidget);
  });
}
