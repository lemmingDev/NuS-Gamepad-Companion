import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nus_gamepad_companion/ble/nus_client.dart';
import 'package:nus_gamepad_companion/ui/controller_screen.dart';
import 'package:nus_gamepad_companion/ui/sinput_screen.dart';
import 'package:nus_gamepad_companion/ui/xinput_screen.dart';

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

  group('SinputScreen / XinputScreen gates', () {
    test('sinput gate accepts only nus-bridge/sinput', () {
      expect(isSinputControllerProfile('nus-bridge/sinput'), isTrue);
      expect(isSinputControllerProfile('nus-bridge/xinput'), isFalse);
      expect(
          isSinputControllerProfile('nus-bridge/generic-strict'), isFalse);
      expect(isSinputControllerProfile(null), isFalse);
    });

    test('xinput gate accepts only nus-bridge/xinput', () {
      expect(isXinputControllerProfile('nus-bridge/xinput'), isTrue);
      expect(isXinputControllerProfile('nus-bridge/sinput'), isFalse);
      expect(
          isXinputControllerProfile('nus-bridge/generic-strict'), isFalse);
      expect(isXinputControllerProfile(null), isFalse);
    });
  });

  group('SinputScreen', () {
    testWidgets('shows 25 buttons, sticks, triggers, hat, specials',
        (tester) async {
      final client = NusClient();
      addTearDown(client.dispose);
      await tester.pumpWidget(
        MaterialApp(home: SinputScreen(client: client)),
      );
      await tester.pump();
      for (var b = 1; b <= 25; b++) {
        expect(find.byKey(ValueKey('button-$b')), findsOneWidget);
      }
      for (final k in [
        'stick-left-x',
        'stick-left-y',
        'stick-right-x',
        'stick-right-y',
        'trigger-left',
        'trigger-right',
      ]) {
        expect(find.byKey(ValueKey(k)), findsOneWidget);
      }
      for (var h = 0; h <= 8; h++) {
        expect(find.byKey(ValueKey('hat-$h')), findsOneWidget);
      }
      for (final s in ['start', 'select', 'home']) {
        expect(find.byKey(ValueKey('special-$s')), findsOneWidget);
      }
    });

    testWidgets('button + hat + special taps safe while idle',
        (tester) async {
      final client = NusClient();
      addTearDown(client.dispose);
      await tester.pumpWidget(
        MaterialApp(home: SinputScreen(client: client)),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('button-25')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('hat-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hat-1')));
      await tester.pump();
      await tester.ensureVisible(
          find.byKey(const ValueKey('special-start')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('special-start')));
      await tester.pump();
    });
  });

  group('XinputScreen', () {
    testWidgets('shows 11 labeled buttons, sticks, triggers, hat, specials',
        (tester) async {
      final client = NusClient();
      addTearDown(client.dispose);
      await tester.pumpWidget(
        MaterialApp(home: XinputScreen(client: client)),
      );
      await tester.pump();
      const labels = {
        1: 'A',
        2: 'B',
        3: 'X',
        4: 'Y',
        5: 'LB',
        6: 'RB',
        7: 'LS',
        8: 'RS',
        9: 'Select',
        10: 'Start',
        11: 'Home',
      };
      for (final e in labels.entries) {
        expect(find.byKey(ValueKey('button-${e.key}')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(ValueKey('button-${e.key}')),
            matching: find.text(e.value),
          ),
          findsOneWidget,
        );
      }
      for (final k in [
        'stick-left-x',
        'stick-left-y',
        'stick-right-x',
        'stick-right-y',
        'trigger-l',
        'trigger-r',
      ]) {
        expect(find.byKey(ValueKey(k)), findsOneWidget);
      }
      for (var h = 0; h <= 8; h++) {
        expect(find.byKey(ValueKey('hat-$h')), findsOneWidget);
      }
      for (final s in ['start', 'select', 'home', 'back']) {
        expect(find.byKey(ValueKey('special-$s')), findsOneWidget);
      }
    });

    testWidgets('button + hat + special taps safe while idle',
        (tester) async {
      final client = NusClient();
      addTearDown(client.dispose);
      await tester.pumpWidget(
        MaterialApp(home: XinputScreen(client: client)),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('button-1')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('hat-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hat-1')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('special-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('special-back')));
      await tester.pump();
    });
  });
}
