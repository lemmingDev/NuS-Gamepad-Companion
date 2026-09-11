---
description: Compile and flash an ESP32 sketch to the CH340 board (COM port auto-detected).
---

Sketch name comes from `$ARGUMENTS` (a directory under either
`C:\Users\PPSHS VR\Downloads\ESP32-BLE-Gamepad\examples\NuS\` or an absolute
sketch path). Steps:
1. Find the board: `Get-PnpDevice` for `CH340|CP210|USB-SERIAL` (note: the COM
   number re-enumerates between operations — always re-check, never assume).
2. CLI (not on PATH):
   `C:\Program Files\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe`.
3. `compile --fqbn esp32:esp32:esp32 <sketch>` then `upload -p COMx --fqbn
   esp32:esp32:esp32 <sketch>`. Report the byte counts and the hash-verified
   line. The installed library is `%USERPROFILE%\Documents\Arduino\libraries\ESP32-BLE-Gamepad.bak`
   — remember it may not match any repo HEAD (check before trusting a build).
