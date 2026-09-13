import 'package:flutter/material.dart';

import '../ble/nus_client.dart';
import 'features/terminal/view_models/terminal_view_model.dart';
import 'features/terminal/views/terminal_view.dart';

/// Legacy terminal entry point.
///
/// Wraps the lean [TerminalView] + [TerminalViewModel] so existing
/// `TerminalScreen(client: NusClient)` call sites remain green.
class TerminalScreen extends StatefulWidget {
  final NusClient client;
  const TerminalScreen({super.key, required this.client});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final TerminalViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = TerminalViewModel(repository: widget.client.repository);
  }

  @override
  void didUpdateWidget(covariant TerminalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _viewModel.dispose();
      _viewModel = TerminalViewModel(repository: widget.client.repository);
    }
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TerminalView(viewModel: _viewModel);
}
