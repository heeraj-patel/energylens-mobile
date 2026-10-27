import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final css = File('assets/design_pages/shared/tablet_layout.css')
      .readAsStringSync();

  for (final page in [
    'settings_manage_devices',
    'settings_manual_device_entry',
    'settings_photo_scan_onboarding',
  ]) {
    test('$page keeps every method panel before the monitored list', () {
      final html = File('assets/design_pages/$page/app.html')
          .readAsStringSync();
      final view = html.indexOf('id="view-devices"');
      final selector = html.indexOf('id="method-btn-manual"', view);
      final scan = html.indexOf('id="section-scan"', view);
      final methodContent = page == 'settings_photo_scan_onboarding'
          ? html.indexOf('id="section-camera-form"', view)
          : html.indexOf('id="section-manual"', view);
      final monitored = html.indexOf('id="monitored-device-list"', view);

      expect(view, greaterThan(0));
      expect(selector, greaterThan(view));
      expect(scan, greaterThan(selector));
      expect(methodContent, greaterThan(scan));
      expect(monitored, greaterThan(methodContent));
      expect(
        html.substring(view - 80, view),
        contains('class="flex flex-col space-y-space-lg'),
      );
    });
  }

  test('phone keeps the vertical source layout', () {
    expect(
      css.split('@media (min-width: 700px)').first,
      isNot(contains('body[data-el-tab="settings"] #view-devices')),
    );
  });

  test('tablet keeps selected method and monitored list in compact flow', () {
    expect(
      css,
      contains('body[data-el-tab="settings"] #view-devices:not(.hidden) {\n'
          '    display: grid;\n'
          '    grid-template-columns: minmax(0, 1fr);\n'
          '    gap: 12px;'),
    );
    expect(css, isNot(contains('grid-template-rows: auto minmax(700px')));
    expect(css, isNot(contains('#view-devices > :last-child {')));
    expect(css, isNot(contains('#view-devices > :not(:first-child):not(:last-child).hidden')));
  });
}
