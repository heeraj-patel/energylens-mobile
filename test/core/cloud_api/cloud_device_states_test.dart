import 'package:energylens_mobile/core/cloud_api/cloud_device_states.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes legacy standby device state to offline', () {
    for (final wireState in ['standby', 'offline']) {
      final state = CloudDeviceState.fromJson({
        'appliance_id': 'device-1',
        'state': wireState,
      });
      expect(state.state, 'offline');
      expect(state.observedAt, isNull);
      expect(state.watts, isNull);
    }
  });

  test('offline device state cannot carry a current reading', () {
    expect(
      () => CloudDeviceState.fromJson({
        'appliance_id': 'device-1',
        'state': 'offline',
        'watts': 0,
      }),
      throwsFormatException,
    );
  });
}
