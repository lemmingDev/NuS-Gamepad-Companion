import 'dart:async';

import 'package:flutter/material.dart';

import '../ble/nus_client.dart';
import '../protocol/profiles.dart';

/// Profile ids whose firmware speaks the generic bridge wire syntax
/// (`press`/`release`/`axis`/`hat`, see the NuSGenericBridge sketch).
const kGenericControllerProfiles = {
  'nus-bridge/generic-strict',
  'nus-bridge/generic-advanced',
};

/// True when [id] resolves (via [profileForId]) to a generic bridge profile.
bool isGenericControllerProfile(String? id) =>
    kGenericControllerProfiles.contains(profileForId(id).id);

/// Axis names in wire order, value range -32768..32767.
const _axisNames = ['x', 'y', 'z', 'rx', 'ry', 'rz', 's1', 's2'];
const _axisMin = -32768.0;
const _axisMax = 32767.0;

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

/// On-screen generic gamepad: 16 buttons, 8 axes, 1 hat.
///
/// Drives bridge commands through [NusClient.sendLine]. Pointer handlers fire
/// without awaiting so touch latency stays minimal.
class ControllerScreen extends StatefulWidget {
  final NusClient client;
  const ControllerScreen({super.key, required this.client});

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  final Set<int> _pressed = {};
  final Map<String, double> _axes = {for (final a in _axisNames) a: 0};
  int _hat = 0;

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
    for (var b = 1; b <= 16; b++) {
      _send('release $b');
    }
  }

  void _sendAxis(String name) {
    _send('axis $name ${_axes[name]!.round()}');
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
                      : 'Controller',
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
                        wire: 'press <1..16>',
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
                  itemCount: 16,
                  itemBuilder: (context, i) {
                    final b = i + 1;
                    final down = _pressed.contains(b);
                    return Listener(
                      key: ValueKey('button-$b'),
                      behavior: HitTestBehavior.opaque,
                      onPointerDown:
                          connected ? (_) => _press(b) : null,
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
                const _SectionHeader(title: 'Axes', wire: 'axis <name> <v>'),
                for (final name in _axisNames)
                  Row(
                    key: ValueKey('axis-$name'),
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          name,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          min: _axisMin,
                          max: _axisMax,
                          divisions: 256,
                          value: _axes[name]!,
                          label: '${_axes[name]!.round()}',
                          // Latency matters less here than BLE flooding:
                          // local echo while dragging, one line on release.
                          onChanged: connected
                              ? (v) => setState(() => _axes[name] = v)
                              : null,
                          onChangeEnd:
                              connected ? (_) => _sendAxis(name) : null,
                        ),
                      ),
                      SizedBox(
                        width: 60,
                        child: Text(
                          '${_axes[name]!.round()}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Center $name',
                        icon: const Icon(Icons.center_focus_weak),
                        onPressed: connected
                            ? () {
                                setState(() => _axes[name] = 0);
                                _send('axis $name 0');
                              }
                            : null,
                      ),
                    ],
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
              color:
                  selected ? scheme.onPrimaryContainer : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
