import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nus_gamepad_companion/ble/nus_client.dart';
import 'package:nus_gamepad_companion/ui/controller_screen.dart';

void main() {
  group('isGenericControllerProfile', () {
    test('accepts strict + advanced only', () {
      expect(
          isGenericControllerProfile('nus-bridge/generic-strict'), isTrue);
      expect(
          isGenericControllerProfile('nus-bridge/generic-advanced'), isTrue);
      expect(isGenericControllerProfile('nus-bridge/xinput'), isFalse);
      expect(isGenericControllerProfile('nus-bridge/sinput'), isFalse);
      expect(isGenericControllerProfile('nus-diag'), isFalse);
      expect(isGenericControllerProfile('bogus'), isFalse);
      expect(isGenericControllerProfile(null), isFalse);
    });
  });

  group('ControllerScreen', () {
    testWidgets('shows 16 buttons, 8 axes, 9 hat cells', (tester) async {
      final client = NusClient();
      addTearDown(client.dispose);
      await tester.pumpWidget(
        MaterialApp(home: ControllerScreen(client: client)),
      );
      await tester.pump();
      for (var b = 1; b <= 16; b++) {
        expect(find.byKey(ValueKey('button-$b')), findsOneWidget);
      }
      expect(find.byType(Slider), findsNWidgets(8));
      for (final name in ['x', 'y', 'z', 'rx', 'ry', 'rz', 's1', 's2']) {
        expect(find.byKey(ValueKey('axis-$name')), findsOneWidget);
      }
      for (var h = 0; h <= 8; h++) {
        expect(find.byKey(ValueKey('hat-$h')), findsOneWidget);
      }
    });

    testWidgets('button + hat taps do not throw while idle', (tester) async {
      final client = NusClient();
      addTearDown(client.dispose);
      await tester.pumpWidget(
        MaterialApp(home: ControllerScreen(client: client)),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('button-1')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('hat-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hat-1')));
      await tester.pump();
    });
  });
}
