import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../../../ble/nus_uuids.dart';
import '../../../../domain/models/connection_state.dart';
import '../view_models/scan_view_model.dart';
import '../../terminal/views/terminal_view.dart';
import '../../terminal/view_models/terminal_view_model.dart';

/// Lean scan view: layout + [ListenableBuilder] on [ScanViewModel].
///
/// All filtering, sorting, and BLE commands live in the ViewModel /
/// Repository.  This widget only handles UI chrome (filter field, NUS badge,
/// navigation to terminal).
class ScanView extends StatefulWidget {
  final ScanViewModel viewModel;
  const ScanView({super.key, required this.viewModel});

  @override
  State<ScanView> createState() => _ScanViewState();
}

class _ScanViewState extends State<ScanView> {
  late final TextEditingController _filter;

  @override
  void initState() {
    super.initState();
    _filter = TextEditingController(text: widget.viewModel.filter);
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _toggleScan() async {
    if (widget.viewModel.scanning) {
      await widget.viewModel.repository.stopScan();
      return;
    }
    final ok = await widget.viewModel.ensurePermissions();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bluetooth scan/connect permission denied.')),
      );
      return;
    }
    try {
      await widget.viewModel.repository.startScan();
    } catch (e) {
      widget.viewModel.repository.errorText = e.toString();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e')),
        );
      }
    }
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
      await widget.viewModel.connect(device);
    } catch (_) {
      // viewModel.repository.errorText carries the reason.
    }
    if (!mounted) return;
    nav.pop();
    if (widget.viewModel.repository.state == NusConnState.ready) {
      final terminalVm = TerminalViewModel(
        repository: widget.viewModel.repository,
      );
      await nav.push(
        MaterialPageRoute(builder: (_) => TerminalView(viewModel: terminalVm)),
      );
      // TerminalView owns its ViewModel lifecycle only for this push;
      // dispose after pop to avoid leaking listeners.
      terminalVm.dispose();
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.viewModel.errorText ?? 'Connect failed.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    return Scaffold(
      appBar: AppBar(title: const Text('NuS Gamepad Companion')),
      body: Column(
        children: [
          StreamBuilder<BluetoothAdapterState>(
            stream: vm.adapterState,
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
                    onChanged: (v) => vm.setFilter(v),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('All'),
                ListenableBuilder(
                  listenable: vm,
                  builder: (context, _) => Switch(
                    value: vm.showAll,
                    onChanged: (v) => vm.setShowAll(v),
                  ),
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
                    listenable: vm,
                    builder: (context, _) {
                      final scanning = vm.scanning;
                      return FilledButton.icon(
                        onPressed: _toggleScan,
                        icon: Icon(
                          scanning ? Icons.stop : Icons.bluetooth_searching,
                        ),
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
              listenable: vm,
              builder: (context, _) {
                final results = vm.filteredResults;
                bool hasNus(ScanResult r) =>
                    r.advertisementData.serviceUuids.any(
                      (u) =>
                          u.str.toLowerCase() ==
                          nusServiceUuid.str.toLowerCase(),
                    );
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
                    final nus = hasNus(r);
                    return ListTile(
                      leading: Icon(
                        Icons.bluetooth,
                        color: nus ? Colors.tealAccent : null,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(name, overflow: TextOverflow.ellipsis),
                          ),
                          if (nus)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Chip(
                                label: Text('NUS'),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                            ),
                        ],
                      ),
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
