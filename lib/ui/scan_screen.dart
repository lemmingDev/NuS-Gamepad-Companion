import 'package:flutter/material.dart';

import '../ble/nus_client.dart';
import 'features/scan/view_models/scan_view_model.dart';
import 'features/scan/views/scan_view.dart';

/// Legacy entry point kept for `main.dart` and existing tests.
///
/// Delegates to the layered [ScanView] + [ScanViewModel].  The facade
/// preserves the original `ScanScreen(client: NusClient)` constructor so
/// call sites need not migrate immediately; new code should inject
/// [ScanViewModel] directly.
class ScanScreen extends StatefulWidget {
  final NusClient client;
  const ScanScreen({super.key, required this.client});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late final ScanViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = ScanViewModel(repository: widget.client.repository);
  }

  @override
  void didUpdateWidget(covariant ScanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _viewModel.dispose();
      _viewModel = ScanViewModel(repository: widget.client.repository);
    }
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScanView(viewModel: _viewModel);
}
