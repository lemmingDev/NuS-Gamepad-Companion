import 'messages.dart';

final _helloRe = RegExp(r'^hello (\S+) (\d+)$');
final _protoRe = RegExp(r'^proto (\S+) (\d+)$');
final _eventRe = RegExp(r'^event (\S+)(?: (.*))?$');
final _stateRe = RegExp(r'^state(?: (.*))?$');

/// Parse one trimmed line into a [NuSMessage]. Never throws: unparseable
/// input (including empty lines) becomes [InfoMessage].
NuSMessage parseLine(String raw) {
  final line = raw.trim();
  if (line.isEmpty) {
    return const InfoMessage('');
  }
  var m = _helloRe.firstMatch(line);
  if (m != null) {
    return HelloMessage(m.group(1)!, int.parse(m.group(2)!));
  }
  m = _protoRe.firstMatch(line);
  if (m != null) {
    return ProtoMessage(m.group(1)!, int.parse(m.group(2)!));
  }
  if (line == 'ok') {
    return const OkMessage();
  }
  if (line.startsWith('ok ')) {
    return OkMessage(line.substring(3));
  }
  if (line == 'err') {
    return const ErrMessage();
  }
  if (line.startsWith('err ')) {
    return ErrMessage(line.substring(4));
  }
  m = _eventRe.firstMatch(line);
  if (m != null) {
    return EventMessage(m.group(1)!, m.group(2) ?? '');
  }
  m = _stateRe.firstMatch(line);
  if (m != null) {
    return StateMessage(m.group(1) ?? '');
  }
  return InfoMessage(line);
}
