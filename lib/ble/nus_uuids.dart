import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Nordic UART Service UUIDs. Verified against
/// NuS-NimBLE-Serial src/NuS.cpp (RX_CHARACTERISTIC_UUID / TX_CHARACTERISTIC_UUID).
///
/// NOTE: our ESP32 firmware advertises the service UUID in the SCAN RESPONSE
/// (the 31-byte adv packet itself is full), so service-UUID scan filtering
/// works on active scanners — but name matching remains the default since it
/// works on passive scans too. Service/characteristic use below is by UUID
/// discovery after connecting either way.
final Guid nusServiceUuid = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');

/// Central -> peripheral. WRITE-only on the firmware side: use
/// write-with-response (flutter_blue_plus' default). Do NOT use
/// withoutResponse writes against current firmware.
final Guid nusRxUuid = Guid('6E400002-B5A3-F393-E0A9-E50E24DCCA9E');

/// Peripheral -> central notifications. Subscribe on connect.
final Guid nusTxUuid = Guid('6E400003-B5A3-F393-E0A9-E50E24DCCA9E');
