import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../../../data/repositories/ble_repository.dart';

/// ViewModel for the NUS terminal feature.
///
/// Exposes immutable snapshots of [BleRepository] state and forwards
/// commands.  The terminal view must remain a dumb layout layer
/// ([ListenableBuilder] on this ViewModel).
class TerminalViewModel extends ChangeNotifier {
  final BleRepository repository;

  TerminalViewModel({required this.repository}) {
    repository.addListener(_onRepositoryChanged);
  }

  // Snapshots -----------------------------------------------------------
  List<LogEntry> get log => repository.log;
  String? get activeProfileId => repository.activeProfileId;
  NusConnState get state => repository.state;
  bool get connected => repository.state == NusConnState.ready;
  String get deviceLabel => repository.deviceLabel;
  BluetoothDevice? get device => repository.device;
  String? get errorText => repository.errorText;
  int get lastLedIndex => repository.lastLedIndex;
  List<int> get lastRgb => repository.lastRgb;
  bool get clearLogOnConnect => repository.clearLogOnConnect;
  bool get showTimestamps => repository.showTimestamps;
  bool get vibrateOnRumble => repository.vibrateOnRumble;

  // Commands ------------------------------------------------------------
  Future<void> sendLine(String line) => repository.sendLine(line);

  void clearLog() => repository.clearLog();

  void setProfileOverride(String id) => repository.setProfileOverride(id);

  void setClearLogOnConnect(bool v) => repository.setClearLogOnConnect(v);

  void setShowTimestamps(bool v) => repository.setShowTimestamps(v);

  void setVibrateOnRumble(bool v) => repository.setVibrateOnRumble(v);

  Future<void> disconnect() => repository.disconnect();

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
