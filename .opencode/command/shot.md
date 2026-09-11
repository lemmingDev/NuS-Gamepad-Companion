---
description: Screenshot the phone over ADB, downscale, and inspect it.
---

1. Capture with `cmd /c` (NOT PowerShell redirect, which mangles binary):
   `cmd /c "adb exec-out screencap -p > C:\Users\PPSHSV~1\AppData\Local\Temp\opencode\shot.png"`.
2. Downscale to 480px wide JPEG via System.Drawing into the same temp dir.
3. Read the JPEG with the Read tool and describe what is on screen
   (banner state, lists, values) relative to the task at hand.
