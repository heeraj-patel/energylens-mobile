class CloudDeviceState {
  const CloudDeviceState({
    required this.applianceId,
    required this.state,
    this.observedAt,
    this.watts,
  });

  final String applianceId;
  final String state;
  final DateTime? observedAt;
  final double? watts;

  factory CloudDeviceState.fromJson(Map<String, dynamic> json) {
    final id = json['appliance_id'];
    final state = json['state'];
    final rawObserved = json['observed_at'];
    final observed = rawObserved is String
        ? DateTime.tryParse(rawObserved)
        : null;
    final watts = json['watts'];
    if (id is! String ||
        id.isEmpty ||
        !const {'active', 'idle', 'standby'}.contains(state) ||
        (rawObserved != null && (observed == null || !observed.isUtc)) ||
        (watts != null && (watts is! num || !watts.isFinite || watts < 0)) ||
        (state == 'active' &&
            (observed == null || watts == null || watts <= 0)) ||
        (state == 'idle' && (observed == null || watts != 0)) ||
        (state == 'standby' && (observed != null || watts != null))) {
      throw const FormatException('Invalid cloud device state');
    }
    return CloudDeviceState(
      applianceId: id,
      state: state as String,
      observedAt: observed,
      watts: (watts as num?)?.toDouble(),
    );
  }
}

class CloudDeviceStates {
  const CloudDeviceStates({
    required this.homeId,
    required this.asOf,
    required this.states,
  });

  final String homeId;
  final DateTime asOf;
  final List<CloudDeviceState> states;

  factory CloudDeviceStates.fromJson(Map<String, dynamic> json, String homeId) {
    final asOf = json['as_of'] is String
        ? DateTime.tryParse(json['as_of'] as String)
        : null;
    final rows = json['states'];
    if (json['home_id'] != homeId ||
        asOf == null ||
        !asOf.isUtc ||
        rows is! List ||
        rows.length > 100) {
      throw const FormatException('Invalid cloud device states');
    }
    final ids = <String>{};
    final states = <CloudDeviceState>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        throw const FormatException('Invalid cloud device state row');
      }
      final state = CloudDeviceState.fromJson(row);
      if (!ids.add(state.applianceId) ||
          (state.observedAt != null && state.observedAt!.isAfter(asOf))) {
        throw const FormatException('Duplicate or future cloud device state');
      }
      states.add(state);
    }
    return CloudDeviceStates(
      homeId: homeId,
      asOf: asOf,
      states: List.unmodifiable(states),
    );
  }
}
