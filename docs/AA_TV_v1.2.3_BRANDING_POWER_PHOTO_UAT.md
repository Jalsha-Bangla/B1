# AA TV Android v1.2.3 — Branding / Power / Private Swipe Photo UAT

Status: **DEVELOPMENT BUILD / NOT LOCKED**
Parent baseline: `feature/android-v1.2-precision-hid` v1.2.2 Always-On.
New branch: `feature/aa-tv-v1.2.3-photo-power`.

## Scope
- User-facing remote/app launcher name becomes **AA TV**.
- New custom AA TV icon in launcher and compact header.
- Fixed Power button as a scalable canvas icon, independent of device glyph/font support.
- Power click now sends the HID **Consumer Sleep Mode usage 0x34** to B1, which normally maps to Android KEYCODE_POWER. First tap requires a warning confirmation. **NOT LIVE-VERIFIED ON B1**; standby may disconnect Bluetooth, requiring physical recovery.
- Swipe mode supports choosing a photo once via Android document picker, storing it only in the phone's **private app files** (`swipe_photo_private.jpg`). The image is drawn with center-crop, rounded clipping, and 36% opacity underneath the smooth white swipe ball.
- User's supplied children's photo is **not committed to the public GitHub repository**. A separately cropped private JPEG accompanies the APK, for import via menu **⋮ > Choose Swipe photo**.
- Choosing/removing the photo changes only app-private data and never sends it over Bluetooth, Drive or GitHub.
- Actual B1 device Bluetooth name/identity, pairing, receiver and NAS bridge remain unchanged.
- Existing working Android v1.1.0 and B1 receiver v0.4.0 untouched.
- Application ID `com.fks.b1remote.precision.probe` retained, so an install may require uninstalling only the prior experimental probe when signing differs.

## Required live-device validation
1. Launcher icon and AA TV label; no safe-area overlap.
2. Header power icon renders (no X or tofu). Short tap (after confirmation) sends Consumer Sleep Mode; observe whether B1 sleeps, opens power UI, ignores it, and whether re-wake is possible. Always keep a physical remote/power outlet available.
3. Import private JPEG from Files via **⋮ > Choose Swipe photo**; verify children centered, slightly zoomed, and visible at light opacity with white ball in front.
4. Switch D-Pad ↔ Swipe ↔ Gyro, power/volume/Back/YouTube/keyboard; no regression.
5. Lock/unlock, background service and auto reconnect remain functional.

### Security and privacy
Do not commit the photo or a base64 representation of the photo to public GitHub Actions logs/source. A private file picker offers durable privacy and replaces automatic bundled-photo delivery.

## Release criteria
Do not merge until physical B1 test proves Power behavior and full UI UAT. HID Consumer 0x34 mapping is platform-dependent.
