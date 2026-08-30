# B1 Remote

Private B1 Android TV / iPhone Bluetooth remote project.

## Proven transport
iPhone → Bluetooth LE → B1 → Accessibility Service → Android TV

The B1 receiver has already passed:
- boot-time BLE auto-start
- Accessibility binding
- Wi-Fi-independent Bluetooth control
- HOME, BACK, UP, DOWN, LEFT, RIGHT, OK, VOL_UP, VOL_DOWN, PLAY_PAUSE

## iPhone cloud build
GitHub Actions builds the native SwiftUI/CoreBluetooth client on the `macos-26` runner using Xcode 26.x.

Workflow:
`.github/workflows/build-ipa.yml`

Artifact:
`B1-Remote-iPhone-v0.2-IPA`

The artifact contains an unsigned IPA intended to be signed/sideloaded to the owner's iPhone with AltServer/AltStore on Windows.

## Source bundle
`B1_Remote_iPhone_CloudBuild_v0.2.zip`

This archive contains the complete Xcode project and Swift source used by the workflow.
