import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/nus_client.dart';
import 'terminal_screen.dart';

/// Scan for NUS peripherals, connect, hand off to the terminal.
///
/// Devices are filtered by advertised NAME (default `ESP32`): our firmware
/// carries the NUS service UUID in the scan response (the 31-byte adv packet
/// itself is full), so service-UUID filtering only works on active scanners
/// while name matching works everywhere. Toggle "show all" to see everything.
class ScanScreen extends StatefulWidget {
  final NusClient client;
  const ScanScreen({super.key, required this.client});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final TextEditingController _filter = TextEditingController(text: 'ESP32');
  bool _showAll = false;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _toggleScan() async {
    if (widget.client.state == NusConnState.scanning) {
      await widget.client.stopScan();
      return;
    }
    final ok = await widget.client.ensurePermissions();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bluetooth scan/connect permission denied.')),
      );
      return;
    }
    await widget.client.startScan();
  }

  Future<void> _connectAndOpen(BluetoothDevice device) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await widget.client.connect(device);
    } catch (_) {
      // client.errorText carries the reason.
    }
    if (!mounted) {
      return;
    }
    nav.pop();
    if (widget.client.state == NusConnState.ready) {
      await nav.push(
        MaterialPageRoute(builder: (_) => TerminalScreen(client: widget.client)),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(widget.client.errorText ?? 'Connect failed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NuS Gamepad Companion')),
      body: Column(
        children: [
          StreamBuilder<BluetoothAdapterState>(
            stream: widget.client.adapterState,
            initialData: BluetoothAdapterState.unknown,
            builder: (context, snap) {
              if (snap.data == BluetoothAdapterState.on) {
                return const SizedBox.shrink();
              }
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Theme.of(context).colorScheme.errorContainer,
                child: const Text(
                  'Bluetooth is off — enable it to scan.',
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _filter,
                    decoration: const InputDecoration(
                      labelText: 'Name filter',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('All'),
                Switch(
                  value: _showAll,
                  onChanged: (v) => setState(() => _showAll = v),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: ListenableBuilder(
                    listenable: widget.client,
                    builder: (context, _) {
                      final scanning =
                          widget.client.state == NusConnState.scanning;
                      return FilledButton.icon(
                        onPressed: _toggleScan,
                        icon: Icon(scanning ? Icons.stop : Icons.bluetooth_searching),
                        label: Text(scanning ? 'Stop scan' : 'Scan'),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              'No system pairing needed — the app talks GATT directly. '
              'Pairing in Android Settings would bond the HID gamepad instead.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.client,
              builder: (context, _) {
                final q = _filter.text.toLowerCase();
                final results = widget.client.scanResults.where((r) {
                  if (_showAll) {
                    return true;
                  }
                  final name = r.advertisementData.advName.toLowerCase();
                  return name.contains(q);
                }).toList();
                if (results.isEmpty) {
                  return const Center(child: Text('No devices yet — hit Scan.'));
                }
                return ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, i) {
                    final r = results[i];
                    final name = r.advertisementData.advName.isNotEmpty
                        ? r.advertisementData.advName
                        : '(unnamed)';
                    return ListTile(
                      leading: const Icon(Icons.bluetooth),
                      title: Text(name),
                      subtitle: Text('${r.device.remoteId.str} · ${r.rssi} dBm'),
                      onTap: () => _connectAndOpen(r.device),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
