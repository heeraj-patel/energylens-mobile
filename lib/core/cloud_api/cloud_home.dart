import 'dart:math';
import 'dart:convert';

import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

final bool _zonesReady = _initializeZones();

bool _initializeZones() {
  tz_data.initializeTimeZones();
  return true;
}

bool _validTimeZone(String value) {
  if (!_zonesReady || value.length < 3 || value.length > 100) return false;
  try {
    tz.getLocation(value);
    return true;
  } catch (_) {
    return false;
  }
}

class CloudHome {
  const CloudHome({
    required this.id,
    required this.name,
    required this.timezone,
    required this.countryCode,
    required this.postalCode,
    this.timezoneResolution,
    this.firstDeviceAddedAt,
    this.hasFirstDeviceStatus = false,
    this.version,
    this.etag,
  });

  final String id;
  final String name;
  final String timezone;
  final String countryCode;
  final String postalCode;
  final String? timezoneResolution;

  /// Server-owned milestone. A missing field means the read is not authoritative.
  final DateTime? firstDeviceAddedAt;
  final bool hasFirstDeviceStatus;
  final int? version;
  final String? etag;

  factory CloudHome.fromJson(Map<String, dynamic> json) {
    final location = json['location'];
    if (json['id'] is! String ||
        (json['id'] as String).isEmpty ||
        json['name'] is! String ||
        (json['name'] as String).isEmpty ||
        json['timezone'] is! String ||
        (json['timezone_resolution'] != null &&
            !{
              'resolved',
              'unresolved',
            }.contains(json['timezone_resolution'])) ||
        location is! Map<String, dynamic> ||
        location['country_code'] is! String ||
        location['postal_code'] is! String) {
      throw const FormatException('Invalid cloud home');
    }
    final milestone = json['first_device_added_at'];
    if (milestone != null &&
        (milestone is! String || DateTime.tryParse(milestone) == null)) {
      throw const FormatException('Invalid cloud home milestone');
    }
    return CloudHome(
      id: json['id'] as String,
      name: json['name'] as String,
      timezone: json['timezone'] as String,
      countryCode: location['country_code'] as String,
      postalCode: location['postal_code'] as String,
      timezoneResolution: json['timezone_resolution'] as String?,
      firstDeviceAddedAt: milestone == null
          ? null
          : DateTime.parse(milestone as String),
      hasFirstDeviceStatus: json.containsKey('first_device_added_at'),
      version: json['version'] as int?,
    );
  }
}

class CloudHomePatch {
  const CloudHomePatch({
    this.name,
    this.timezone,
    this.countryCode,
    this.postalCode,
  });
  final String? name;
  final String? timezone;
  final String? countryCode;
  final String? postalCode;

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{};
    if (name != null) result['name'] = name;
    if (timezone != null) result['timezone'] = timezone;
    if (countryCode != null || postalCode != null) {
      if (countryCode == null || postalCode == null) {
        throw ArgumentError('Both countryCode and postalCode are required');
      }
      result['location'] = {
        'country_code': countryCode,
        'postal_code': postalCode,
        'city': null,
        'county': null,
        'precision': 'postal_code',
        'source': 'user_entered',
      };
    }
    if (result.isEmpty) throw ArgumentError('Home update must not be empty');
    return result;
  }
}

class CloudHomeCreate {
  const CloudHomeCreate({
    required this.name,
    required this.timezone,
    required this.countryCode,
    required this.postalCode,
  });

  final String name;
  final String timezone;
  final String countryCode;
  final String postalCode;

  static CloudHomeCreate? validate({
    required String name,
    required String timezone,
    required String countryCode,
    required String postalCode,
  }) {
    final cleanedName = name.trim();
    final cleanedZone = timezone.trim();
    final cleanedCountry = countryCode.trim().toUpperCase();
    final cleanedPostal = postalCode.trim().toUpperCase();
    if (cleanedName.isEmpty ||
        utf8.encode(cleanedName).length > 120 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(cleanedName) ||
        !_validTimeZone(cleanedZone) ||
        !RegExp(r'^[A-Z]{2}$').hasMatch(cleanedCountry) ||
        !(cleanedCountry == 'US'
            ? RegExp(r'^\d{5}(?:-\d{4})?$').hasMatch(cleanedPostal)
            : RegExp(r'^[A-Z0-9][A-Z0-9 -]{0,19}$').hasMatch(cleanedPostal))) {
      return null;
    }
    return CloudHomeCreate(
      name: cleanedName,
      timezone: cleanedZone,
      countryCode: cleanedCountry,
      postalCode: cleanedPostal,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'timezone': timezone,
    'location': {
      'country_code': countryCode,
      'postal_code': postalCode,
      'city': null,
      'county': null,
      'precision': 'postal_code',
      'source': 'user_entered',
    },
  };
}

String newCloudIdempotencyKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String deviceIanaTimeZone() {
  final name = DateTime.now().timeZoneName;
  const zones = {
    'EST': 'America/New_York',
    'EDT': 'America/New_York',
    'CST': 'America/Chicago',
    'CDT': 'America/Chicago',
    'MST': 'America/Denver',
    'MDT': 'America/Denver',
    'PST': 'America/Los_Angeles',
    'PDT': 'America/Los_Angeles',
    'AKST': 'America/Anchorage',
    'AKDT': 'America/Anchorage',
    'HST': 'Pacific/Honolulu',
  };
  final candidate = zones[name] ?? (name.contains('/') ? name : 'UTC');
  return _validTimeZone(candidate) ? candidate : 'UTC';
}

/// Only a platform-provided IANA zone is safe as a silent setup default.
/// Abbreviations such as CST identify several different regions.
String? resolvedDeviceIanaTimeZone() {
  final name = DateTime.now().timeZoneName;
  return name.contains('/') && _validTimeZone(name) ? name : null;
}
