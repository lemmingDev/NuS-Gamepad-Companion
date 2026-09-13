import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../ble/nus_uuids.dart';

/// Domain-friendly view of a BLE scan result.
///
/// Wraps the raw [ScanResult] so the UI does not depend directly on
/// `flutter_blue_plus` models for presentation logic.
class ScanDevice {
  final ScanResult raw;

  const ScanDevice(this.raw);

  /// Advertised name (may be empty).
  String get name => raw.advertisementData.advName;

  /// Remote identifier string.
  String get id => raw.device.remoteId.str;

  /// RSSI in dBm.
  int get rssi => raw.rssi;

  /// Whether the NUS service UUID was seen in the advertisement / scan
  /// response.
  bool get hasNus => raw.advertisementData.serviceUuids.any(
        (u) => u.str.toLowerCase() == nusServiceUuid.str.toLowerCase(),
      );

  BluetoothDevice get device => raw.device;
}
