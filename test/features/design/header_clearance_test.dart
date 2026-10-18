import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main clears the fixed header plus the top safe-area inset', () {
    final css = File('assets/design_pages/shared/mobile_refinements.css')
        .readAsStringSync();
    expect(
      css,
      contains('body main.pt-16 {\n'
          '  padding-top: calc(4rem + env(safe-area-inset-top, 0px));'),
    );
  });
}
