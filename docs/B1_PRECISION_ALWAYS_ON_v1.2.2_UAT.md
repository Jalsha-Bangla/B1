# B1 Precision HID v1.2.2 — Always-On UAT (NOT RELEASE LOCKED)

Reason: User observed phone locking causes Bluetooth HID disconnect; B1 TV then displays its native remote-pairing guidance. Manual reconnect of already-bonded vivo V30 Lite works, but is intrusive. v1.2.1 has NOT been tested by user.

## Design and changes
- HID transport is owned by Android **connectedDevice foreground service**, not MainActivity. Android Bluetooth HID unregisters apps whose UID falls below its foreground importance threshold; FGS keeps UID foreground-service importance when phone screen locks, subject to vendor policy.
- Foreground notification shows connected/reconnecting and includes explicit Disconnect action. Three-dot menu also supports intentional Disconnect.
- Service continues when UI pauses/closes or phone locks. Activity destruction does NOT call HID unregister.
- Persistent successful B1 bond from pre-existing HidTransport logic; on foreground registration and when not connected, reconnects without initiating a new pairing request. 30-second maintenance tick plus Bluetooth state ON listener; service returns START_STICKY after system kill.
- Best-effort BOOT_COMPLETED / MY_PACKAGE_REPLACED start if user previously opted in. Vendor battery management or Android foreground service restrictions can still prevent boot-time recovery.
- No Wi-Fi needed. B1 Receiver v0.4.0 and old Android remote v1.1.0 untouched. No B1 firmware change.

## UAT gates
1. Initial connect + green icon + D-pad/Youtube and Wi-Fi OFF sanity.
2. **Phone locks for 60 seconds, then 5 minutes**: confirm B1 TV stays on its current screen, no pairing popup. Unlock and green remains.
3. Open other apps then return; no disconnect and button controls still work.
4. Turn B1 off then on: confirm automatic reconnect without repeating pairing, while phone BT remains on. Timing varies; service checks periodically.
5. Toggle phone Bluetooth OFF then ON: reconnect without unpair/re-pair.
6. Reboot phone: if Android allows boot autostart, recovery without manual app launch. Check app notifications and vivo autostart permissions.
7. Use ⋮ > Disconnect: notification stops and connection intentionally ends. Orange button restarts service.
8. Retest Settings Back, haptics, gyro Home click and sensitivity from v1.2.1 fixes.

## Required vivo V30 Lite settings
- Set B1 Precision HID Probe to **Unrestricted / Allow background usage** under battery/app settings.
- Enable **Autostart** for the probe (vivo iManager or Settings special app access, depending on OS).
- Allow notifications so the ongoing connectedDevice service is visible.
- Do not Force stop the app; Android Force stop blocks boot/background restarts until reopened.

## Limitations
- No claim of 100% always-connected: if B1 powers off, Bluetooth is switched off, app is force-stopped, or phone/OEM kills the foreground service, HID necessarily disconnects.
- Stock B1 remote-pairing overlay is vendor firmware behavior and cannot be guaranteed suppressed just by sending HID connect requests.
- Pairing itself is one-time; OS/device may still require reconnect when host returns.
- Service must be manually started at least once; it never silently assumes background operation without user opening the app.
- Do not merge PR #3 or update existing working apps until real-device UAT passes.
