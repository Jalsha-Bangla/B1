#!/usr/bin/env python3
"""Guarded B1 ADB target recovery.

Checks an explicitly supplied new LAN IP using the existing NAS bridge's
dedicated ADB runtime and stored authorization key. Only with --apply, and only
after verifying exact B1/HiMedia/BingeStick identity, backs up and updates the
single target_host field in the existing bridge config.

Never changes the B1's Android settings, installed receiver, or NAS workloads.
"""
import argparse
import importlib.util
import ipaddress
import json
import os
import shutil
import stat
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path("/mnt/FKS_VAULT/JALSHA_AI/SERVICES/fks-b1-bridge")
SCRIPT = ROOT / "fks_b1_worker.py"
CONFIG = ROOT / "config.json"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--host", required=True, help="B1's observed current IPv4")
    p.add_argument("--apply", action="store_true", help="Update config after exact identity check")
    args = p.parse_args()

    ip = ipaddress.ip_address(args.host)
    if ip.version != 4 or not ip.is_private:
        print("INVALID_HOST: expected a private IPv4 address")
        return 2
    if not SCRIPT.is_file() or not CONFIG.is_file():
        print("BRIDGE_NOT_INSTALLED")
        return 2
    spec = importlib.util.spec_from_file_location("fks_b1_worker", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    old = mod.load_config()
    old_ip = ipaddress.ip_address(str(old["target_host"]))
    if ip not in ipaddress.ip_network(f"{old_ip}/24", strict=False):
        print("BLOCKED_DIFFERENT_SUBNET: existing B1 subnet must be maintained")
        return 2

    candidate = dict(old)
    candidate["target_host"] = str(ip)
    bridge = mod.Bridge(candidate)
    state, details = bridge.adb_status()
    if state != "CONNECTED":
        print(json.dumps({
            "state": state, "tested": f"{ip}:{candidate['target_port']}",
            "config_changed": False, "adb_output": details[-1800:]
        }, indent=2))
        return 3
    try:
        identity = bridge.verify_identity()
    except Exception as exc:
        print(json.dumps({"state": "IDENTITY_FAILURE", "config_changed": False,
                          "error": str(exc)}, indent=2))
        return 4
    lines = [s.strip() for s in identity.splitlines() if s.strip()]
    if lines[-3:] != ["B1", "HiMedia", "BingeStick"]:
        print(json.dumps({"state": "IDENTITY_MISMATCH", "observed": lines[-3:],
                          "config_changed": False}, indent=2))
        return 4

    output = {"state": "IDENTITY_PASS", "observed": lines[-3:],
              "old_target": f"{old['target_host']}:{old['target_port']}",
              "verified_target": f"{ip}:{candidate['target_port']}",
              "config_changed": False}
    if args.apply and str(ip) != str(old["target_host"]):
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        backup = CONFIG.with_name("config.pre_hid_target_" + timestamp + ".json")
        shutil.copy2(CONFIG, backup)
        config_mode = stat.S_IMODE(CONFIG.stat().st_mode)
        fd, tmp = tempfile.mkstemp(prefix=".config.target.", suffix=".tmp", dir=ROOT)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                json.dump(candidate, stream, ensure_ascii=False, indent=2)
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.chmod(tmp, config_mode)
            os.replace(tmp, CONFIG)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
        output.update(config_changed=True, backup=str(backup))
    else:
        output["note"] = "Dry run; add --apply for guarded update" if not args.apply else "Already configured"
    print(json.dumps(output, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
