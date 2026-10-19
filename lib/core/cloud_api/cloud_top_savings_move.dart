import 'cloud_household_energy.dart';

/// Typed model for the owner-scoped Top Savings Move response.
class CloudTopSavingsMove {
  const CloudTopSavingsMove({
    required this.homeId,
    required this.generatedAt,
    required this.move,
  });
  final String homeId;
  final DateTime generatedAt;
  final CloudSavingsMove? move;

  factory CloudTopSavingsMove.fromJson(
    Map<String, dynamic> json, {
    required String expectedHomeId,
  }) {
    _keys(json, const {'home_id', 'generated_at', 'window', 'move'});
    final homeId = json['home_id'];
    if (homeId is! String ||
        homeId.toLowerCase() != expectedHomeId.toLowerCase()) {
      throw const FormatException('Top savings move home changed');
    }
    final generatedAt = _dateTime(json['generated_at'], 'generated_at');
    final window = _object(json['window'], 'window');
    _keys(window, const {'start', 'end_exclusive'});
    final start = _dateTime(window['start'], 'window start');
    final end = _dateTime(window['end_exclusive'], 'window end');
    if (end.isBefore(start)) {
      throw const FormatException('Invalid top savings window');
    }
    final move = json['move'];
    return CloudTopSavingsMove(
      homeId: homeId,
      generatedAt: generatedAt,
      move: move == null ? null : CloudSavingsMove.fromJson(move),
    );
  }
}

class CloudSavingsMove {
  const CloudSavingsMove({
    required this.name,
    required this.monthlySavings,
    required this.basis,
    required this.evidenceBasis,
    this.applianceId,
    this.deviceId,
    this.dailyWaste,
    this.actionId,
    this.actionTitle,
  });
  final String? applianceId;
  final String? deviceId;
  final String name;
  final CloudEnergyMoney monthlySavings;
  final String basis;
  final String evidenceBasis;
  final CloudEnergyMoney? dailyWaste;
  final String? actionId;
  final String? actionTitle;

  factory CloudSavingsMove.fromJson(Object? value) {
    final json = _object(value, 'move');
    _keys(json, const {
      'appliance_id',
      'device_id',
      'name',
      'monthly_savings',
      'basis',
      'evidence_basis',
      'daily_waste',
      'action_id',
      'action_title',
    });
    final basis = json['basis'];
    if (basis != 'idle_waste' && basis != 'recommendation') {
      throw const FormatException('Invalid top savings basis');
    }
    final applianceId = _optionalString(json['appliance_id']);
    final deviceId = _optionalString(json['device_id']);
    if (applianceId == null && deviceId == null) {
      throw const FormatException('Top savings move has no device');
    }
    final dailyWaste = json['daily_waste'] == null
        ? null
        : CloudEnergyMoney.fromJson(json['daily_waste']);
    final actionTitle = _optionalString(json['action_title']);
    if (basis == 'idle_waste' && dailyWaste == null ||
        basis == 'recommendation' && actionTitle == null) {
      throw const FormatException('Incomplete top savings move');
    }
    return CloudSavingsMove(
      applianceId: applianceId,
      deviceId: deviceId,
      name: _nonempty(json['name'], 'name'),
      monthlySavings: CloudEnergyMoney.fromJson(json['monthly_savings']),
      basis: basis as String,
      evidenceBasis: _nonempty(json['evidence_basis'], 'evidence_basis'),
      dailyWaste: dailyWaste,
      actionId: _optionalString(json['action_id']),
      actionTitle: actionTitle,
    );
  }
}

Map<String, dynamic> _object(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('Invalid $field');
}

void _keys(Map<String, dynamic> json, Set<String> allowed) {
  if (json.length != allowed.length ||
      json.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('Invalid top savings response fields');
  }
}

String _nonempty(Object? value, String field) {
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException('Invalid $field');
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  return _nonempty(value, 'string');
}

DateTime _dateTime(Object? value, String field) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed != null) return parsed;
  throw FormatException('Invalid $field');
}
