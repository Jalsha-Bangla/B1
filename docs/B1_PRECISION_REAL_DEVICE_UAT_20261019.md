# B1 Precision HID — Real Device UAT / Regression Log

Date: 2026-10-19 (+06:00)
Test phone: vivo V30 Lite
Target: B1 / HiMedia / BingeStick Android TV 9
Transport: Android Bluetooth HID Device → B1 HID Host
Build tested: v1.2.0 HID registration recovery test
Evidence: user screenshots of B1 Remotes & Accessories = vivo V30 Lite Connected and phone app HID_CONNECTED_TO_B1 green indicator; hands-on verbal UAT.

## Real-device PASS (user-reported)

- Phone paired with B1 and HID_CONNECTED_TO_B1, green indicator
- D-Pad four directions and OK functional
- YouTube navigation / arrows / OK functional
- TV keyboard control functional
- Android hardware volume up/down controls B1 volume
- App volume up/down and mute functional
- Home button works
- Swipe mode navigation works; user reports smooth and usable
- Gyro mouse cursor appears and moves on YouTube
- Gyro single tap selects on YouTube; double tap triggers Back
- Bluetooth controls function with Wi-Fi OFF

## Observed regressions / incomplete acceptance

- Back button sometimes fails specifically in Android Settings; YouTube Back works
- No perceptible vibration/haptic feedback
- Gyro movement sensitivity/calibration needs improvement; excessive phone tilting
- Gyro select works in YouTube, not consistently on B1 Home launcher
- After phone screen lock/unlock Bluetooth HID is orange/disconnected; manually tapping orange reconnects
- UI polish and accurate swipe 1 event / hold 4Hz have not yet been instrumented and signed off
- BLE fallback integration in the new APK is still pending; preserve existing standalone BLE remote v1.1.0 unchanged

## Fixes staged in v1.2.1-uat.1

- Back changed from keyboard Escape (0x29) to HID Consumer AC Back 0x224; Android maps it to KEYCODE_BACK. Needs Settings/YouTube UAT.
- Direct 11ms, low-amplitude Android vibrator pulse with view haptic fallback; phone hardware/system haptic settings may affect perception.
- Remember B1 bond and bounded reconnect after HID registration/foreground return; no promise of screen-off background HID persistence.
- Gyro sensitivity selector (precise/normal/fast/very fast), higher initial gain and low-pass filter.
- Gyro tap can use Mouse Click by default or Keyboard Enter via overflow toggle; this is a manual compatibility switch, not detection of the TV launcher.
- Mouse click report holds button through 85ms release even amid gyro movement.

## Next mandatory real-device UAT

1. Settings screen Back repeatedly (at least 5 times) and YouTube Back.
2. Haptics on D-Pad, swipe, menu and gyro taps.
3. TV Home gyro click with both Mouse and Enter selections.
4. Gyro sensitivity (Fast default) and cursor drift.
5. After phone locks/unlocks, auto-reconnect within bounded wait with Wi-Fi OFF.
6. Preserve existing working v1.1.0 + B1 Receiver v0.4.0; neither is updated.

Status: development validation only; NO v1.2.1 release lock before these real-device gates.
