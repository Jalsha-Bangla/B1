#!/usr/bin/env python3
"""Read-only B1 HID Host capability probe through existing FKS NAS bridge.
No ADB settings changes, pairing changes, receiver updates, or key injection.
Run on TrueNAS as: sudo /usr/bin/python3 /path/to/b1_hid_host_probe.py
"""
import importlib.util, json, re, sys
from datetime import datetime, timezone
from pathlib import Path

SERVICE = Path('/mnt/FKS_VAULT/JALSHA_AI/SERVICES/fks-b1-bridge')
WORKER = SERVICE / 'fks_b1_worker.py'
spec = importlib.util.spec_from_file_location('fks_b1_worker', WORKER)
if spec is None or spec.loader is None:
    raise RuntimeError('Installed bridge worker not found')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
bridge = mod.Bridge(mod.load_config())
state, adb_details = bridge.adb_status()
if state != 'CONNECTED':
    print(json.dumps({'probe':'FKS_B1_HID_HOST','state':state,'error':adb_details[-1500:]},indent=2))
    raise SystemExit(2)
identity = bridge.verify_identity()
commands = {
    'android_system': 'getprop ro.build.version.release; getprop ro.build.version.sdk; getprop ro.product.model; getprop ro.product.device',
    'bluetooth_on': 'settings get global bluetooth_on',
    'bluetooth_manager': 'dumpsys bluetooth_manager',
    'bluetooth_package': 'dumpsys package com.android.bluetooth | grep -i -E "HidHostService|HidDeviceService|HID_HOST|profile|bluetooth" | head -75',
    'hid_services': 'service list | grep -i -E "bluetooth|hid|input"',
    'features': 'pm list features | grep -i -E "bluetooth|hid|usb.host"',
    'paired_input_devices': 'dumpsys input | grep -i -E "hid|keyboard|bluetooth|mouse" | head -85',
}
checks = {}
for key, command in commands.items():
    try:
        rc, output = bridge.adb_shell(command, timeout=35)
        checks[key] = {'rc': rc, 'output': output[-12000:]}
    except Exception as e:
        checks[key] = {'error': f'{type(e).__name__}: {e}'}
manager = checks.get('bluetooth_manager',{}).get('output','')
pkg = checks.get('bluetooth_package',{}).get('output','')
indicator = bool(re.search(r'(HidHostService|HID_HOST|BluetoothHidHost|HidHost)', manager+'\n'+pkg, re.I))
obj = {
    'schema_version':1, 'probe':'FKS_B1_HID_HOST','probe_version':'0.1.0',
    'target':bridge.serial,'identity':identity,
    'observed_at':datetime.now(timezone.utc).isoformat(),
    'state':'EVIDENCE_COLLECTED',
    'hid_host_service_indicator': indicator,
    'paired_hid_functionally_tested': False,
    'interpretation':'An HID Host service indicator alone does not prove pairing, HID keyboard input, or mouse cursor functionality. A real handset/B1 pairing and live keypress UAT remains mandatory.',
    'checks':checks,
}
bridge.results_dir.mkdir(parents=True,exist_ok=True)
out = bridge.results_dir/'FKS-B1-HID-HOST-PROBE__RESULT.json'
mod.atomic_json(out,obj)
print('READ_ONLY_HID_PROBE_COMPLETE')
print('HID_HOST_SERVICE_INDICATOR='+str(indicator))
print('RESULT='+str(out))
print('LIVE_PAIRING_UAT=NOT_YET_TESTED')
