import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../ble/nus_client.dart';
import '../protocol/profiles.dart';

/// Profile ids whose firmware speaks the SInput bridge wire syntax
/// (`press`/`release`/`stick`/`trigger`/`hat`/`special`,
/// see the NuSSInputBridge sketch).
const kSinputControllerProfiles = {
  'nus-bridge/sinput',
};

/// True when [id] resolves (via [profileForId]) to an SInput bridge profile.
bool isSinputControllerProfile(String? id) =>
    kSinputControllerProfiles.contains(profileForId(id).id);

const _stickMin = -32767.0;
const _stickMax = 32767.0;
const _trigMin = 0.0;
const _trigMax = 32767.0;

/// Hat values in 3x3 grid order with their glyphs.
/// Wire order: 0=centered 1=up 2=up-right 3=right 4=down-right 5=down
/// 6=down-left 7=left 8=up-left.
const _hatGrid = [8, 1, 2, 7, 0, 3, 6, 5, 4];
const _hatGlyphs = {
  0: '•',
  1: '↑',
  2: '↗',
  3: '→',
  4: '↘',
  5: '↓',
  6: '↙',
  7: '←',
  8: '↖',
};

const _specials = ['start', 'select', 'home'];

/// On-screen SInput gamepad: 25 buttons, 2 sticks, 2 triggers, 1 hat,
/// start/select/home specials, plus optional phone-IMU motion streaming.
///
/// Touch commands stay terminal-only (need multitouch pads). Drives bridge
/// commands through [NusClient.sendLine]. Pointer handlers fire without
/// awaiting so touch latency stays minimal.
class SinputScreen extends StatefulWidget {
  final NusClient client;
  const SinputScreen({super.key, required this.client});

  @override
  State<SinputScreen> createState() => _SinputScreenState();
}

class _SinputScreenState extends State<SinputScreen> {
  final Set<int> _pressed = {};
  final Set<String> _specialsOn = {};
  double _leftX = 0;
  double _leftY = 0;
  double _rightX = 0;
  double _rightY = 0;
  double _trigLeft = 0;
  double _trigRight = 0;
  int _hat = 0;

  // Phone-IMU motion streaming. Gyro rad/s x1000 and accel m/s^2 x500 land
  // in int16 range for realistic hand motion (clamped); this drives the
  // sketch's fire-and-forget `motion` command for testing, not calibrated
  // IMU fusion. Sent at 10Hz while enabled.
  bool _motionOn = false;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  Timer? _motionTimer;
  double _gx = 0, _gy = 0, _gz = 0, _ax = 0, _ay = 0, _az = 0;

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
    _motionTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || !_motionOn) {
        return;
      }
      int c(double v, double s) =>
          (v * s).round().clamp(-32768, 32767);
      _send('motion ${c(_gx, 1000)} ${c(_gy, 1000)} ${c(_gz, 1000)} '
          '${c(_ax, 500)} ${c(_ay, 500)} ${c(_az, 500)}');
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

  void _press(int b) {
    setState(() {
      _pressed.add(b);
    });
    _send('press $b');
  }

  void _release(int b) {
    setState(() {
      _pressed.remove(b);
    });
    _send('release $b');
  }

  void _releaseAll() {
    setState(() {
      _pressed.clear();
    });
    for (var b = 1; b <= 25; b++) {
      _send('release $b');
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

  void _sendTrigger(String side) {
    final v = (side == 'left' ? _trigLeft : _trigRight).round();
    _send('trigger $side $v');
  }

  void _specialDown(String name) {
    setState(() {
      _specialsOn.add(name);
    });
    _send('special $name on');
  }

  void _specialUp(String name) {
    setState(() {
      _specialsOn.remove(name);
    });
    _send('special $name off');
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
                      : 'SInput Controller',
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
                Row(
                  children: [
                    const Expanded(
                      child: _SectionHeader(
                        title: 'Buttons',
                        wire: 'press <1..25>',
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
                    crossAxisCount: 5,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    mainAxisExtent: 64,
                  ),
                  itemCount: 25,
                  itemBuilder: (context, i) {
                    final b = i + 1;
                    final down = _pressed.contains(b);
                    return Listener(
                      key: ValueKey('button-$b'),
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: connected ? (_) => _press(b) : null,
                      onPointerUp: (_) => _release(b),
                      onPointerCancel: (_) => _release(b),
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
                          '$b',
                          style: TextStyle(
                            fontSize: 22,
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
                  wire: 'trigger <left|right> <v>',
                ),
                _TriggerRow(
                  rowKey: 'trigger-left',
                  label: 'LT',
                  value: _trigLeft,
                  enabled: connected,
                  onChanged: (v) => setState(() => _trigLeft = v),
                  onChangeEnd: () => _sendTrigger('left'),
                ),
                _TriggerRow(
                  rowKey: 'trigger-right',
                  label: 'RT',
                  value: _trigRight,
                  enabled: connected,
                  onChanged: (v) => setState(() => _trigRight = v),
                  onChangeEnd: () => _sendTrigger('right'),
                ),
                _SectionHeader(
                  title: 'Hat',
                  wire: 'hat <0..8> (now $_hat)',
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
                              _HatCell(
                                value: _hatGrid[r * 3 + c],
                                selected: _hat == _hatGrid[r * 3 + c],
                                enabled: connected,
                                onDown: (v) {
                                  setState(() => _hat = v);
                                  _send('hat $v');
                                },
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                const _SectionHeader(
                  title: 'Special',
                  wire: 'special <start|select|home> <on|off>',
                ),
                Row(
                  children: [
                    for (final name in _specials)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Listener(
                            key: ValueKey('special-$name'),
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: connected
                                ? (_) => _specialDown(name)
                                : null,
                            onPointerUp: (_) => _specialUp(name),
                            onPointerCancel: (_) => _specialUp(name),
                            child: Container(
                              height: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _specialsOn.contains(name)
                                    ? scheme.primaryContainer
                                    : scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _specialsOn.contains(name)
                                      ? scheme.primary
                                      : scheme.outlineVariant,
                                ),
                              ),
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _specialsOn.contains(name)
                                      ? scheme.onPrimaryContainer
                                      : scheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const _SectionHeader(
                  title: 'Motion',
                  wire: 'motion <gx> <gy> <gz> <ax> <ay> <az> @10Hz',
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

class _HatCell extends StatelessWidget {
  final int value;
  final bool selected;
  final bool enabled;
  final void Function(int) onDown;
  const _HatCell({
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
        key: ValueKey('hat-$value'),
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
            _hatGlyphs[value]!,
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
