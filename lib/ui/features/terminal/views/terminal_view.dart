import 'package:flutter/material.dart';

import '../../../../ble/nus_client.dart';
import '../../../../protocol/messages.dart';
import '../../../../protocol/profiles.dart';
import '../../../composite_dualsense_screen.dart';
import '../../../composite_xbox_screen.dart';
import '../../../controller_screen.dart';
import '../../../host_status_strip.dart';
import '../../../sinput_screen.dart';
import '../../../xinput_screen.dart';
import '../view_models/terminal_view_model.dart';

/// Lean terminal view: layout + [ListenableBuilder] on [TerminalViewModel].
class TerminalView extends StatefulWidget {
  final TerminalViewModel viewModel;
  const TerminalView({super.key, required this.viewModel});

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  int _lastLogLength = 0;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Color _colorFor(BuildContext context, LogEntry e) {
    final scheme = Theme.of(context).colorScheme;
    if (e.outgoing) return scheme.onSurfaceVariant;
    final m = e.message;
    if (m is ErrMessage) return scheme.error;
    if (m is OkMessage) return Colors.green;
    if (m is EventMessage) return Colors.orange;
    if (m is StateMessage) return Colors.lightBlue;
    if (m is HelloMessage || m is ProtoMessage) return Colors.teal;
    return scheme.onSurface;
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    await widget.viewModel.sendLine(text);
  }

  static String _ts(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final profile = profileForId(vm.activeProfileId);

        if (vm.log.length != _lastLogLength) {
          _lastLogLength = vm.log.length;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients) {
              _scroll.jumpTo(_scroll.position.maxScrollExtent);
            }
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 12,
                      color: vm.connected ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        vm.deviceLabel.isNotEmpty ? vm.deviceLabel : 'Terminal',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Text(
                  profile.label,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Controller',
                icon: const Icon(Icons.gamepad),
                onPressed: (vm.connected &&
                        (isGenericControllerProfile(vm.activeProfileId) ||
                            isSinputControllerProfile(vm.activeProfileId) ||
                            isXinputControllerProfile(vm.activeProfileId) ||
                            isCompositeXboxProfile(vm.activeProfileId) ||
                            isCompositeDualsenseProfile(vm.activeProfileId)))
                    ? () {
                        final id = vm.activeProfileId;
                        final shim = NusClient.fromRepository(vm.repository);
                        final dest = isCompositeXboxProfile(id)
                            ? CompositeXboxScreen(client: shim)
                            : isCompositeDualsenseProfile(id)
                                ? CompositeDualsenseScreen(client: shim)
                                : isSinputControllerProfile(id)
                                    ? SinputScreen(client: shim)
                                    : isXinputControllerProfile(id)
                                        ? XinputScreen(client: shim)
                                        : ControllerScreen(client: shim);
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => dest),
                        );
                      }
                    : null,
              ),
              PopupMenuButton<String>(
                tooltip: 'Command profile',
                onSelected: (id) => vm.setProfileOverride(id),
                itemBuilder: (_) => [
                  for (final p in kProfiles)
                    PopupMenuItem(value: p.id, child: Text(p.label)),
                ],
              ),
              PopupMenuButton<String>(
                tooltip: 'Terminal options',
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  if (v == 'clear') {
                    vm.setClearLogOnConnect(!vm.clearLogOnConnect);
                  } else if (v == 'stamps') {
                    vm.setShowTimestamps(!vm.showTimestamps);
                  } else if (v == 'vibrate') {
                    vm.setVibrateOnRumble(!vm.vibrateOnRumble);
                  }
                },
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                    value: 'clear',
                    checked: vm.clearLogOnConnect,
                    child: const Text('Clear log on connect'),
                  ),
                  CheckedPopupMenuItem(
                    value: 'stamps',
                    checked: vm.showTimestamps,
                    child: const Text('Show timestamps'),
                  ),
                  CheckedPopupMenuItem(
                    value: 'vibrate',
                    checked: vm.vibrateOnRumble,
                    child: const Text('Vibrate on rumble'),
                  ),
                ],
              ),
              IconButton(
                tooltip: 'Clear log',
                icon: const Icon(Icons.clear_all),
                onPressed: vm.clearLog,
              ),
              IconButton(
                tooltip: 'Disconnect',
                icon: const Icon(Icons.bluetooth_disabled),
                onPressed: () async {
                  await vm.disconnect();
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    profile.hint,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: HostStatusStrip(
                    ledIndex: vm.lastLedIndex,
                    rgb: vm.lastRgb,
                  ),
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    for (final m in profile.macros)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          label: Text(m.label),
                          onPressed:
                              vm.connected ? () => vm.sendLine(m.command) : null,
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: vm.log.isEmpty
                    ? const Center(child: Text('No traffic yet — send `help`.'))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(8),
                        itemCount: vm.log.length,
                        itemBuilder: (context, i) {
                          final e = vm.log[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Text(
                              '${vm.showTimestamps ? '${_ts(e.time)} ' : ''}'
                              '${e.outgoing ? '> ' : ''}${e.message.display}',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                color: _colorFor(context, e),
                                fontStyle: e.outgoing
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        decoration: const InputDecoration(
                          hintText: 'help',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Send',
                      icon: const Icon(Icons.send),
                      onPressed: vm.connected ? _send : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
