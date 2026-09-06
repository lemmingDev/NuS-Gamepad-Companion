import 'package:flutter_test/flutter_test.dart';
import 'package:nus_gamepad_companion/protocol/messages.dart';
import 'package:nus_gamepad_companion/protocol/parser.dart';
import 'package:nus_gamepad_companion/protocol/profiles.dart';

void main() {
  group('parseLine', () {
    test('hello', () {
      final m = parseLine('hello nus-diag 1');
      expect(m, isA<HelloMessage>());
      final h = m as HelloMessage;
      expect(h.profileId, 'nus-diag');
      expect(h.protoVer, 1);
    });

    test('proto', () {
      final m = parseLine('proto nus-bridge/xinput 1');
      expect(m, isA<ProtoMessage>());
      expect((m as ProtoMessage).profileId, 'nus-bridge/xinput');
    });

    test('ok bare and with detail', () {
      expect(parseLine('ok'), isA<OkMessage>());
      final m = parseLine('ok pressed 5');
      expect((m as OkMessage).detail, 'pressed 5');
    });

    test('err bare and with detail', () {
      expect(parseLine('err'), isA<ErrMessage>());
      final m = parseLine('err unknown command - send \'help\'');
      expect((m as ErrMessage).detail, contains('unknown command'));
    });

    test('event with and without rest', () {
      final a = parseLine('event rumble weak=1 strong=2 ltrig=3 rtrig=4');
      expect(a, isA<EventMessage>());
      expect((a as EventMessage).name, 'rumble');
      expect(a.rest, contains('weak=1'));
      final b = parseLine('event playerled 2');
      expect((b as EventMessage).name, 'playerled');
    });

    test('state', () {
      final m = parseLine('state buttons=1010000000000000');
      expect(m, isA<StateMessage>());
      expect((m as StateMessage).rest, contains('buttons='));
    });

    test('free text stays informational', () {
      expect(parseLine('[NuS] Generic bridge ready. Send \'help\'.'), isA<InfoMessage>());
      expect(
        parseLine('uptime_ms=68801 gamepad_connected=yes battery=81 free_heap=182240'),
        isA<InfoMessage>(),
      );
      expect(parseLine('BUTTON_4 pressed - will release in 5s.'), isA<InfoMessage>());
    });

    test('whitespace and empty lines', () {
      expect(parseLine('  ok pressed 5  '), isA<OkMessage>());
      expect(parseLine(''), isA<InfoMessage>());
      expect(parseLine('   '), isA<InfoMessage>());
    });

    test('near-misses do not misparse', () {
      // 'okay' is not 'ok'; 'error' is not 'err'.
      expect(parseLine('okay dokay'), isA<InfoMessage>());
      expect(parseLine('error boom'), isA<InfoMessage>());
    });
  });

  group('profiles', () {
    test('known ids resolve, unknown falls back', () {
      expect(profileForId('nus-diag').label, 'NuSSerialDiag');
      expect(profileForId('nus-bridge/composite-dualsense').label, contains('DualSense'));
      expect(profileForId('nope-unknown'), kFallbackProfile);
      expect(profileForId(null), kFallbackProfile);
    });

    test('every profile carries the common macros', () {
      for (final p in kProfiles) {
        final cmds = p.macros.map((m) => m.command).toSet();
        expect(cmds, containsAll(['help', 'proto?', 'status']), reason: p.id);
      }
    });
  });
}
