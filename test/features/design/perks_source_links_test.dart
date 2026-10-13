import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('packaged Perks links lead to the named official resources', () {
    const resources = <String, String>{
      'Austin Energy heat-pump water heater rebate': 'https://austinenergy.com/energy-efficiency/rebates-incentives/residential/appliances-equipment/hp-water-heater',
      'Weatherization Assistance Program': 'https://www.energy.gov/cmei/scep/wap/how-apply-weatherization-assistance',
      'GE Appliances promotions':
          'https://www.geappliances.com/ge/rebates-promotions',
      'Upgrade &amp; rebate search': 'https://www.energystar.gov/rebate-finder',
    };
    for (final name in ['app.html', 'code.html']) {
      final html = File('assets/design_pages/perks_tips/$name')
          .readAsStringSync();
      expect(html, isNot(contains('https://example.com/')), reason: name);
      for (final entry in resources.entries) {
        expect(html, contains(entry.key), reason: name);
        expect(html, contains('href="${entry.value}"'), reason: name);
        if (entry.key != 'Upgrade &amp; rebate search') {
          final hrefAt = html.indexOf('href="${entry.value}"');
          final anchorEnd = html.indexOf('</a>', hrefAt);
          expect(
            html.substring(hrefAt, anchorEnd),
            contains(entry.key),
            reason: name,
          );
        }
      }
      expect(html, isNot(contains('Rebate Pre-Approved')), reason: name);
      expect(html, isNot(contains('Tax Credit')), reason: name);
    }
  });
}
