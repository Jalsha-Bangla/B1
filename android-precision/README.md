# B1 Remote Android v1.2.0 — Precision HID development track

**Development-only**, does not replace the live Android Remote v1.1.0 or the B1 Receiver v0.4.0.

- Branch: `feature/android-v1.2-precision-hid`
- An isolated test application has application ID `com.fks.b1remote.precision.probe`.
- B1 NAS bridge `v0.1.2` remains unmodified and locked.
- A read-only NAS HID Host diagnostic is in `tools/b1_hid_host_probe.py`. It interrogates B1 via existing ADB key and writes an audit file under `FROM_NAS/B1_BRIDGE/RESULTS`. It does **not** install/change/reboot anything.
- The Android probe attempts Android Bluetooth HID Device registration, exposes actual pairing/connection status, sends keyboard and relative mouse HID reports when a real B1 HID connection is established. HID availability on the handset and interoperability on the B1 cannot be assumed from Android versions alone.
- Existing BLE receiver cannot be called HID; switching is not automatic without a successful HID pairing.

## Gates

1. B1 read-only HID Host capability evidence (service and feature indicators) — **pending runtime execution**.
2. Phone HID Device profile proxy + registration — **pending real handset test**.
3. B1 HID Host pairing and input: UP/DOWN/LEFT/RIGHT/ENTER on YouTube and Wi-Fi IME — **pending**.
4. Mouse relative cursor, Gyro and button latency — **pending**.
5. Only after 1–4 PASS consider integration with the current v1.1.0 phone app/receiver. Never overwrite them during proof-of-concept.

## Safe NAS diagnostic

On the **home LAN**, from TrueNAS Shell, run only after reviewing the script:

```bash
sudo curl -fsSL https://raw.githubusercontent.com/Jalsha-Bangla/B1/feature/android-v1.2-precision-hid/tools/b1_hid_host_probe.py -o /tmp/b1_hid_host_probe.py && sudo /usr/bin/python3 /tmp/b1_hid_host_probe.py
```

It needs the existing B1 ADB at `192.168.68.108:5555`. If the IP changed, the probe safely reports offline rather than changing the target. Results are written into the existing Bridge RESULTS directory.
