/// Parsed view of one `\n`-terminated line from the firmware.
/// Mirrors the shared vocabulary documented in the firmware examples:
/// `hello` / `proto` / `ok` / `err` / `event …` / `state …`, anything else
/// is informational free text.
sealed class NuSMessage {
  const NuSMessage();
  String get display;
}

/// Any line that matches no other shape (greetings, status dumps, echo…).
class InfoMessage extends NuSMessage {
  final String text;
  const InfoMessage(this.text);
  @override
  String get display => text;
}

/// `hello <profile-id> <proto-ver>` — pushed on NUS subscribe.
class HelloMessage extends NuSMessage {
  final String profileId;
  final int protoVer;
  const HelloMessage(this.profileId, this.protoVer);
  @override
  String get display => 'hello $profileId $protoVer';
}

/// `proto <profile-id> <proto-ver>` — reply to the `proto?` command.
class ProtoMessage extends NuSMessage {
  final String profileId;
  final int protoVer;
  const ProtoMessage(this.profileId, this.protoVer);
  @override
  String get display => 'proto $profileId $protoVer';
}

/// `ok` / `ok <detail>` — command accepted.
class OkMessage extends NuSMessage {
  final String detail;
  const OkMessage([this.detail = '']);
  @override
  String get display => detail.isEmpty ? 'ok' : 'ok $detail';
}

/// `err` / `err <detail>` — command rejected.
class ErrMessage extends NuSMessage {
  final String detail;
  const ErrMessage([this.detail = '']);
  @override
  String get display => detail.isEmpty ? 'err' : 'err $detail';
}

/// `event <name> <rest>` — unsolicited push (rumble, led, state…).
class EventMessage extends NuSMessage {
  final String name;
  final String rest;
  const EventMessage(this.name, [this.rest = '']);
  @override
  String get display => rest.isEmpty ? 'event $name' : 'event $name $rest';
}

/// `state <rest>` — periodic state summary.
class StateMessage extends NuSMessage {
  final String rest;
  const StateMessage([this.rest = '']);
  @override
  String get display => rest.isEmpty ? 'state' : 'state $rest';
}
