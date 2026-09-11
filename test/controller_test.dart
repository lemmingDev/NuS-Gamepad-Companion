import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nus_gamepad_companion/ble/nus_client.dart';
import 'package:nus_gamepad_companion/ui/composite_dualsense_screen.dart';
import 'package:nus_gamepad_companion/ui/composite_xbox_screen.dart';
import 'package:nus_gamepad_companion/ui/controller_screen.dart';
import 'package:nus_gamepad_companion/ui/sinput_screen.dart';
import 'package:nus_gamepad_companion/ui/xinput_screen.dart';

void main() {
  group('isGenericControllerProfile', () {
    test('accepts strict + advanced + composite-generic', () {
      expect(
          isGenericControllerProfile('nus-bridge/generic-strict'), isTrue);
      expect(
          isGenericControllerProfile('nus-bridge/generic-advanced'), isTrue);
      expect(
          isGenericControllerProfile('nus-bridge/composite-generic'), isTrue);
      expect(isGenericControllerProfile('nus-bridge/xinput'), isFalse);
      expect(isGenericControllerProfile('nus-bridge/sinput'), isFalse);
      expect(
          isGenericControllerProfile('nus-bridge/composite-xbox'), isFalse);
      expect(
          isGenericControllerProfile('nus-bridge/composite-dualsense'),
          isFalse);
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

  group('CompositeXboxScreen / CompositeDualsenseScreen gates', () {
    test('composite-xbox gate accepts only nus-bridge/composite-xbox', () {
      expect(
          isCompositeXboxProfile('nus-bridge/composite-xbox'), isTrue);
      expect(isCompositeXboxProfile('nus-bridge/xinput'), isFalse);
      expect(
          isCompositeXboxProfile('nus-bridge/composite-dualsense'), isFalse);
      expect(
          isCompositeXboxProfile('nus-bridge/composite-generic'), isFalse);
      expect(isCompositeXboxProfile(null), isFalse);
    });

    test(
        'composite-dualsense gate accepts only '
        'nus-bridge/composite-dualsense', () {
      expect(
          isCompositeDualsenseProfile(
              'nus-bridge/composite-dualsense'),
          isTrue);
      expect(
          isCompositeDualsenseProfile('nus-bridge/composite-xbox'), isFalse);
      expect(isCompositeDualsenseProfile('nus-bridge/sinput'), isFalse);
      expect(isCompositeDualsenseProfile(null), isFalse);
    });
  });

  group('CompositeXboxScreen', () {
    testWidgets('shows 11 named buttons, sticks, triggers, dpad, share',
        (tester) async {
      final client = NusClient();
      addTearDown(client.dispose);
      await tester.pumpWidget(
        MaterialApp(home: CompositeXboxScreen(client: client)),
      );
      await tester.pump();
      const labels = {
        'a': 'A',
        'b': 'B',
        'x': 'X',
        'y': 'Y',
        'lb': 'LB',
        'rb': 'RB',
        'select': 'Select',
        'start': 'Start',
        'home': 'Home',
        'ls': 'LS',
        'rs': 'RS',
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
        expect(find.byKey(ValueKey('dpad-$h')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('share')), findsOneWidget);
    });

    testWidgets('button + dpad + share taps safe while idle',
        (tester) async {
      final client = NusClient();
      addTearDown(client.dispose);
      await tester.pumpWidget(
        MaterialApp(home: CompositeXboxScreen(client: client)),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('button-a')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('dpad-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dpad-1')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('share')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('share')));
      await tester.pump();
    });
  });

  group('CompositeDualsenseScreen', () {
    testWidgets('shows 20 named buttons, sticks, triggers, dpad, motion',
        (tester) async {
      final client = NusClient();
      addTearDown(client.dispose);
      await tester.pumpWidget(
        MaterialApp(home: CompositeDualsenseScreen(client: client)),
      );
      await tester.pump();
      for (final name in [
        'y',
        'b',
        'a',
        'x',
        'lb',
        'rb',
        'lt',
        'rt',
        'select',
        'start',
        'ls',
        'rs',
        'mode',
        'touchpad',
        'share',
        'mute',
        'l4',
        'r4',
        'l5',
        'r5',
      ]) {
        expect(find.byKey(ValueKey('button-$name')), findsOneWidget);
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
        expect(find.byKey(ValueKey('dpad-$h')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('motion-toggle')), findsOneWidget);
    });

    testWidgets('button + dpad taps safe while idle', (tester) async {
      final client = NusClient();
      addTearDown(client.dispose);
      await tester.pumpWidget(
        MaterialApp(home: CompositeDualsenseScreen(client: client)),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('button-y')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('dpad-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dpad-0')));
      await tester.pump();
    });
  });
}
