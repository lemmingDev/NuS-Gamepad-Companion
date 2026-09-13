import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../data/repositories/ble_repository.dart';
import '../data/services/ble_service.dart';

// Re-export domain models so existing imports from `nus_client.dart`
// continue to resolve `NusConnState` and `LogEntry`.
export '../domain/models/connection_state.dart';
export '../domain/models/log_entry.dart';

/// Backward-compatible facade over [BleRepository].
///
/// The monolithic `NusClient` god object has been split into
/// `BleService` (stateless `flutter_blue_plus` wrapper) + `BleRepository`
/// (single source of truth).  This class now delegates every call to an
/// internal [BleRepository] instance so existing call sites
/// (`ScanScreen`, `TerminalScreen`, pad screens, tests) keep working
/// without behavioural change.
///
/// New code should inject [BleRepository] (or a feature [ChangeNotifier]
/// ViewModel) directly instead of using this facade.
class NusClient extends ChangeNotifier {
  final BleRepository _repo;
  final bool _ownsRepo;

  NusClient({BleService? bleService})
      : _repo = BleRepository(bleService: bleService ?? const BleService()),
        _ownsRepo = true {
    _repo.addListener(_onRepoChanged);
  }

  /// Shares an existing repository (e.g. from a ViewModel) without taking
  /// ownership — disposing the shim does not dispose the shared repository.
  NusClient.fromRepository(BleRepository repo)
      : _repo = repo,
        _ownsRepo = false {
    _repo.addListener(_onRepoChanged);
  }

  /// Direct access to the underlying repository for ViewModel wiring.
  BleRepository get repository => _repo;

  void _onRepoChanged() {
    if (!_disposed) notifyListeners();
  }

  bool _disposed = false;

  // ---------------------------------------------------------------- state
  NusConnState get state => _repo.state;
  set state(NusConnState v) {
    _repo.state = v;
    notifyListeners();
  }

  String? get errorText => _repo.errorText;
  set errorText(String? v) {
    _repo.errorText = v;
    notifyListeners();
  }

  List<ScanResult> get scanResults => _repo.scanResults;
  set scanResults(List<ScanResult> v) {
    _repo.scanResults = v;
    notifyListeners();
  }

  BluetoothDevice? get device => _repo.device;
  set device(BluetoothDevice? v) {
    _repo.device = v;
    notifyListeners();
  }

  String get deviceLabel => _repo.deviceLabel;

  List<LogEntry> get log => _repo.log;

  String? get activeProfileId => _repo.activeProfileId;
  set activeProfileId(String? v) {
    _repo.activeProfileId = v;
    notifyListeners();
  }

  bool get clearLogOnConnect => _repo.clearLogOnConnect;
  set clearLogOnConnect(bool v) => _repo.clearLogOnConnect = v;

  bool get showTimestamps => _repo.showTimestamps;
  set showTimestamps(bool v) => _repo.showTimestamps = v;

  bool get vibrateOnRumble => _repo.vibrateOnRumble;
  set vibrateOnRumble(bool v) => _repo.vibrateOnRumble = v;

  int get lastLedIndex => _repo.lastLedIndex;
  set lastLedIndex(int v) {
    _repo.lastLedIndex = v;
    notifyListeners();
  }

  List<int> get lastRgb => _repo.lastRgb;
  set lastRgb(List<int> v) {
    _repo.lastRgb = v;
    notifyListeners();
  }

  // ------------------------------------------------------------- behaviour
  void setClearLogOnConnect(bool v) => _repo.setClearLogOnConnect(v);
  void setShowTimestamps(bool v) => _repo.setShowTimestamps(v);
  void setVibrateOnRumble(bool v) => _repo.setVibrateOnRumble(v);

  static int rumbleVibrateMs(String rest) =>
      BleRepository.rumbleVibrateMs(rest);

  void setProfileOverride(String id) => _repo.setProfileOverride(id);

  Future<bool> ensurePermissions() => _repo.ensurePermissions();

  Stream<BluetoothAdapterState> get adapterState => _repo.adapterState;

  Future<bool> get isSupported => _repo.isSupported;

  Future<void> startScan() => _repo.startScan();

  Future<void> stopScan() => _repo.stopScan();

  Future<void> connect(BluetoothDevice d) => _repo.connect(d);

  Future<void> disconnect() => _repo.disconnect();

  Future<void> sendLine(String line) => _repo.sendLine(line);

  void clearLog() => _repo.clearLog();

  @override
  void dispose() {
    _disposed = true;
    _repo.removeListener(_onRepoChanged);
    if (_ownsRepo) _repo.dispose();
    super.dispose();
  }
}
