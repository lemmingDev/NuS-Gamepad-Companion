---
description: Build debug APK, install to the wireless phone, launch the app.
---

In `C:\Users\PPSHS VR\Downloads\NuS-Gamepad-Companion`:
1. `flutter build apk --debug`.
2. Copy `build\app\outputs\flutter-apk\app-debug.apk` to
   `C:\Users\PPSHSV~1\AppData\Local\Temp\opencode\app-debug.apk` (space-free;
   `flutter run`/`adb install` choke on the space in `PPSHS VR`).
3. `adb install -r` that copy. If streamed install fails with an empty error,
   fall back to `adb push` to `/data/local/tmp/` + `adb shell pm install -r`
   (reliable for the ~150-190MB APK over WiFi).
4. `adb shell am start -n dev.nuscompanion.nus_gamepad_companion/.MainActivity`.
5. If `adb devices` is empty, stop and ask the user to re-establish wireless
   debugging (fresh IP/port or pairing code) — do not guess ports.
