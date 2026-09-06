import 'package:flutter/material.dart';

import '../ble/nus_client.dart';
import '../protocol/messages.dart';
import '../protocol/profiles.dart';

/// NUS console: color-coded log, command input, macro chips for the active
/// device profile (auto-selected from the sketch's `hello` line, overridable).
class TerminalScreen extends StatefulWidget {
  final NusClient client;
  const TerminalScreen({super.key, required this.client});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
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
    if (e.outgoing) {
      return scheme.onSurfaceVariant;
    }
    final m = e.message;
    if (m is ErrMessage) {
      return scheme.error;
    }
    if (m is OkMessage) {
      return Colors.green;
    }
    if (m is EventMessage) {
      return Colors.orange;
    }
    if (m is StateMessage) {
      return Colors.lightBlue;
    }
    if (m is HelloMessage || m is ProtoMessage) {
      return Colors.teal;
    }
    return scheme.onSurface;
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) {
      return;
    }
    _input.clear();
    await widget.client.sendLine(text);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.client,
      builder: (context, _) {
        final client = widget.client;
        final profile = profileForId(client.activeProfileId);

        if (client.log.length != _lastLogLength) {
          _lastLogLength = client.log.length;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients) {
              _scroll.jumpTo(_scroll.position.maxScrollExtent);
            }
          });
        }

        final connected = client.state == NusConnState.ready;
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
                      color: connected ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        client.deviceLabel.isNotEmpty ? client.deviceLabel : 'Terminal',
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
              PopupMenuButton<String>(
                tooltip: 'Command profile',
                onSelected: (id) => client.setProfileOverride(id),
                itemBuilder: (_) => [
                  for (final p in kProfiles)
                    PopupMenuItem(
                      value: p.id,
                      child: Text(p.label),
                    ),
                ],
              ),
              IconButton(
                tooltip: 'Clear log',
                icon: const Icon(Icons.clear_all),
                onPressed: client.clearLog,
              ),
              IconButton(
                tooltip: 'Disconnect',
                icon: const Icon(Icons.bluetooth_disabled),
                onPressed: () async {
                  await client.disconnect();
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
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
                  child: Text(profile.hint, style: Theme.of(context).textTheme.labelSmall),
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
                          onPressed: connected ? () => client.sendLine(m.command) : null,
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: client.log.isEmpty
                    ? const Center(child: Text('No traffic yet — send `help`.'))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(8),
                        itemCount: client.log.length,
                        itemBuilder: (context, i) {
                          final e = client.log[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Text(
                              '${e.outgoing ? '> ' : ''}${e.message.display}',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                color: _colorFor(context, e),
                                fontStyle: e.outgoing ? FontStyle.italic : FontStyle.normal,
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
                      onPressed: connected ? _send : null,
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
