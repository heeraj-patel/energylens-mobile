import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Devices controls stay directly above the feed at phone and tablet widths', () {
    final html = File('assets/design_pages/devices/app.html')
        .readAsStringSync();
    final css = File('assets/design_pages/shared/tablet_layout.css')
        .readAsStringSync();

    final controls = html.indexOf('id="devices-list-controls"');
    final feed = html.indexOf('id="devices-feed"');
    expect(controls, greaterThan(0));
    expect(feed, greaterThan(controls));
    expect(
      html.substring(controls + 'id="devices-list-controls"'.length, feed),
      isNot(contains('id="devices-')),
    );

    // Phone portrait and landscape use the HTML's flex column. Tablet portrait
    // retains that column, while the landscape grid must span both controls
    // and summary across all columns before the full-width feed.
    expect(
      html,
      contains(
        'class="flex flex-col w-full px-gutter space-y-space-md pb-space-lg"',
      ),
    );
    expect(
      css,
      contains(
        'body[data-el-page="devices"] main > div:first-of-type > :nth-child(2),\n'
        '  body[data-el-page="devices"] main > div:first-of-type > :nth-child(3) { grid-column: 1 / -1; }',
      ),
    );
    expect(
      css,
      contains(
        'body[data-el-page="devices"] #devices-feed {\n'
        '    display: grid;\n'
        '    grid-template-columns: repeat(3, minmax(0, 1fr));',
      ),
    );
    expect(
      css,
      isNot(
        contains(
          'body[data-el-page="devices"] #devices-list-controls { grid-column: span 3; }',
        ),
      ),
    );
  });

  test('efficiency subsection headings span both tablet columns', () {
    final css = File('assets/design_pages/shared/tablet_layout.css')
        .readAsStringSync();
    expect(
      css,
      contains(
        'body[data-el-tab="efficiency"] .tab-panel > [data-el-eff-copy],\n'
        '  body[data-el-tab="efficiency"] .tab-panel > '
        '[data-el-eff-copy] + * {\n'
        '    grid-column: 1 / -1;',
      ),
    );
  });

  test('general tips subsection headings span both tablet columns', () {
    final css = File('assets/design_pages/shared/tablet_layout.css')
        .readAsStringSync();
    expect(
      css,
      contains(
        'body[data-el-tab="tips"] #tab-panel-efficiency > '
        '.el-tips-section-title,\n'
        '  body[data-el-tab="tips"] #tab-panel-efficiency > '
        '#el-live-tips {\n'
        '    grid-column: 1 / -1;',
      ),
    );
    expect(
      css,
      contains(
        'body[data-el-tab="tips"] #el-live-tips:not(:empty) {\n'
        '    display: grid;\n'
        '    grid-template-columns: repeat(2, minmax(0, 1fr));',
      ),
    );
  });
}
