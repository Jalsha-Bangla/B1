# FKS B1 Bridge v0.1.2 — END-TO-END CONTROL LOCK

Status: **LOCKED / PASS**

Lock date: 2026-10-19 (+06:00)

## Verified production path

User command in ChatGPT
→ Google Drive TO_NAS queue
→ TrueNAS Cloud Sync PULL
→ FKS B1 Bridge
→ ADB TCP 192.168.68.108:5555
→ B1
→ visible Android TV action

## Real-device evidence

1. ADB authorization on B1 was approved with "Always allow".
2. Preflight identity check passed with:
   - model: B1
   - manufacturer: HiMedia
   - device: BingeStick
3. Worker version: 0.1.2.
4. End-to-end HOME canary was issued from ChatGPT through the Drive/NAS bridge with no user-entered shell command for the action.
5. B1 visibly moved to the Home screen.
6. Existing BLE receiver and Accessibility control app remained independent from this bridge.

## Locked safety model

- No generic TrueNAS root-shell endpoint is exposed to ChatGPT.
- B1 identity must match B1/BingeStick before allowlisted actions execute.
- ADB is isolated through the dedicated bridge container/runtime.
- Persistent ADB RSA credentials remain under the bridge service directory.
- b1.shell accepts only predefined diagnostic command IDs, not arbitrary shell text.
- APK installation requires an exact SHA-256 plus a job-specific explicit confirmation.
- Existing NAS workloads (SMB, Jellyfin, Immich, JMF infrastructure, media, drama, private, CCTV) are outside the bridge action scope.

## Locked allowlisted actions

- b1.status
- b1.enter
- b1.keyevent
- b1.shell (predefined command_id only)
- b1.logs
- b1.restart_receiver
- b1.install_apk (checksum + confirmation gated)

## Current endpoint

- B1 ADB target: 192.168.68.108:5555
- Service: /mnt/FKS_VAULT/JALSHA_AI/SERVICES/fks-b1-bridge
- Input queue: /mnt/FKS_VAULT/JALSHA_AI/CHATGPT_IN/B1_BRIDGE
- Output queue: /mnt/FKS_VAULT/JALSHA_AI/CHATGPT_OUT/B1_BRIDGE

## Next UAT block

1. ENTER action
2. Status/result return proof through FROM_NAS
3. Receiver health
4. Receiver restart + BLE recovery
5. Logs
6. APK update gate dry-run / known-good package
7. IP-change resilience / host update procedure

Do not weaken the locked safety model when adding future capabilities.
