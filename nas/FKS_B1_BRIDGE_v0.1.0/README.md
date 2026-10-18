# FKS B1 Bridge v0.1.0

Dedicated, allowlisted TrueNAS -> B1 ADB worker.

## Architecture
ChatGPT / Google Drive TO_NAS -> TrueNAS Cloud Sync PULL -> FKS B1 Bridge -> ADB 192.168.68.108:5555 -> B1.

Results are written under CHATGPT_OUT/B1_BRIDGE and returned by the existing PUSH task.

## Safety
- No generic NAS root shell endpoint.
- B1 identity must match B1 / BingeStick before any action.
- ADB runs in a dedicated Alpine container.
- ADB RSA keys persist only under the bridge service directory.
- b1.shell accepts command IDs only, never raw shell text.
- APK install requires SHA-256 plus confirm=INSTALL:<JOB_ID>.
- Existing Cloud Sync post-script is preserved and executed before this worker.
- SMB, Jellyfin, Immich, media, drama, private and CCTV configuration are untouched.

## Actions
b1.status
b1.enter
b1.keyevent
b1.shell
b1.logs
b1.restart_receiver
b1.install_apk

## Queue paths
Commands: /mnt/FKS_VAULT/JALSHA_AI/CHATGPT_IN/B1_BRIDGE/COMMANDS
Files: /mnt/FKS_VAULT/JALSHA_AI/CHATGPT_IN/B1_BRIDGE/FILES
Results: /mnt/FKS_VAULT/JALSHA_AI/CHATGPT_OUT/B1_BRIDGE/RESULTS
Status: /mnt/FKS_VAULT/JALSHA_AI/CHATGPT_OUT/B1_BRIDGE/STATUS

First ADB connection may show "Allow USB debugging" on B1. Enable "Always allow" and choose Allow.
