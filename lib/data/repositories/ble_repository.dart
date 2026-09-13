import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../../ble/nus_uuids.dart';
import '../../domain/models/connection_state.dart';
import '../../domain/models/log_entry.dart';
import '../../protocol/messages.dart';
import '../../protocol/parser.dart';
import '../models/scan_device.dart';
import '../services/ble_service.dart';

export '../../domain/models/connection_state.dart';
export '../../domain/models/log_entry.dart';

/// Single source of truth for BLE connection state.
///
/// Consumes [BleService] (raw `flutter_blue_plus` API) and exposes
/// domain-friendly models to ViewModels.  Handles caching, retry, teardown
/// invariants, watchdog, MTU chunking, and line discipline.
///
/// This is the direct layered replacement for the former `NusClient` god
/// object; `NusClient` now delegates to this repository for backwards
/// compatibility.
class BleRepository extends ChangeNotifier {
  final BleService _ble;

  BleRepository({BleService? bleService})
      : _ble = bleService ?? const BleService() {
    _loadPrefs();
  }

  // ------------------------------------------------------------------ public
  NusConnState state = NusConnState.idle;
  String? errorText;
  List<ScanResult> scanResults = [];
  BluetoothDevice? device;

  String get deviceLabel {
    final d = device;
    if (d == null) return '';
    return d.platformName.isNotEmpty ? d.platformName : d.remoteId.str;
  }

  final List<LogEntry> log = [];

  /// Domain-friendly wrapper for scan results (NUS badge / sort).
  List<ScanDevice> get scanDevices =>
      scanResults.map((r) => ScanDevice(r)).toList();

  /// Profile id from latest `hello`/`proto`, or null.
  String? activeProfileId;

  bool clearLogOnConnect = true;
  bool showTimestamps = false;
  bool vibrateOnRumble = false;

  int lastLedIndex = 0;
  List<int> lastRgb = const [0, 0, 0];

  static const _kClearLog = 'clearLogOnConnect';
  static const _kStamps = 'showTimestamps';
  static const _kVibrate = 'vibrateOnRumble';

  // ---------------------------------------------------------------- prefs
  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      clearLogOnConnect = p.getBool(_kClearLog) ?? true;
      showTimestamps = p.getBool(_kStamps) ?? false;
      vibrateOnRumble = p.getBool(_kVibrate) ?? false;
      _notify();
    } catch (_) {
      // Prefs unavailable — fall back to defaults.
    }
  }

  Future<void> _savePrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kClearLog, clearLogOnConnect);
      await p.setBool(_kStamps, showTimestamps);
      await p.setBool(_kVibrate, vibrateOnRumble);
    } catch (_) {
      // Best effort only.
    }
  }

  void setClearLogOnConnect(bool v) {
    clearLogOnConnect = v;
    _notify();
    _savePrefs();
  }

  void setShowTimestamps(bool v) {
    showTimestamps = v;
    _notify();
    _savePrefs();
  }

  void setVibrateOnRumble(bool v) {
    vibrateOnRumble = v;
    _notify();
    _savePrefs();
  }

  // ------------------------------------------------------------ host state
  void _trackHostState(EventMessage msg) {
    if (msg.name == 'led') {
      final v = int.tryParse(msg.rest.trim());
      if (v != null) {
        lastLedIndex = v.clamp(0, 4);
      }
    } else if (msg.name == 'rgb') {
      final r = _kvInt(msg.rest, 'r');
      final g = _kvInt(msg.rest, 'g');
      final b = _kvInt(msg.rest, 'b');
      if (r != null || g != null || b != null) {
        final cur = List<int>.of(lastRgb);
        if (r != null) cur[0] = r.clamp(0, 255);
        if (g != null) cur[1] = g.clamp(0, 255);
        if (b != null) cur[2] = b.clamp(0, 255);
        lastRgb = cur;
      }
    }
  }

  static int? _kvInt(String rest, String key) {
    final m = RegExp('$key=(\\d+)').firstMatch(rest);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static final _rumbleMagRe = RegExp(r'(?:strong|weak|left|right)=(\d+)');

  /// Maps an `event rumble ...` rest string to a vibration duration in ms.
  static int rumbleVibrateMs(String rest) {
    var peak = 0;
    for (final m in _rumbleMagRe.allMatches(rest)) {
      final v = int.tryParse(m.group(1)!) ?? 0;
      if (v > peak) peak = v;
    }
    if (peak <= 0) return 0;
    return 20 + (peak.clamp(0, 255) * 230 ~/ 255);
  }

  Future<void> _buzzForRumble(String rest) async {
    try {
      final ms = rumbleVibrateMs(rest);
      if (ms <= 0 || _disposed) return;
      if (await Vibration.hasVibrator() != true) return;
      await Vibration.vibrate(duration: ms);
    } catch (_) {
      // Haptics unavailable — never break the terminal.
    }
  }

  void setProfileOverride(String id) {
    activeProfileId = id;
    _addInfo('Profile: $id (manual override).');
    _notify();
  }

  // ------------------------------------------------------------ BLE plumbing
  BluetoothCharacteristic? _rx;
  BluetoothCharacteristic? _tx;
  int _mtuPayload = 20;
  Future<void> _sendQueue = Future.value();
  final StringBuffer _rxBuf = StringBuffer();
  final List<StreamSubscription> _subs = [];
  bool _disposed = false;
  bool _wantConnection = false;
  int _reconnectTries = 0;
  Timer? _reconnectTimer;

  // ------------------------------------------------------------------ setup
  Future<bool> ensurePermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    if (Platform.isAndroid) {
      final location = await Permission.locationWhenInUse.request();
      if (!location.isGranted) return false;
      final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      if (sdkInt <= 30) return true;
    }
    return scan.isGranted && connect.isGranted;
  }

  Stream<BluetoothAdapterState> get adapterState => _ble.adapterState;

  Future<bool> get isSupported => _ble.isSupported;

  // ------------------------------------------------------------------- scan
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _scanWatchdog;

  Future<void> startScan() async {
    await stopScan();
    await _scanSub?.cancel();
    _scanSub = _ble.scanResults.listen((results) {
      scanResults = results;
      _notify();
    });
    state = NusConnState.scanning;
    errorText = null;
    _notify();
    _scanWatchdog?.cancel();
    _scanWatchdog = Timer(const Duration(minutes: 2), () {
      if (state == NusConnState.scanning) {
        stopScan();
      }
    });
    await _ble.startScan();
    await _scanSub?.cancel();
    _scanSub = null;
    if (state == NusConnState.scanning) {
      state = NusConnState.idle;
      _notify();
    }
  }

  Future<void> stopScan() async {
    try {
      await _ble.stopScan();
    } catch (_) {
      // Already stopped — harmless.
    }
    _scanWatchdog?.cancel();
    _scanWatchdog = null;
    await _scanSub?.cancel();
    _scanSub = null;
    if (state == NusConnState.scanning) {
      state = NusConnState.idle;
      _notify();
    }
  }

  // ---------------------------------------------------------------- connect
  void _teardownLink() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _rx = null;
    _tx = null;
    _rxBuf.clear();
  }

  Future<void> _setupLink(BluetoothDevice d) async {
    try {
      if (Platform.isAndroid) {
        final mtu = await _ble.requestMtu(d, 185);
        _mtuPayload = mtu - 3;
      } else {
        final mtu = await _ble.mtuStream(d).first.timeout(
              const Duration(seconds: 5),
            );
        _mtuPayload = mtu - 3;
      }
      if (_mtuPayload < 20) _mtuPayload = 20;
    } catch (_) {
      _mtuPayload = 20;
    }

    final services = await _ble.discoverServices(d);
    BluetoothCharacteristic? rx;
    BluetoothCharacteristic? tx;
    for (final s in services) {
      if (s.uuid == nusServiceUuid) {
        for (final c in s.characteristics) {
          if (c.uuid == nusRxUuid) {
            rx = c;
          } else if (c.uuid == nusTxUuid) {
            tx = c;
          }
        }
      }
    }
    if (rx == null || tx == null) {
      throw StateError('Nordic UART Service not found on this device.');
    }
    _rx = rx;
    _tx = tx;
    await _ble.setNotifyValue(tx, true);
    _subs.add(_ble.onValueReceived(tx).listen(_onNotifyBytes));
    _subs.add(
      _ble.connectionState(d).listen((s) {
        if (s == BluetoothConnectionState.disconnected && _wantConnection) {
          _onUnexpectedDisconnect();
        }
      }),
    );
  }

  Future<void> connect(BluetoothDevice d) async {
    await stopScan();
    state = NusConnState.connecting;
    errorText = null;
    activeProfileId = null;
    _notify();
    try {
      device = d;
      _wantConnection = true;
      _reconnectTries = 0;
      _teardownLink();
      if (clearLogOnConnect) log.clear();
      try {
        await _ble.connect(d, timeout: const Duration(seconds: 15));
      } catch (_) {
        _addInfo('Connect failed, retrying once…');
        _notify();
        await Future.delayed(const Duration(seconds: 2));
        await _ble.connect(d, timeout: const Duration(seconds: 15));
      }
      await _setupLink(d);

      state = NusConnState.ready;
      _addInfo('Connected. Send `help` anytime.');
      _notify();
      await sendLine('proto?');
    } catch (e) {
      state = NusConnState.error;
      errorText = e.toString();
      _wantConnection = false;
      _notify();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _wantConnection = false;
    _reconnectTimer?.cancel();
    // Clean unsubscribe first: the firmware only drops its subscriber count
    // on explicit unsubscribe.
    final tx = _tx;
    if (tx != null) {
      try {
        await _ble.setNotifyValue(tx, false);
      } catch (_) {
        // Link already gone — harmless.
      }
    }
    try {
      final d = device;
      if (d != null) await _ble.disconnect(d);
    } catch (_) {
      // Already gone — harmless.
    }
    _teardownLink();
    device = null;
    activeProfileId = null;
    if (state != NusConnState.idle) {
      state = NusConnState.idle;
      _notify();
    }
  }

  void _onUnexpectedDisconnect() {
    _teardownLink();
    _addInfo('Link lost.');
    if (_reconnectTries >= 3) {
      state = NusConnState.idle;
      errorText = 'Disconnected (auto-reconnect gave up after 3 tries).';
      _wantConnection = false;
      _notify();
      return;
    }
    _reconnectTries++;
    _addInfo('Reconnecting (try $_reconnectTries/3)…');
    _notify();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () async {
      final d = device;
      if (!_wantConnection || d == null || _disposed) return;
      try {
        await _ble.connect(d, timeout: const Duration(seconds: 10));
        await _setupLink(d);
        _reconnectTries = 0;
        _addInfo('Reconnected.');
        _notify();
      } catch (_) {
        _onUnexpectedDisconnect();
      }
    });
  }

  // --------------------------------------------------------------------- io
  void _onNotifyBytes(List<int> bytes) {
    _rxBuf.write(utf8.decode(bytes, allowMalformed: true));
    for (;;) {
      final s = _rxBuf.toString();
      final idx = s.indexOf('\n');
      if (idx < 0) break;
      final line = s.substring(0, idx);
      _rxBuf.clear();
      _rxBuf.write(s.substring(idx + 1));
      if (line.trim().isEmpty) continue;
      final msg = parseLine(line);
      if (msg is HelloMessage) {
        activeProfileId = msg.profileId;
      } else if (msg is ProtoMessage) {
        activeProfileId = msg.profileId;
      }
      log.add(LogEntry(msg));
      if (msg is EventMessage) {
        _trackHostState(msg);
        if (msg.name == 'rumble' && vibrateOnRumble) {
          unawaited(_buzzForRumble(msg.rest));
        }
      }
    }
    _notify();
  }

  /// Sends one line (appends `\n`, chunks to negotiated MTU).
  Future<void> sendLine(String line) {
    final rx = _rx;
    final text = line.trim();
    if (rx == null || text.isEmpty || state != NusConnState.ready) {
      return Future.value();
    }
    log.add(LogEntry(InfoMessage(text), outgoing: true));
    _notify();
    final bytes = utf8.encode('$text\n');
    final run = _sendQueue.then((_) async {
      for (var i = 0; i < bytes.length; i += _mtuPayload) {
        final end = (i + _mtuPayload < bytes.length)
            ? i + _mtuPayload
            : bytes.length;
        await _ble.write(rx, bytes.sublist(i, end));
      }
    });
    _sendQueue = run.catchError((_) {});
    return run;
  }

  void _addInfo(String text) {
    log.add(LogEntry(InfoMessage(text)));
  }

  void clearLog() {
    log.clear();
    _notify();
  }

  // ------------------------------------------------------------------ misc
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _scanWatchdog?.cancel();
    _scanWatchdog = null;
    _scanSub?.cancel();
    _scanSub = null;
    _teardownLink();
    super.dispose();
  }
}
