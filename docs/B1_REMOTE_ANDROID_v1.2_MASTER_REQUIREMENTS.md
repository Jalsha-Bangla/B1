# B1 Remote Android v1.2.0 — Precision Remote requirements
Status: DEVELOPMENT SPECIFICATION / NOT RELEASE LOCKED
Date: 2026-10-19

## Compatibility contract
- Preserve the installed working Android phone app v1.1.0 and B1 receiver v0.4.0 unchanged.
- No in-place install, receiver replacement, or BLE protocol change before controlled UAT and rollback.
- Separate probe application ID: com.fks.b1remote.precision.probe.
- Primary goal: offline Bluetooth control, no Wi-Fi/internet requirement for normal use.
- Existing NAS B1 Bridge v0.1.2 remains locked and untouched.

## UX specification
1. Insets/safe-area compliance: Android clock/cutout/status + gesture/navigation bar never overlap the UI.
2. Header: tiny B1 Remote text; only 3 equal-height icon controls — Bluetooth status/reconnect (green/orange), Power, overflow.
3. Overflow selects D-Pad / Swipe / Gyro; consistent layout and persistent footer controls.
4. D-Pad: circular ring with precise quadrant presses, blank center OK circle, no text labels.
5. Minimal haptics on every click, D-Pad move, Swipe movement and Gyro tap.
6. Swipe: one swipe gesture = exactly one directional event; sustained hold after triggering = 4 directional events/second; release stops immediately. Remove Play/Pause.
7. No icon captions and no explanatory Bluetooth/direct/swipe text in production UI.
8. Swipe pointer: smooth white ball follows touch with low-latency smoothing/return animation.
9. Gyro: phone angular motion controls a relative TV cursor; single tap OK; double tap Back, no false single-tap on a double. Sensitivity, recenter and drift mitigation.
10. Phone physical volume keys route to B1 with low-latency, and native local volume change should be suppressed only when remote foreground/connected.

## Navigation defect acceptance tests
- On B1's Wi-Fi password IME: remote arrows navigate every keyboard region and Enter/Connect completes submission.
- On YouTube TV app: arrow keys and OK work; not just system Home.
- Jellyfin works as before; BLE reconnect across receiver restart.
- Every feature works with Wi-Fi disabled *after* the appropriate HID pairing/setup (if HID feasible).

## Transport strategy
- Probe B1 Bluetooth HID Host support using read-only ADB telemetry: a service indicator is **suggestive**, not definitive.
- Probe Android handset's Bluetooth HID Device support and registration.
- Confirm real pairing, keyboard events, consumer controls, and mouse reports. Never mark HID PASS from Android API documentation alone.
- If stock Android blocks HID Device or B1 rejects paired reports, design B1-side Accessibility/overlay fallback and explicitly mark constraints.
- Preserve existing BLE receiver v0.4.0 as fallback; do not claim current test app already integrates it.

## Current implementation / scope
- Native HID proof-of-concept source, D-Pad/Swipe/Gyro controls, and standalone debug APK compile.
- Not yet production polished; icon glyphs, kinetic easing, latency metrics, BLE fallback, physical-key interception, power mapping and gyro calibration require real-device refinement.
- No production lock until YouTube + IME + Gyro + physical volume UAT and non-regression pass.

## UAT gates
G1 = B1 HID host evidence returned from NAS read-only diagnostic.
G2 = handset HID profile proxy and registration pass.
G3 = pairing establishes HID connection.
G4 = YouTube D-Pad and Enter pass.
G5 = Android TV Wi-Fi on-screen keyboard arrow and Enter pass.
G6 = mouse pointer visible, gyro + tap/double-tap pass.
G7 = Swipe one step/4Hz hold measured.
G8 = volume, safety and restart/reconnect pass.
G9 = UI device-inset and accessibility review pass.
G10 = legacy BLE fallback compatibility and rollback pass.
