import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
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
