import 'dart:convert';

import '../../core/cloud_api/cloud_api_client.dart';

/// Internal API transport for the dormant design-page integration. The static
/// DesignShell does not construct this repository or display its responses.
abstract interface class DesignPageTransport {
  Future<String> get(String path);
}

class CloudDesignPageTransport implements DesignPageTransport {
  const CloudDesignPageTransport(this.api);
  final CloudApiClient api;

  @override
  Future<String> get(String path) async => (await api.get(path)).body;
}

const designPageIds = <String>{
  'dashboard',
  'devices',
  'efficiency',
  'efficiency_away',
  'efficiency_habits',
  'efficiency_peak_rates',
  'perks_tips',
  'settings',
  'settings_manage_devices',
  'settings_manual_device_entry',
  'settings_photo_scan_onboarding',
  'tips_care_upgrades',
  'tips_efficiency',
  'tips_knowledge',
};

const designFixtureRevision = 'mobile_design_2026_10_06_v1';

class DesignTextSegment {
  const DesignTextSegment(
    this.path,
    this.text,
    this.hiddenInitially,
    this.iconGlyph,
  );
  final String path;
  final String text;
  final bool hiddenInitially;
  final bool iconGlyph;

  factory DesignTextSegment.fromJson(Map<String, dynamic> value) {
    final path = value['path'];
    final text = value['text'];
    final hidden = value['hidden_initially'];
    final icon = value['icon_glyph'];
    if (path is! String ||
        !path.startsWith('/html[1]/body[1]/') ||
        text is! String ||
        hidden is! bool ||
        icon is! bool) {
      throw const FormatException('Invalid design text segment');
    }
    return DesignTextSegment(path, text, hidden, icon);
  }
}

class DesignPageSnapshot {
  const DesignPageSnapshot({
    required this.homeId,
    required this.page,
    required this.snapshotId,
    required this.generatedAt,
    required this.asOf,
    required this.timezone,
    required this.period,
    required this.textSegments,
  });

  final String homeId;
  final String page;
  final String snapshotId;
  final DateTime? generatedAt;
  final DateTime? asOf;
  final String? timezone;
  final Map<String, String>? period;
  final List<DesignTextSegment> textSegments;

  factory DesignPageSnapshot.fromJson(
    Map<String, dynamic> value, {
    required String expectedHomeId,
    required String expectedPage,
  }) {
    final fixture = value['fixture'];
    final period = value['period'];
    DateTime? parseNullableTime(String key) {
      final raw = value[key];
      if (raw == null) return null;
      if (raw is! String || DateTime.tryParse(raw) == null) {
        throw const FormatException('Invalid design page timestamp');
      }
      return DateTime.parse(raw);
    }

    final generatedAt = parseNullableTime('generated_at');
    final asOf = parseNullableTime('as_of');
    if (value['schema_revision'] != 'mobile_design_page_v1' ||
        value['home_id'] != expectedHomeId ||
        value['page'] != expectedPage ||
        value['data_mode'] != 'sample' ||
        value['fixture_revision'] != designFixtureRevision ||
        value['scope'] != 'page_specific_sample' ||
        value['availability'] != 'available' ||
        value['evidence_basis'] != 'page_fixture' ||
        value['actions_enabled'] != false ||
        value['snapshot_id'] is! String ||
        (value['snapshot_id'] as String).isEmpty ||
        (value['timezone'] != null &&
            (value['timezone'] is! String ||
                (value['timezone'] as String).isEmpty)) ||
        (period != null &&
            (period is! Map<String, dynamic> ||
                period['start_local'] is! String ||
                period['end_exclusive_local'] is! String)) ||
        fixture is! Map<String, dynamic> ||
        fixture['fixture_revision'] != designFixtureRevision ||
        fixture['page'] != expectedPage ||
        fixture['ordered_text_segments'] is! List ||
        fixture['controls'] is! List ||
        fixture['media'] is! List ||
        fixture['initial_states'] is! List) {
      throw const FormatException('Invalid design page snapshot');
    }
    final segments = (fixture['ordered_text_segments'] as List)
        .map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('Invalid design text segment');
          }
          return DesignTextSegment.fromJson(item);
        })
        .toList(growable: false);
    return DesignPageSnapshot(
      homeId: expectedHomeId,
      page: expectedPage,
      snapshotId: value['snapshot_id'] as String,
      generatedAt: generatedAt,
      asOf: asOf,
      timezone: value['timezone'] as String?,
      period: period == null
          ? null
          : Map.unmodifiable({
              'start_local': period['start_local'] as String,
              'end_exclusive_local': period['end_exclusive_local'] as String,
            }),
      textSegments: List.unmodifiable(segments),
    );
  }
}

class DesignPageRepository {
  const DesignPageRepository(this.transport);
  final DesignPageTransport transport;

  Future<DesignPageSnapshot> fetch(String homeId, String page) async {
    if (homeId.isEmpty ||
        homeId.length > 128 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(homeId) ||
        !designPageIds.contains(page)) {
      throw ArgumentError('Invalid design page selection');
    }
    final body = await transport.get(
      '/v1/homes/${Uri.encodeComponent(homeId)}/design-pages/$page',
    );
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid design page response');
    }
    return DesignPageSnapshot.fromJson(
      decoded,
      expectedHomeId: homeId,
      expectedPage: page,
    );
  }
}
