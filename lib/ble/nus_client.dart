import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../protocol/messages.dart';
import '../protocol/parser.dart';
import 'nus_uuids.dart';

/// Connection lifecycle exposed to the UI.
enum NusConnState { idle, scanning, connecting, ready, error }

/// One row in the terminal log.
class LogEntry {
  final DateTime time;
  final NuSMessage message;
  final bool outgoing;
  LogEntry(this.message, {this.outgoing = false}) : time = DateTime.now();
}

/// BLE central for one Nordic UART peripheral + line discipline on top.
///
/// Scan by NAME (our firmware does not advertise the NUS UUID — the 31-byte
/// advertising packet is full). After connect: discover services, find NUS by
/// UUID, subscribe to TX notifications, write `\n`-terminated lines to RX
/// (write-with-response — the firmware RX characteristic is WRITE-only).
class NusClient extends ChangeNotifier {
  NusConnState state = NusConnState.idle;
  String? errorText;
  List<ScanResult> scanResults = [];
  BluetoothDevice? device;
  String get deviceLabel {
    final d = device;
    if (d == null) {
      return '';
    }
    return d.platformName.isNotEmpty ? d.platformName : d.remoteId.str;
  }
  final List<LogEntry> log = [];

  /// Profile id from the latest `hello`/`proto` line, or null.
  /// A manual override via [setProfileOverride] wins until the next
  /// `hello`/`proto` line arrives (e.g. after reconnect).
  String? activeProfileId;

  /// Fresh terminal per connection when true (default). Auto-reconnects
  /// always keep history; only explicit connects clear.
  bool clearLogOnConnect = true;

  /// Prefix each terminal line with its arrival time when true (default off).
  bool showTimestamps = false;

  /// Buzz the phone when an `event rumble` line arrives (default off).
  /// Android-only in practice (iOS has no sustained-vibration API).
  bool vibrateOnRumble = false;

  static const _kClearLog = 'clearLogOnConnect';
  static const _kStamps = 'showTimestamps';
  static const _kVibrate = 'vibrateOnRumble';

  NusClient() {
    _loadPrefs();
  }

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

  static final _rumbleMagRe = RegExp(r'(?:strong|weak|left|right)=(\d+)');

  /// Maps an `event rumble ...` rest string to a vibration duration in ms.
  /// Understands SInput (`left=`/`right=`) and XInput (`strong=`/`weak=`)
  /// shapes; 0 when nothing parseable or all zero. Pure for testability.
  static int rumbleVibrateMs(String rest) {
    var peak = 0;
    for (final m in _rumbleMagRe.allMatches(rest)) {
      final v = int.tryParse(m.group(1)!) ?? 0;
      if (v > peak) {
        peak = v;
      }
    }
    if (peak <= 0) {
      return 0;
    }
    return 20 + (peak.clamp(0, 255) * 230 ~/ 255);
  }

  Future<void> _buzzForRumble(String rest) async {
    try {
      final ms = rumbleVibrateMs(rest);
      if (ms <= 0 || _disposed) {
        return;
      }
      if (await Vibration.hasVibrator() != true) {
        return;
      }
      await Vibration.vibrate(duration: ms);
    } catch (_) {
      // Haptics unavailable — never break the terminal for a buzz.
    }
  }

  /// Manually select a command profile (overrides auto-detection).
  void setProfileOverride(String id) {
    activeProfileId = id;
    _addInfo('Profile: $id (manual override).');
    _notify();
  }

  BluetoothCharacteristic? _rx;
  BluetoothCharacteristic? _tx;
  int _mtuPayload = 20;
  // Serializes all outbound writes. Without this, concurrent sendLine calls
  // (e.g. 10Hz motion streaming + a button tap) interleave MTU chunks on the
  // wire, garbling lines and stalling senders behind each other's awaits.
  Future<void> _sendQueue = Future.value();
  final StringBuffer _rxBuf = StringBuffer();
  final List<StreamSubscription> _subs = [];
  bool _disposed = false;
  bool _wantConnection = false;
  int _reconnectTries = 0;
  Timer? _reconnectTimer;

  // ------------------------------------------------------------------ setup

  /// Bluetooth scan/connect permissions. Location is requested too: on
  /// Android 11 and below (API <= 30) it is the ONLY runtime requirement —
  /// BLUETOOTH_SCAN/CONNECT don't exist there, so permission_handler reports
  /// them denied without ever showing a dialog. Requiring them would block
  /// scanning forever on older phones.
  Future<bool> ensurePermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return true;
    }
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    if (Platform.isAndroid) {
      final location = await Permission.locationWhenInUse.request();
      if (!location.isGranted) {
        return false;
      }
      final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      if (sdkInt <= 30) {
        return true;
      }
    }
    return scan.isGranted && connect.isGranted;
  }

  Stream<BluetoothAdapterState> get adapterState => FlutterBluePlus.adapterState;

  Future<bool> get isSupported => FlutterBluePlus.isSupported;

  // ------------------------------------------------------------------- scan

  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _scanWatchdog;

  Future<void> startScan() async {
    await stopScan();
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      scanResults = results;
      _notify();
    });
    state = NusConnState.scanning;
    errorText = null;
    _notify();
    // Broad scan on purpose: firmware cannot be filtered by NUS service UUID
    // (not advertised), so the UI filters by name instead.
    // No OS timeout: the scan runs until the user taps Stop. Repeated
    // start/stop bursts (>~5 per 30s) make Android serve empty results
    // (scan throttle), so one continuous scan beats frequent re-scans.
    // A 2-minute watchdog stops runaway scans (battery); re-tapping Scan
    // afterwards is a single start/stop pair, safely under the throttle.
    _scanWatchdog?.cancel();
    _scanWatchdog = Timer(const Duration(minutes: 2), () {
      if (state == NusConnState.scanning) {
        stopScan();
      }
    });
    // startScan returns when stopScan is called; drop back to idle here —
    // otherwise the button sticks on "Stop scan".
    await FlutterBluePlus.startScan();
    await _scanSub?.cancel();
    _scanSub = null;
    if (state == NusConnState.scanning) {
      state = NusConnState.idle;
      _notify();
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
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

  /// Drops all GATT/link subscriptions and characteristic handles without
  /// touching [device] or the want-connection flag. Must run before every
  /// (re)connect: otherwise each reconnect stacks another `_onNotifyBytes`
  /// listener and every line is logged N times.
  void _teardownLink() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _rx = null;
    _tx = null;
    _rxBuf.clear();
  }

  /// Post-connect setup shared by [connect] and the auto-reconnect path:
  /// MTU, service discovery, TX-notify subscribe, disconnect watcher.
  Future<void> _setupLink(BluetoothDevice d) async {
    // Larger writes = fewer chunks per line. Best effort; 20 is the fallback.
    try {
      if (Platform.isAndroid) {
        final mtu = await d.requestMtu(185);
        _mtuPayload = mtu - 3;
      } else {
        final mtu = await d.mtu.first.timeout(const Duration(seconds: 5));
        _mtuPayload = mtu - 3;
      }
      if (_mtuPayload < 20) {
        _mtuPayload = 20;
      }
    } catch (_) {
      _mtuPayload = 20;
    }

    final services = await d.discoverServices();
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
    await tx.setNotifyValue(true);
    _subs.add(tx.onValueReceived.listen(_onNotifyBytes));
    _subs.add(
      d.connectionState.listen((s) {
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
      if (clearLogOnConnect) {
        log.clear();
      }
      // License.nonprofit: this MIT-licensed companion app is personal/open-source use.
      try {
        await d.connect(license: License.nonprofit, timeout: const Duration(seconds: 15));
      } catch (_) {
        // One automatic retry: the board often holds a stale half-open link
        // that supervision timeout drops within seconds, so attempt two lands.
        _addInfo('Connect failed, retrying once…');
        _notify();
        await Future.delayed(const Duration(seconds: 2));
        await d.connect(license: License.nonprofit, timeout: const Duration(seconds: 15));
      }
      await _setupLink(d);

      state = NusConnState.ready;
      _addInfo('Connected. Send `help` anytime.');
      _notify();
      // Ask for identity outright: the pushed `hello` is best-effort (a
      // notify sent during CCCD enable can be lost in the race), while a
      // `proto?` reply always arrives. Either path selects the profile.
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
    // on explicit unsubscribe, so skipping this would leave a phantom
    // subscriber (harmless, but it eats the next greeting).
    try {
      await _tx?.setNotifyValue(false);
    } catch (_) {
      // Link already gone — harmless.
    }
    try {
      await device?.disconnect();
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
    // Drop stale notify/connection subscriptions now; the reconnect attempt
    // below re-subscribes from scratch via [_setupLink].
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
      if (!_wantConnection || d == null || _disposed) {
        return;
      }
      try {
        await d.connect(license: License.nonprofit, timeout: const Duration(seconds: 10));
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
      if (idx < 0) {
        break;
      }
      final line = s.substring(0, idx);
      _rxBuf.clear();
      _rxBuf.write(s.substring(idx + 1));
      if (line.trim().isEmpty) {
        continue;
      }
      final msg = parseLine(line);
      if (msg is HelloMessage) {
        activeProfileId = msg.profileId;
      } else if (msg is ProtoMessage) {
        activeProfileId = msg.profileId;
      }
      log.add(LogEntry(msg));
      if (msg is EventMessage && msg.name == 'rumble' && vibrateOnRumble) {
        unawaited(_buzzForRumble(msg.rest));
      }
    }
    _notify();
  }

  /// Sends one line (appends `\n`, chunks to the negotiated MTU).
  /// Outbound writes are serialized through [_sendQueue] so concurrent
  /// callers never interleave chunks; a tap waits at most one in-flight line.
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
        final end =
            (i + _mtuPayload < bytes.length) ? i + _mtuPayload : bytes.length;
        await rx.write(bytes.sublist(i, end));
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
    if (!_disposed) {
      notifyListeners();
    }
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
