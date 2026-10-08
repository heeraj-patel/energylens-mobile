import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/features/design/knowledge_page_script.dart';

void main() {
  test(
    'production renders all approved labels with fallback for missing evidence',
    () {
      final script = buildKnowledgePageScript();
      expect(RegExp('"id":').allMatches(script), hasLength(34));
      expect(script, contains('Power is how quickly electricity is used'));
      expect(script, contains('What is a kilowatt-hour?'));
      expect(script, contains('a program shown for my device?'));
      expect(script, contains("We can't answer this right now."));
      expect(script, isNot(contains('Outdoor heat peaked at 91°F')));
      expect(script, isNot(contains('Tier 1 off-peak pricing')));
      expect(script, contains('When are my peak-rate hours?'));
      expect(script, contains("existing.classList.remove('hidden')"));
    },
  );

  test('local pilot retains its three approved demo rows', () {
    final script = buildKnowledgePageScript(localPilot: true);
    expect(script, contains('Outdoor heat peaked at 91°F'));
    expect(script, contains('Tier 1 off-peak pricing'));
    expect(script, contains('phantom standby loads'));
  });
}
