import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('packaged Perks links lead to the named official resources', () {
    const resources = <String, (String, String)>{
      'Austin Energy heat-pump water heater rebate': (
        'https://austinenergy.com/energy-efficiency/rebates-incentives/residential/appliances-equipment/hp-water-heater',
        'Austin Energy',
      ),
      'Weatherization Assistance Program': (
        'https://www.energy.gov/cmei/scep/wap/how-apply-weatherization-assistance',
        'U.S. Department of Energy',
      ),
      'GE Appliances promotions': (
        'https://www.geappliances.com/ge/rebates-promotions',
        'Model-specific offers',
      ),
      'Upgrade &amp; rebate search': (
        'https://www.energystar.gov/rebate-finder',
        'Rebate finder',
      ),
    };
    for (final name in ['app.html', 'code.html']) {
      final html = File('assets/design_pages/perks_tips/$name')
          .readAsStringSync();
      expect(html, isNot(contains('https://example.com/')), reason: name);
      for (final entry in resources.entries) {
        expect(html, contains(entry.key), reason: name);
        final hrefAt = html.indexOf('href="${entry.value.$1}"');
        expect(hrefAt, greaterThanOrEqualTo(0), reason: name);
        final anchorEnd = html.indexOf('</a>', hrefAt);
        expect(anchorEnd, greaterThan(hrefAt), reason: name);
        if (name == 'app.html' && entry.key != 'Upgrade &amp; rebate search') {
          final articleStart = html.lastIndexOf('<article', hrefAt);
          final titleAt = html.indexOf('>${entry.key}</h3>', articleStart);
          expect(titleAt, greaterThan(articleStart), reason: name);
          expect(titleAt, lessThan(hrefAt), reason: name);
        }
        expect(
          html.substring(hrefAt, anchorEnd),
          contains(
            name == 'app.html'
                ? entry.value.$2
                : entry.key == 'Upgrade &amp; rebate search'
                ? entry.value.$2
                : entry.key,
          ),
          reason: name,
        );
      }
      expect(html, isNot(contains('Rebate Pre-Approved')), reason: name);
      expect(html, isNot(contains('Tax Credit')), reason: name);
    }
  });
}
