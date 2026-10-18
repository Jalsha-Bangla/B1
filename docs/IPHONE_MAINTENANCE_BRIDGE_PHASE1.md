# B1 Remote iPhone — Phase 1 Maintenance Bridge

Branch: \`feature/iphone-maintenance-bridge-v1\`

## Goal

Remove the Windows-PC dependency for normal B1 maintenance by adding a local-network ADB client to the existing iPhone B1 Remote app.

The Bluetooth remote path remains independent and unchanged. The new Maintenance tab is an additive local-Wi-Fi tool.

## Implemented in v0.4.0 candidate

- Remote tab: existing BLE control commands
- Maintenance tab:
  - connect to B1 ADB on TCP port 5555
  - first-use RSA ADB authorization using an iPhone-local Keychain key
  - run shell commands
  - one-tap Enter/Home/Back/D-pad keyevents
  - restart \`com.fks.b1remote/.BleRemoteService\`
  - receiver/package/accessibility health snapshot
  - read recent logcat output
  - choose an APK from iPhone Files, upload to \`/data/local/tmp\`, and run \`pm install -r\`
- ADB private key is generated on-device and stored in the iPhone Keychain.
- No ADB private key or device credential is committed to Git.
- Local Network permission is used only for the Maintenance tab's direct B1 connection.

## B1 prerequisites

- B1 and iPhone on the same LAN/Wi-Fi
- Developer options enabled on B1
- USB debugging enabled on B1
- ADB TCP listener reachable on port 5555
- On first iPhone ADB connection, accept the B1 "Allow USB debugging" prompt and preferably enable "Always allow"

## UAT gates before merge

1. Existing BLE Remote tab still connects and all locked buttons work.
2. Maintenance connects to a verified B1 identity.
3. First-use RSA authorization succeeds.
4. \`input keyevent 66\` submits the Android TV keyboard Enter action.
5. Shell output returns correctly.
6. Receiver restart recovers BLE service.
7. Health/log actions return output.
8. APK update of a known-good B1 receiver succeeds with \`pm install -r\`.
9. Cold reopen: remembered B1 IP and ADB Keychain identity still work.
10. No Windows PC is required for gates 2–9.

Do not merge or call this hard-locked until real-device UAT passes.
