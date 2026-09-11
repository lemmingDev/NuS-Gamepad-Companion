# NuS-Gamepad-Companion — agent conventions

Read this before doing anything in this repo. It encodes lessons that each
cost a live debugging session to learn.

## Verify by execution, in this order
`flutter analyze` (zero issues) → `flutter test` (all pass) → `flutter build
apk --debug` → install + screenshot-verify on hardware. Never claim a fix
works without the corresponding step. (`/verify`, `/ship`, `/shot`, `/flash`
commands encode the exact incantations.)

## Never push, never publish
Local commits are fine when asked. No `push`, no remotes/PRs, no releases,
no TestFlight — unless the user explicitly requests it.

## BLE / wire-contract facts (live-verified, do not regress)
- NUS UUIDs in `lib/ble/nus_uuids.dart`; UUID rides in the scan response.
- Scan is name-filtered (default `NuS`, matches `<Role>-NuS` aliases) with
  NUS-UUID badge/sort. Never UUID-only exclusion, never probe-connects.
- `proto?` is the reliable identity query (pushed `hello` can race CCCD).
- New firmware support = one entry in `lib/protocol/profiles.dart`.
- `flutter_blue_plus` stays version-pinned; `connect()` needs
  `license: License.nonprofit`.
- Android API ≤30: `BLUETOOTH_SCAN`/`CONNECT` don't exist (location is the
  sole runtime permission); classic `BLUETOOTH`/`BLUETOOTH_ADMIN`
  (`maxSdkVersion 30`) are mandatory or every adapter call throws
  `SecurityException`.
- `NusClient` invariants: `_teardownLink()` before every (re)connect,
  `_setupLink()` shared with auto-reconnect, explicit unsubscribe on
  `disconnect()`, continuous scan with 2-min watchdog, one connect retry.

## Environment gotchas
- Project path contains a space (`PPSHS VR`): never `flutter run` install or
  `adb install` from it — stage the APK under
  `C:\Users\PPSHSV~1\AppData\Local\Temp\opencode\` first (or push + `pm install`
  for ~150MB+ APKs over WiFi).
- `adb exec-out screencap` must go through `cmd /c` (PowerShell `>` corrupts
  binary); downscale to 480px JPEG before reading.
- Wireless ADB drops every ~20-40 min and ports rotate; the remembered TLS
  pairing usually survives (mDNS entry), pairing ports are single-use.
- COM port re-enumerates (COM5/COM6); always re-check before flashing.
- Opening a serial port resets the ESP32 — captures destroy the state they
  observe; coordinate or account for the reboot.
- The installed Arduino library
  (`%USERPROFILE%\Documents\Arduino\libraries\ESP32-BLE-Gamepad.bak`) may not
  match any repo HEAD — verify before trusting a build (this exact mismatch
  cost a full SInput driver-error hunt).
