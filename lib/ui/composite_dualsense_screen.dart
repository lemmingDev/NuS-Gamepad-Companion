import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../ble/nus_client.dart';
import '../protocol/profiles.dart';
import 'host_status_strip.dart';

/// Profile ids whose firmware speaks the CompositeHID DualSense bridge wire
/// syntax (`press`/`release`/`stick`/`trigger`/`dpad`/`motion`,
/// see the NuSDualSenseBridge sketch).
const kCompositeDualsenseProfiles = {
  'nus-bridge/composite-dualsense',
};

/// True when [id] resolves (via [profileForId]) to a CompositeHID DualSense
/// bridge profile.
bool isCompositeDualsenseProfile(String? id) =>
    kCompositeDualsenseProfiles.contains(profileForId(id).id);

/// Button names in pad order with their display labels.
const _buttonNames = [
  'y',
  'b',
  'a',
  'x',
  'lb',
  'rb',
  'lt',
  'rt',
  'select',
  'start',
  'ls',
  'rs',
  'mode',
  'touchpad',
  'share',
  'mute',
  'l4',
  'r4',
  'l5',
  'r5',
];

const _buttonLabels = {
  'y': 'Y',
  'b': 'B',
  'a': 'A',
  'x': 'X',
  'lb': 'LB',
  'rb': 'RB',
  'lt': 'LT',
  'rt': 'RT',
  'select': 'Select',
  'start': 'Start',
  'ls': 'LS',
  'rs': 'RS',
  'mode': 'Mode',
  'touchpad': 'Touch',
  'share': 'Share',
  'mute': 'Mute',
  'l4': 'L4',
  'r4': 'R4',
  'l5': 'L5',
  'r5': 'R5',
};

const _stickMin = -127.0;
const _stickMax = 127.0;
const _trigMin = 0.0;
const _trigMax = 255.0;

/// Dpad values in 3x3 grid order (row-major: [7,0,1 / 6,8,2 / 5,4,3]).
/// Wire order: 0=north 1=northeast 2=east 3=southeast 4=south 5=southwest
/// 6=west 7=northwest 8=none.
const _dpadGrid = [7, 0, 1, 6, 8, 2, 5, 4, 3];
const _dpadGlyphs = {
  0: '↑',
  1: '↗',
  2: '→',
  3: '↘',
  4: '↓',
  5: '↙',
  6: '←',
  7: '↖',
  8: '•',
};

/// On-screen CompositeHID DualSense gamepad: 20 named buttons, 2 sticks,
/// combined L+R triggers, 1 dpad, plus optional phone-IMU motion streaming.
///
/// Touch UI is skipped (terminal macros cover it); battery/charging/rumble/
/// LED/lightbar/trigger-FX stay terminal macros plus [HostStatusStrip].
/// Drives bridge commands through [NusClient.sendLine]. Pointer handlers
/// fire without awaiting so touch latency stays minimal.
class CompositeDualsenseScreen extends StatefulWidget {
  final NusClient client;
  const CompositeDualsenseScreen({super.key, required this.client});

  @override
  State<CompositeDualsenseScreen> createState() =>
      _CompositeDualsenseScreenState();
}

class _CompositeDualsenseScreenState extends State<CompositeDualsenseScreen> {
  final Set<String> _pressed = {};
  double _leftX = 0;
  double _leftY = 0;
  double _rightX = 0;
  double _rightY = 0;
  double _trigL = 0;
  double _trigR = 0;
  int _dpad = 8;

  // Phone-IMU motion streaming. Gyro rad/s x1000 and accel m/s^2 x500 land
  // in int16 range for realistic hand motion (clamped); this drives the
  // sketch's fire-and-forget `motion` command for testing, not calibrated
  // IMU fusion. Sent at 10Hz while enabled.
  bool _motionOn = false;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  Timer? _motionTimer;
  double _gx = 0, _gy = 0, _gz = 0, _ax = 0, _ay = 0, _az = 0;
  List<int>? _lastMotion;

  @override
  void dispose() {
    _stopMotion();
    super.dispose();
  }

  void _setMotion(bool on) {
    setState(() => _motionOn = on);
    if (!on) {
      _stopMotion();
      return;
    }
    _gyroSub = gyroscopeEventStream().listen((e) {
      _gx = e.x;
      _gy = e.y;
      _gz = e.z;
    });
    _accelSub = accelerometerEventStream().listen((e) {
      _ax = e.x;
      _ay = e.y;
      _az = e.z;
    });
    _motionTimer?.cancel();
    _lastMotion = null;
    _motionTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || !_motionOn) {
        return;
      }
      int c(double v, double s) => (v * s).round().clamp(-32768, 32767);
      final cur = [
        c(_gx, 1000),
        c(_gy, 1000),
        c(_gz, 1000),
        c(_ax, 500),
        c(_ay, 500),
        c(_az, 500),
      ];
      // Delta gate: a still phone sends nothing, so buttons/axes never queue
      // behind a wall of unchanged motion lines. Thresholds (~0.05 rad/s gyro,
      // ~0.2 m/s^2 accel) sit above sensor noise for hand-held use.
      final prev = _lastMotion;
      var changed = prev == null;
      if (!changed) {
        for (var i = 0; i < 6; i++) {
          final eps = i < 3 ? 50 : 100;
          if ((cur[i] - prev[i]).abs() >= eps) {
            changed = true;
            break;
          }
        }
      }
      if (!changed) {
        return;
      }
      _lastMotion = cur;
      _send('motion ${cur[0]} ${cur[1]} ${cur[2]} '
          '${cur[3]} ${cur[4]} ${cur[5]}');
    });
  }

  void _stopMotion() {
    _motionTimer?.cancel();
    _motionTimer = null;
    _gyroSub?.cancel();
    _gyroSub = null;
    _accelSub?.cancel();
    _accelSub = null;
  }

  void _send(String line) {
    unawaited(widget.client.sendLine(line));
  }

  void _press(String name) {
    setState(() {
      _pressed.add(name);
    });
    _send('press $name');
  }

  void _release(String name) {
    setState(() {
      _pressed.remove(name);
    });
    _send('release $name');
  }

  void _releaseAll() {
    setState(() {
      _pressed.clear();
    });
    for (final name in _buttonNames) {
      _send('release $name');
    }
  }

  void _sendStick(String side) {
    final x = side == 'left' ? _leftX.round() : _rightX.round();
    final y = side == 'left' ? _leftY.round() : _rightY.round();
    _send('stick $side $x $y');
  }

  void _centerStick(String side) {
    setState(() {
      if (side == 'left') {
        _leftX = 0;
        _leftY = 0;
      } else {
        _rightX = 0;
        _rightY = 0;
      }
    });
    _send('stick $side 0 0');
  }

  /// DualSense takes BOTH trigger values in one command.
  void _sendTriggers() {
    _send('trigger ${_trigL.round()} ${_trigR.round()}');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.client,
      builder: (context, _) {
        final client = widget.client;
        final profile = profileForId(client.activeProfileId);
        final connected = client.state == NusConnState.ready;
        final scheme = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.deviceLabel.isNotEmpty
                      ? client.deviceLabel
                      : 'DualSense Controller',
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  profile.label,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!connected)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Disconnected — controls disabled.'),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: HostStatusStrip(
                    ledIndex: client.lastLedIndex,
                    rgb: client.lastRgb,
                  ),
                ),
                Row(
                  children: [
                    const Expanded(
                      child: _SectionHeader(
                        title: 'Buttons',
                        wire: 'press <name>',
                      ),
                    ),
                    TextButton(
                      onPressed: connected ? _releaseAll : null,
                      child: const Text('Release all'),
                    ),
                  ],
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    mainAxisExtent: 64,
                  ),
                  itemCount: _buttonNames.length,
                  itemBuilder: (context, i) {
                    final name = _buttonNames[i];
                    final down = _pressed.contains(name);
                    return Listener(
                      key: ValueKey('button-$name'),
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: connected ? (_) => _press(name) : null,
                      onPointerUp: (_) => _release(name),
                      onPointerCancel: (_) => _release(name),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: down
                              ? scheme.primaryContainer
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: down
                                ? scheme.primary
                                : scheme.outlineVariant,
                          ),
                        ),
                        child: Text(
                          _buttonLabels[name]!,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: down
                                ? scheme.onPrimaryContainer
                                : scheme.onSurface,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const _SectionHeader(
                  title: 'Sticks',
                  wire: 'stick <left|right> <x> <y>',
                ),
                _StickAxisRow(
                  axisKey: 'stick-left-x',
                  label: 'LX',
                  value: _leftX,
                  enabled: connected,
                  onChanged: (v) => setState(() => _leftX = v),
                  onChangeEnd: () => _sendStick('left'),
                ),
                _StickAxisRow(
                  axisKey: 'stick-left-y',
                  label: 'LY',
                  value: _leftY,
                  enabled: connected,
                  onChanged: (v) => setState(() => _leftY = v),
                  onChangeEnd: () => _sendStick('left'),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const ValueKey('stick-left-center'),
                    onPressed: connected ? () => _centerStick('left') : null,
                    icon: const Icon(Icons.center_focus_weak),
                    label: const Text('Center left'),
                  ),
                ),
                _StickAxisRow(
                  axisKey: 'stick-right-x',
                  label: 'RX',
                  value: _rightX,
                  enabled: connected,
                  onChanged: (v) => setState(() => _rightX = v),
                  onChangeEnd: () => _sendStick('right'),
                ),
                _StickAxisRow(
                  axisKey: 'stick-right-y',
                  label: 'RY',
                  value: _rightY,
                  enabled: connected,
                  onChanged: (v) => setState(() => _rightY = v),
                  onChangeEnd: () => _sendStick('right'),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const ValueKey('stick-right-center'),
                    onPressed: connected ? () => _centerStick('right') : null,
                    icon: const Icon(Icons.center_focus_weak),
                    label: const Text('Center right'),
                  ),
                ),
                const _SectionHeader(
                  title: 'Triggers',
                  wire: 'trigger <l> <r>',
                ),
                _TriggerRow(
                  rowKey: 'trigger-l',
                  label: 'L',
                  value: _trigL,
                  enabled: connected,
                  onChanged: (v) => setState(() => _trigL = v),
                  onChangeEnd: _sendTriggers,
                ),
                _TriggerRow(
                  rowKey: 'trigger-r',
                  label: 'R',
                  value: _trigR,
                  enabled: connected,
                  onChanged: (v) => setState(() => _trigR = v),
                  onChangeEnd: _sendTriggers,
                ),
                _SectionHeader(
                  title: 'Dpad',
                  wire: 'dpad <0..8> (now $_dpad)',
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var r = 0; r < 3; r++)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var c = 0; c < 3; c++)
                              _DpadCell(
                                value: _dpadGrid[r * 3 + c],
                                selected: _dpad == _dpadGrid[r * 3 + c],
                                enabled: connected,
                                onDown: (v) {
                                  setState(() => _dpad = v);
                                  _send('dpad $v');
                                },
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                const _SectionHeader(
                  title: 'Motion',
                  wire: 'motion <p> <yw> <r> <ax> <ay> <az> @10Hz',
                ),
                SwitchListTile(
                  key: const ValueKey('motion-toggle'),
                  title: const Text('Stream phone IMU'),
                  subtitle: const Text(
                      'Gyro x1000, accel x500 — testing only, not calibrated'),
                  value: _motionOn,
                  onChanged: connected ? _setMotion : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String wire;
  const _SectionHeader({required this.title, required this.wire});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              wire,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StickAxisRow extends StatelessWidget {
  final String axisKey;
  final String label;
  final double value;
  final bool enabled;
  final void Function(double) onChanged;
  final void Function() onChangeEnd;
  const _StickAxisRow({
    required this.axisKey,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      key: ValueKey(axisKey),
      children: [
        SizedBox(
          width: 28,
          child: Text(
            label,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
        Expanded(
          child: Slider(
            min: _stickMin,
            max: _stickMax,
            divisions: 256,
            value: value,
            label: '${value.round()}',
            // Local echo while dragging, one line on release.
            onChanged: enabled ? onChanged : null,
            onChangeEnd: enabled ? (_) => onChangeEnd() : null,
          ),
        ),
        SizedBox(
          width: 60,
          child: Text(
            '${value.round()}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }
}

class _TriggerRow extends StatelessWidget {
  final String rowKey;
  final String label;
  final double value;
  final bool enabled;
  final void Function(double) onChanged;
  final void Function() onChangeEnd;
  const _TriggerRow({
    required this.rowKey,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      key: ValueKey(rowKey),
      children: [
        SizedBox(
          width: 28,
          child: Text(
            label,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
        Expanded(
          child: Slider(
            min: _trigMin,
            max: _trigMax,
            divisions: 256,
            value: value,
            label: '${value.round()}',
            // Local echo while dragging, one combined line on release.
            onChanged: enabled ? onChanged : null,
            onChangeEnd: enabled ? (_) => onChangeEnd() : null,
          ),
        ),
        SizedBox(
          width: 60,
          child: Text(
            '${value.round()}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }
}

class _DpadCell extends StatelessWidget {
  final int value;
  final bool selected;
  final bool enabled;
  final void Function(int) onDown;
  const _DpadCell({
    required this.value,
    required this.selected,
    required this.enabled,
    required this.onDown,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Listener(
        key: ValueKey('dpad-$value'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: enabled ? (_) => onDown(value) : null,
        child: Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Text(
            _dpadGlyphs[value]!,
            style: TextStyle(
              fontSize: 24,
              color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
