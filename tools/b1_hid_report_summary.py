#!/usr/bin/env python3
"""Concise read-only interpretation of the previously saved FKS B1 HID probe.

Does not connect to ADB, pair devices or change system/app settings.
"""
import json
import re
from pathlib import Path

PATH = Path("/mnt/FKS_VAULT/JALSHA_AI/CHATGPT_OUT/B1_BRIDGE/RESULTS/FKS-B1-HID-HOST-PROBE__RESULT.json")
PATTERN = re.compile(
    r"hid|hidh|keyboard|mouse|bonded|paired|profile|bluetooth|input|feature",
    re.I,
)

def main():
    if not PATH.is_file():
        print("REPORT_MISSING: " + str(PATH))
        return 2
    result = json.loads(PATH.read_text(encoding="utf-8"))
    if result.get("probe") != "FKS_B1_HID_HOST":
        print("UNEXPECTED_REPORT_TYPE")
        return 3
    print("REPORT_STATE:", result.get("state"))
    print("TARGET:", result.get("target"))
    print("MODEL:", result.get("identity", "").replace("\n", " / "))
    print("HID_HOST_INDICATOR:", result.get("hid_host_service_indicator"))
    print("LIVE_HID_PAIRING:", "NOT_TESTED" if not result.get("paired_hid_functionally_tested") else "TESTED")
    checks = result.get("checks", {})
    for name in ("bluetooth_on", "features", "bluetooth_manager", "bluetooth_package",
                 "hid_services", "paired_input_devices"):
        item = checks.get(name) or {}
        print("\n=== " + name.upper() + " (rc=" + str(item.get("rc", "unknown")) + ") ===")
        if item.get("error"):
            print("ERROR:", item["error"])
            continue
        lines = [line.strip() for line in (item.get("output") or "").splitlines()]
        if name == "bluetooth_on":
            matches = lines
        else:
            matches = [line for line in lines if PATTERN.search(line)]
        if not matches:
            print("(no matching service/feature lines in saved probe output)")
        else:
            for line in matches[:26]:
                print(line[:230])
            if len(matches) > 26:
                print(f"... {len(matches) - 26} further matching lines omitted")
    print("\nCONCLUSION: NO_LIVE_HID_HOST_PAIRING_PROOF_YET")
    print("NOTE: Missing service string is inconclusive; real host pairing + input is required.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
