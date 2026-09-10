import 'package:flutter_test/flutter_test.dart';
import 'package:nus_gamepad_companion/ble/nus_client.dart';

void main() {
  group('rumbleVibrateMs', () {
    test('empty and zero magnitudes give no buzz', () {
      expect(NusClient.rumbleVibrateMs(''), 0);
      expect(NusClient.rumbleVibrateMs('left=0 right=0'), 0);
      expect(NusClient.rumbleVibrateMs('strong=0 weak=0 ltrig=0 rtrig=0'), 0);
      expect(NusClient.rumbleVibrateMs('garbage text'), 0);
    });

    test('SInput left/right shapes scale to duration', () {
      expect(NusClient.rumbleVibrateMs('left=255 right=0'), 250);
      expect(NusClient.rumbleVibrateMs('left=0 right=255'), 250);
      final mid = NusClient.rumbleVibrateMs('left=128 right=64');
      expect(mid, greaterThan(20));
      expect(mid, lessThan(250));
    });

    test('XInput strong/weak shapes use the peak, ignore triggers', () {
      expect(NusClient.rumbleVibrateMs('strong=255 weak=255 ltrig=99 rtrig=99'), 250);
      // ltrig/rtrig must not count: only zeros elsewhere.
      expect(NusClient.rumbleVibrateMs('ltrig=99 rtrig=99'), 0);
      final mid = NusClient.rumbleVibrateMs('strong=100 weak=200 ltrig=0 rtrig=0');
      expect(mid, NusClient.rumbleVibrateMs('left=200 right=0'));
    });
  });
}
