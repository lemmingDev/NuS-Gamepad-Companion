import 'dart:async';

import 'package:flutter/material.dart';

import '../ble/nus_client.dart';
import '../protocol/profiles.dart';

/// Profile ids whose firmware speaks the CompositeHID Xbox bridge wire syntax
/// (`press`/`release`/`stick`/`trigger`/`dpad`/`share`,
/// see the NuSXboxBridge sketch).
const kCompositeXboxProfiles = {
  'nus-bridge/composite-xbox',
};

/// True when [id] resolves (via [profileForId]) to a CompositeHID Xbox
/// bridge profile.
bool isCompositeXboxProfile(String? id) =>
    kCompositeXboxProfiles.contains(profileForId(id).id);

/// Button names in pad order with their display labels.
const _buttonNames = [
  'a',
  'b',
  'x',
  'y',
  'lb',
  'rb',
  'select',
  'start',
  'home',
  'ls',
  'rs',
];

const _buttonLabels = {
  'a': 'A',
  'b': 'B',
  'x': 'X',
  'y': 'Y',
  'lb': 'LB',
  'rb': 'RB',
  'select': 'Select',
  'start': 'Start',
  'home': 'Home',
  'ls': 'LS',
  'rs': 'RS',
};

const _stickMin = -32768.0;
const _stickMax = 32767.0;
const _trigMin = 0.0;
const _trigMax = 1023.0;

/// Dpad values in 3x3 grid order (row-major: [8,1,2 / 7,0,3 / 6,5,4]).
/// Wire order: 0=none 1=north 2=northeast 3=east 4=southeast 5=south
/// 6=southwest 7=west 8=northwest.
const _dpadGrid = [8, 1, 2, 7, 0, 3, 6, 5, 4];
const _dpadGlyphs = {
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

/// On-screen CompositeHID Xbox gamepad: 11 named buttons, 2 sticks, combined
/// L+R triggers, 1 dpad, share hold-pad.
///
/// Battery macros stay terminal-only. Drives bridge commands through
/// [NusClient.sendLine]. Pointer handlers fire without awaiting so touch
/// latency stays minimal.
class CompositeXboxScreen extends StatefulWidget {
  final NusClient client;
  const CompositeXboxScreen({super.key, required this.client});

  @override
  State<CompositeXboxScreen> createState() => _CompositeXboxScreenState();
}

class _CompositeXboxScreenState extends State<CompositeXboxScreen> {
  final Set<String> _pressed = {};
  bool _shareOn = false;
  double _leftX = 0;
  double _leftY = 0;
  double _rightX = 0;
  double _rightY = 0;
  double _trigL = 0;
  double _trigR = 0;
  int _dpad = 0;

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

  /// Composite Xbox takes BOTH trigger values in one command.
  void _sendTriggers() {
    _send('trigger ${_trigL.round()} ${_trigR.round()}');
  }

  void _shareDown() {
    setState(() {
      _shareOn = true;
    });
    _send('share on');
  }

  void _shareUp() {
    setState(() {
      _shareOn = false;
    });
    _send('share off');
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
                      : 'Xbox Controller',
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
                            fontSize: 20,
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
                  title: 'Share',
                  wire: 'share <on|off>',
                ),
                Listener(
                  key: const ValueKey('share'),
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: connected ? (_) => _shareDown() : null,
                  onPointerUp: (_) => _shareUp(),
                  onPointerCancel: (_) => _shareUp(),
                  child: Container(
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _shareOn
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _shareOn
                            ? scheme.primary
                            : scheme.outlineVariant,
                      ),
                    ),
                    child: Text(
                      'share',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _shareOn
                            ? scheme.onPrimaryContainer
                            : scheme.onSurface,
                      ),
                    ),
                  ),
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
