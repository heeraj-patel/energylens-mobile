import 'package:flutter_test/flutter_test.dart';
import 'package:energylens_mobile/features/identify/appliance_onboarding_screen.dart';

void main() {
  test('extracts the approved label variants without changing OCR values', () {
    final cases = <(String, String?, String?, String?, String?)>[
      (
        'Model No. WRF555SDFZOO\nSerial No. K12345678\nFCC ID: A3LWRF555\nIC: 649E-WRF555',
        'WRF555SDFZOO',
        'K12345678',
        'A3LWRF555',
        '649E-WRF555',
      ),
      (
        'MODEL: RF28R7351SR/AA\nS/N: 0B4T4BAN600123',
        'RF28R7351SR/AA',
        '0B4T4BAN600123',
        null,
        null,
      ),
      ('MODEL NO.: WRF555SDFZ00', 'WRF555SDFZ00', null, null, null),
      ('MODEL\nWRF555SDFZ00', 'WRF555SDFZ00', null, null, null),
      ('Mod. UN55TU7000FXZA', 'UN55TU7000FXZA', null, null, null),
      ('MODEL/MODÈLE: 22LF450', '22LF450', null, null, null),
      ('MODEL #: 25-1234', '25-1234', null, null, null),
      ('Model No.:NS-24D310NA19', 'NS-24D310NA19', null, null, null),
      (
        'FCC ID: 2AB12-XYZ100\nIC: 12345A-XYZ100',
        null,
        null,
        '2AB12-XYZ100',
        '12345A-XYZ100',
      ),
      ('SER. NO. 1234ABCD', null, '1234ABCD', null, null),
      (
        'Model Number: LRFVS3006S\nSerial Number: 503KRAB12345',
        'LRFVS3006S',
        '503KRAB12345',
        null,
        null,
      ),
    ];
    for (final (label, model, serial, fcc, ic) in cases) {
      final fields = identityFieldsFromOcr(label);
      expect(fields.model, model, reason: label);
      expect(fields.serialNumber, serial, reason: label);
      expect(fields.fccId, fcc, reason: label);
      expect(fields.icId, ic, reason: label);
      expect(modelHintFromOcr(label), model, reason: label);
    }
  });

  test('brand uses the model label position even when its value follows', () {
    final cases = <(String, String)>[
      ('SAMSUNG\nMod. UN55TU7000FXZA', 'Samsung'),
      ('LG ELECTRONICS\nMODEL/MODÈLE: 22LF450', 'LG'),
      ('Whirlpool\nMODEL\nWRF555SDFZ00', 'Whirlpool'),
    ];
    for (final (label, brand) in cases) {
      expect(manufacturerHintFromOcr(label), brand, reason: label);
    }
  });

  test(
    'rejects neighboring labels and unlabeled or nonnumeric model values',
    () {
      for (final label in [
        'MODEL\nSERIAL NO. K123',
        'MODE: ABC123',
        'MODERN: ABC123',
        'MODEL: ABCDEF',
        'SERIAL: ABC1234',
        'unlabeled ABC1234',
      ]) {
        expect(modelHintFromOcr(label), isNull, reason: label);
      }
      expect(manufacturerHintFromOcr('LG\nMODEL\nSERIAL NO. K123'), isNull);
      expect(identityFieldsFromOcr('FCC ID: BAD\nIC: NOT-AN-ID').fccId, isNull);
      expect(identityFieldsFromOcr('FCC ID: BAD\nIC: NOT-AN-ID').icId, isNull);
    },
  );
}
