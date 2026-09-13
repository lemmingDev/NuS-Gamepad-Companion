import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../../../ble/nus_uuids.dart';
import '../../../../data/models/scan_device.dart';
import '../../../../data/repositories/ble_repository.dart';

/// ViewModel for the scan feature.
///
/// Wraps [BleRepository] and adds UI-specific state (name filter, show-all
/// toggle) while keeping the view lean.  Exposes immutable snapshots and
/// commands; the view only does layout + [ListenableBuilder].
class ScanViewModel extends ChangeNotifier {
  final BleRepository repository;

  ScanViewModel({required this.repository}) {
    repository.addListener(_onRepositoryChanged);
  }

  // UI-only state -------------------------------------------------------
  String _filter = 'NuS';
  String get filter => _filter;

  bool _showAll = false;
  bool get showAll => _showAll;

  // Repository passthrough (read-only) ---------------------------------
  NusConnState get state => repository.state;
  bool get scanning => repository.state == NusConnState.scanning;
  String? get errorText => repository.errorText;
  Stream<BluetoothAdapterState> get adapterState => repository.adapterState;

  /// Raw results filtered by name and sorted (NUS first, then RSSI).
  List<ScanResult> get filteredResults {
    final q = _filter.toLowerCase();
    final results = repository.scanResults.where((r) {
      if (_showAll) return true;
      final name = r.advertisementData.advName.toLowerCase();
      return name.contains(q);
    }).toList();

    bool hasNus(ScanResult r) => r.advertisementData.serviceUuids
        .any((u) => u.str.toLowerCase() == nusServiceUuid.str.toLowerCase());

    results.sort((a, b) {
      final an = hasNus(a) ? 0 : 1;
      final bn = hasNus(b) ? 0 : 1;
      if (an != bn) return an - bn;
      return b.rssi.compareTo(a.rssi);
    });
    return results;
  }

  /// Domain-friendly wrapper for the filtered results.
  List<ScanDevice> get filteredDevices =>
      filteredResults.map((r) => ScanDevice(r)).toList();

  // Commands ------------------------------------------------------------
  void setFilter(String value) {
    if (_filter == value) return;
    _filter = value;
    notifyListeners();
  }

  void setShowAll(bool value) {
    if (_showAll == value) return;
    _showAll = value;
    notifyListeners();
  }

  Future<bool> ensurePermissions() => repository.ensurePermissions();

  Future<void> toggleScan() async {
    if (scanning) {
      await repository.stopScan();
      return;
    }
    final ok = await repository.ensurePermissions();
    if (!ok) return;
    await repository.startScan();
  }

  Future<void> connect(BluetoothDevice device) => repository.connect(device);

  // Lifecycle -----------------------------------------------------------
  void _onRepositoryChanged() {
    if (!_disposed) notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    try {
      repository.removeListener(_onRepositoryChanged);
    } catch (_) {}
    super.dispose();
  }
}
