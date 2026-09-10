import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nus_gamepad_companion/ui/host_status_strip.dart';

void main() {
  testWidgets('shows player slot and rgb hex', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HostStatusStrip(ledIndex: 2, rgb: [255, 0, 128]),
        ),
      ),
    );
    expect(find.text('P2'), findsOneWidget);
    expect(find.text('#ff0080'), findsOneWidget);
  });

  testWidgets('shows dash when no player led', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HostStatusStrip(ledIndex: 0, rgb: [0, 0, 0]),
        ),
      ),
    );
    expect(find.text('—'), findsOneWidget);
    expect(find.text('#000000'), findsOneWidget);
  });
}
