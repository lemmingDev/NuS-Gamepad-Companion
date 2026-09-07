# NuS-Gamepad-Companion

Flutter companion app for NUS-enabled ESP32 gamepad firmware: scan, connect
over Nordic UART, and drive the device from a serial terminal with
per-firmware command macros. Android-first; iOS builds as a smoke check
(TestFlight packaging later).

## Firmware contract

Any peripheral exposing the Nordic UART Service works:

- Service `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`, RX `…-0002` (WRITE),
  TX `…-0003` (notify). The app scans by device **name** (default filter
  `NuS`): boards advertise short `<Role>-NuS` aliases, and the NUS UUID
  itself rides in the scan response — advertisers get an NUS badge and sort
  first, but name matching stays the default since scan responses aren't
  always captured.
- Lines are `\n`-terminated; the app chunks writes to the negotiated MTU.
- Sketches that greet `hello <profile-id> 1` get their macro set
  auto-selected (`proto?` re-queries it). Unknown lines render as-is.

On-air aliases (all ≤11 chars, verified live on hardware):

| Sketch | Alias | Profile ID |
|--------|-------|------------|
| NuSSerialDiag | `Diag-NuS` | `nus-diag` |
| NuSGenericBridge | `Generic-NuS` | `nus-bridge/generic-strict` |
| NuSGenericAdvanced | `GenAdv-NuS` | `nus-bridge/generic-advanced` |
| NuSSInputBridge | `SInput-NuS` | `nus-bridge/sinput` |
| NuSXInputBridge | `XInput-NuS` | `nus-bridge/xinput` |

Tested against [`ESP32-BLE-Gamepad`](https://github.com/lemmingDev/ESP32-BLE-Gamepad)
`examples/NuS/*` (Generic strict/advanced, SInput, XInput, Diagnostics) and
ready for NuS-capable
[`ESP32-BLE-CompositeHID`](https://github.com/Mystfit/ESP32-BLE-CompositeHID)
sketches. Adding a firmware = one entry in `lib/protocol/profiles.dart`.

## Project status: v0.1 terminal

- [x] Scan (name filter), connect, auto-reconnect (3 tries)
- [x] Terminal: color-coded log, input, macro chips, manual profile override
- [x] Unit-tested line parser (`flutter test`)
- [ ] Controller UI (v0.2): on-screen pad driving bridge commands
- [ ] iOS distribution via TestFlight (builds unsigned in CI today)

## Build & install

See [SETUP.md](SETUP.md). Short version: `flutter create` the platform
shells, overlay this repo's files, `flutter run`. CI builds a debug APK
artifact on every push (download from the Actions run, tap to install).

## License

MIT (this app). It talks to [NuS-NimBLE-Serial](https://github.com/afpineda/NuS-NimBLE-Serial)
(CC BY 4.0, © Ángel Fernández Pineda) firmware-side; that license covers the
firmware library, not this app.
