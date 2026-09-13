import '../../protocol/messages.dart';

/// One row in the terminal log.
class LogEntry {
  final DateTime time;
  final NuSMessage message;
  final bool outgoing;
  LogEntry(this.message, {this.outgoing = false}) : time = DateTime.now();
}
