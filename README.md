# B1 Remote

B1 Android TV / iPhone Bluetooth remote project.

## Proven transport
iPhone → Bluetooth LE → B1 → Accessibility Service → Android TV

## Batch 1
The original Bluetooth-only remote foundation is complete and user-accepted:
- boot-time BLE auto-start
- Accessibility binding
- Wi-Fi / mobile-data / Internet independent control
- HOME, BACK, UP, DOWN, LEFT, RIGHT, OK, VOL_UP, VOL_DOWN, PLAY_PAUSE
- native iPhone app UAT
- cold-power-cycle UAT

## v0.3 — Connection Stability / Auto-Recovery
This release targets intermittent `Connecting…` / failed reconnect behavior observed while the B1 TV card is busy or a BLE link drops.

### Android receiver hardening
- forced advertising restart after every GATT disconnect
- BLE health watchdog
- GATT/advertising self-healing
- Bluetooth OFF → ON recovery
- existing HiRemote vendor remote system untouched
- same BLE UUIDs and command protocol

Package:
`B1_Remote_Android_Stability_v0.3.zip`

The Android update patches the existing proven receiver project in place and **requires the existing signing keystore** so `adb install -r` remains a valid update.

### iPhone v0.3 hardening
- remembered B1 peripheral
- fast direct reconnect
- fresh BLE scan fallback
- connection timeout
- service-discovery timeout
- bounded reconnect backoff
- write-error recovery
- CoreBluetooth state restoration
- `bluetooth-central` background mode
- foreground health/resume check

Source bundle:
`B1_Remote_iPhone_CloudBuild_v0.3.zip`

GitHub Actions artifact:
`B1-Remote-iPhone-v0.3-IPA`

The IPA is unsigned and is intended to be signed/sideloaded with AltServer/AltStore.

## BLE protocol
Service UUID:
`7B3E1001-2F9A-4E2A-9A6B-1C6C0F9B1001`

Command characteristic:
`7B3E1002-2F9A-4E2A-9A6B-1C6C0F9B1001`
