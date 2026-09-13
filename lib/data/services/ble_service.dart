import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Stateless wrapper around `flutter_blue_plus`.
///
/// The service returns raw platform plugin models (`ScanResult`,
/// `BluetoothDevice`, `BluetoothCharacteristic`, …) without transformation,
/// caching, or retry.  All business logic lives in [BleRepository].
class BleService {
  const BleService();

  Stream<BluetoothAdapterState> get adapterState =>
      FlutterBluePlus.adapterState;

  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  Future<bool> get isSupported => FlutterBluePlus.isSupported;

  /// Starts a continuous scan (no OS timeout).  Caller must call [stopScan]
  /// to complete the returned future.
  Future<void> startScan() => FlutterBluePlus.startScan();

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  Future<void> connect(
    BluetoothDevice device, {
    Duration timeout = const Duration(seconds: 15),
  }) =>
      device.connect(license: License.nonprofit, timeout: timeout);

  Future<void> disconnect(BluetoothDevice device) => device.disconnect();

  Future<List<BluetoothService>> discoverServices(
    BluetoothDevice device,
  ) =>
      device.discoverServices();

  Future<int> requestMtu(BluetoothDevice device, int mtu) =>
      device.requestMtu(mtu);

  Stream<int> mtuStream(BluetoothDevice device) => device.mtu;

  Future<void> setNotifyValue(
    BluetoothCharacteristic characteristic,
    bool enable,
  ) =>
      characteristic.setNotifyValue(enable);

  Stream<List<int>> onValueReceived(
    BluetoothCharacteristic characteristic,
  ) =>
      characteristic.onValueReceived;

  Future<void> write(
    BluetoothCharacteristic characteristic,
    List<int> value,
  ) =>
      characteristic.write(value);

  Stream<BluetoothConnectionState> connectionState(
    BluetoothDevice device,
  ) =>
      device.connectionState;
}
