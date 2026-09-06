/// Command profiles: macro buttons per known firmware sketch, keyed by the
/// profile IDs the sketches greet with (`hello <id> 1` / `proto?`).
/// Adding support for new firmware (e.g. a NuS-capable CompositeHID sketch)
/// is a data entry here — no app code changes.
library;

class MacroButton {
  final String label;
  final String command;
  const MacroButton(this.label, this.command);
}

class DeviceProfile {
  final String id;
  final String label;
  final String hint;
  final List<MacroButton> macros;
  const DeviceProfile({
    required this.id,
    required this.label,
    required this.hint,
    required this.macros,
  });
}

const _commonMacros = [
  MacroButton('help', 'help'),
  MacroButton('proto?', 'proto?'),
  MacroButton('status', 'status'),
];

const List<DeviceProfile> kProfiles = [
  DeviceProfile(
    id: 'generic',
    label: 'Generic NUS terminal',
    hint: 'Fallback console for any Nordic UART peripheral. No assumed commands.',
    macros: _commonMacros,
  ),
  DeviceProfile(
    id: 'nus-diag',
    label: 'NuSSerialDiag',
    hint: 'Diagnostics: auto-press, echo, proactive status lines.',
    macros: [
      ..._commonMacros,
      MacroButton('button4', 'button4'),
    ],
  ),
  DeviceProfile(
    id: 'nus-bridge/generic-strict',
    label: 'Generic bridge (strict)',
    hint: '16 buttons, 8 axes, 1 hat, battery, power, bond/TX management.',
    macros: _commonMacros,
  ),
  DeviceProfile(
    id: 'nus-bridge/generic-advanced',
    label: 'Generic bridge (advanced)',
    hint: 'Strict set plus start/select specials and HID output/feature reports.',
    macros: [
      ..._commonMacros,
      MacroButton('output?', 'output?'),
      MacroButton('feature get', 'feature get'),
    ],
  ),
  DeviceProfile(
    id: 'nus-bridge/sinput',
    label: 'SInput bridge',
    hint: 'SInput pad plus host LED/rumble/RGB queries.',
    macros: [
      ..._commonMacros,
      MacroButton('led?', 'led?'),
      MacroButton('rumble?', 'rumble?'),
      MacroButton('rgb?', 'rgb?'),
    ],
  ),
  DeviceProfile(
    id: 'nus-bridge/xinput',
    label: 'XInput bridge',
    hint: 'Xbox pad plus host rumble query.',
    macros: [
      ..._commonMacros,
      MacroButton('rumble?', 'rumble?'),
    ],
  ),
  DeviceProfile(
    id: 'nus-bridge/composite-generic',
    label: 'CompositeHID Generic bridge',
    hint: 'CompositeHID generic pad plus player-LED query.',
    macros: [
      ..._commonMacros,
      MacroButton('playerled?', 'playerled?'),
    ],
  ),
  DeviceProfile(
    id: 'nus-bridge/composite-xbox',
    label: 'CompositeHID Xbox bridge',
    hint: 'CompositeHID Xbox pad plus host rumble query.',
    macros: [
      ..._commonMacros,
      MacroButton('rumble?', 'rumble?'),
    ],
  ),
  DeviceProfile(
    id: 'nus-bridge/composite-dualsense',
    label: 'CompositeHID DualSense bridge',
    hint: 'DualSense Edge plus rumble/LED/lightbar/trigger queries.',
    macros: [
      ..._commonMacros,
      MacroButton('rumble?', 'rumble?'),
      MacroButton('led?', 'led?'),
      MacroButton('lightbar?', 'lightbar?'),
      MacroButton('trigfx?', 'trigfx?'),
    ],
  ),
];

const DeviceProfile kFallbackProfile = DeviceProfile(
  id: 'generic',
  label: 'Generic NUS terminal',
  hint: 'Fallback console for any Nordic UART peripheral. No assumed commands.',
  macros: _commonMacros,
);

/// Returns the profile for a greeted `hello`/`proto` id, or the generic
/// fallback when unknown.
DeviceProfile profileForId(String? id) {
  if (id == null) {
    return kFallbackProfile;
  }
  for (final p in kProfiles) {
    if (p.id == id) {
      return p;
    }
  }
  return kFallbackProfile;
}
