import 'package:flutter/material.dart';

import 'ble/nus_client.dart';
import 'ui/scan_screen.dart';

void main() {
  runApp(const NusCompanionApp());
}

/// NuS-Gamepad-Companion v0.1: BLE scan/connect plus a Nordic UART terminal
/// with per-firmware command macros. See README.md.
class NusCompanionApp extends StatefulWidget {
  const NusCompanionApp({super.key});

  @override
  State<NusCompanionApp> createState() => _NusCompanionAppState();
}

class _NusCompanionAppState extends State<NusCompanionApp> {
  late final NusClient _client;

  @override
  void initState() {
    super.initState();
    _client = NusClient();
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NuS Gamepad Companion',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: ScanScreen(client: _client),
    );
  }
}
