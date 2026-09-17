import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/models/usb_direct_output_status.dart';

void main() {
  group('UsbDirectOutputStatus.fromMap', () {
    test('reads an active stream as the Android plugin reports it', () {
      final status = UsbDirectOutputStatus.fromMap({
        'state': 'active',
        'device': 'CS202',
        'sampleRate': 48000,
        'channels': 2,
        'bits': 16,
      });

      expect(status.state, UsbDirectOutputState.active);
      expect(status.deviceLabel, 'CS202');
      expect(status.sampleRate, 48000);
      expect(status.channels, 2);
      expect(status.bits, 16);
    });

    test('every state code the plugin sends is recognised', () {
      // Must match UsbDirectOutput.State codes in the Kotlin plugin.
      const codes = [
        'off',
        'noDevice',
        'androidRoutes',
        'permission',
        'denied',
        'active',
        'unsupported',
        'error',
      ];
      for (final code in codes) {
        final status = UsbDirectOutputStatus.fromMap({'state': code});
        expect(status.state.name, code);
      }
    });

    test('a null map (web, desktop, plugin missing) reads as off', () {
      final status = UsbDirectOutputStatus.fromMap(null);
      expect(status.state, UsbDirectOutputState.off);
      expect(status.deviceLabel, isNull);
    });

    test('an unknown state or malformed numbers do not throw', () {
      final status = UsbDirectOutputStatus.fromMap({
        'state': 'somethingNew',
        'sampleRate': '48000',
        'device': null,
      });
      expect(status.state, UsbDirectOutputState.off);
      expect(status.sampleRate, 0);
    });
  });
}
