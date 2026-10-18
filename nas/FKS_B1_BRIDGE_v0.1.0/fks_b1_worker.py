#!/usr/bin/env python3
import argparse, hashlib, json, os, re, shlex, sqlite3, subprocess, tempfile
from datetime import datetime, timezone
from pathlib import Path

VERSION = "0.1.2"
SERVICE = Path(__file__).resolve().parent
CONFIG_PATH = SERVICE / "config.json"

KEYEVENTS = {
    "ENTER": 66, "HOME": 3, "BACK": 4, "UP": 19, "DOWN": 20,
    "LEFT": 21, "RIGHT": 22, "OK": 23, "PLAY_PAUSE": 85,
    "VOL_UP": 24, "VOL_DOWN": 25, "MUTE": 164,
}
SHELL_COMMANDS = {
    "identity": "getprop ro.product.model; getprop ro.product.manufacturer; getprop ro.product.device; getprop ro.build.version.release; getprop ro.build.version.sdk",
    "receiver_health": "dumpsys package com.fks.b1remote | grep -E 'versionName|versionCode' | head -20; dumpsys activity services com.fks.b1remote | head -120",
    "accessibility_state": "settings get secure enabled_accessibility_services; settings get secure accessibility_enabled",
    "network": "ip addr show wlan0; ip route",
    "packages": "pm list packages | grep -E 'com.fks.b1remote|com.hitv.rc'",
}

def utc_now():
    return datetime.now(timezone.utc).isoformat()

def load_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        cfg = json.load(f)
    required = ["target_host", "target_port", "docker_image", "adb_key_dir", "commands_dir", "files_dir", "results_dir", "status_dir", "state_db"]
    missing = [k for k in required if not cfg.get(k)]
    if missing:
        raise RuntimeError("Missing config keys: " + ", ".join(missing))
    return cfg

def atomic_json(path: Path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False, indent=2)
            f.write("\n")
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

class Bridge:
    def __init__(self, cfg):
        self.cfg = cfg
        self.serial = f"{cfg['target_host']}:{int(cfg['target_port'])}"
        self.image = cfg["docker_image"]
        self.key_dir = Path(cfg["adb_key_dir"])
        self.commands_dir = Path(cfg["commands_dir"])
        self.files_dir = Path(cfg["files_dir"])
        self.results_dir = Path(cfg["results_dir"])
        self.status_dir = Path(cfg["status_dir"])
        self.db_path = Path(cfg["state_db"])
        for p in [self.key_dir, self.commands_dir, self.files_dir, self.results_dir, self.status_dir, self.db_path.parent]:
            p.mkdir(parents=True, exist_ok=True)
        os.chmod(self.key_dir, 0o700)
        self.db = sqlite3.connect(self.db_path)
        self.db.execute("""CREATE TABLE IF NOT EXISTS jobs(
            job_id TEXT PRIMARY KEY,
            request_sha256 TEXT NOT NULL,
            status TEXT NOT NULL,
            action TEXT NOT NULL,
            processed_at TEXT NOT NULL
        )""")
        self.db.commit()

    def docker(self, command: str, timeout=30):
        cmd = ["docker", "run", "--rm", "--network", "host",
               "-v", f"{self.key_dir}:/root/.android",
               "-v", f"{self.files_dir}:/input:ro",
               self.image, command]
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=timeout)
        return p.returncode, p.stdout.strip()

    def adb_shell(self, shell_cmd: str, timeout=30):
        command = (
            "adb start-server >/dev/null 2>&1; "
            f"adb connect {self.serial} >/tmp/connect.txt 2>&1 || true; "
            f"adb -s {self.serial} shell {shlex.quote(shell_cmd)}"
        )
        rc, out = self.docker(command, timeout=timeout)
        low = out.lower()
        if "unauthorized" in low:
            raise PermissionError("ADB_UNAUTHORIZED")
        if "no devices/emulators found" in low or "device not found" in low:
            raise ConnectionError("ADB_DEVICE_NOT_FOUND")
        return rc, out

    def adb_status(self):
        command = (
            "adb start-server >/dev/null 2>&1; "
            f"adb connect {self.serial} 2>&1; "
            "echo '---DEVICES---'; adb devices -l"
        )
        rc, out = self.docker(command, timeout=20)
        state = "CONNECTED"
        low = out.lower()
        if "unauthorized" in low:
            state = "AUTH_PENDING"
        elif not re.search(r"(?m)^" + re.escape(self.serial) + r"\s+device(?:\s|$)", out):
            state = "OFFLINE"
        return state, out

    def verify_identity(self):
        _, out = self.adb_shell("getprop ro.product.model; getprop ro.product.manufacturer; getprop ro.product.device", timeout=20)
        lines = [x.strip() for x in out.splitlines() if x.strip()]
        tail = lines[-3:] if len(lines) >= 3 else lines
        joined = "\n".join(tail)
        if not ("B1" in joined and "BingeStick" in joined):
            raise RuntimeError("IDENTITY_MISMATCH: " + joined)
        return joined

    def write_status(self, state, details=""):
        atomic_json(self.status_dir / "B1_BRIDGE_STATUS.json", {
            "schema_version": 1, "bridge": "FKS B1 Bridge", "version": VERSION,
            "target": self.serial, "state": state, "details": details[-4000:],
            "updated_at": utc_now(),
        })

    def result(self, job_id, action, status, output="", error=None, transient=False):
        obj = {
            "schema_version": 1, "job_id": job_id, "bridge": "FKS B1 Bridge",
            "bridge_version": VERSION, "target": self.serial, "action": action,
            "status": status, "output": output[-20000:], "error": error,
            "transient": transient, "completed_at": utc_now(),
        }
        atomic_json(self.results_dir / f"{job_id}__RESULT.json", obj)
        return obj

    def seen(self, job_id, req_sha):
        row = self.db.execute("SELECT request_sha256,status FROM jobs WHERE job_id=?", (job_id,)).fetchone()
        if not row:
            return None
        if row[0] != req_sha:
            return "CONFLICT"
        return row[1]

    def mark(self, job_id, req_sha, status, action):
        self.db.execute(
            "INSERT OR REPLACE INTO jobs(job_id,request_sha256,status,action,processed_at) VALUES(?,?,?,?,?)",
            (job_id, req_sha, status, action, utc_now()))
        self.db.commit()

    def execute(self, req, req_sha):
        job_id = req.get("job_id")
        action = req.get("action")
        args = req.get("args") or {}
        if not isinstance(job_id, str) or not re.fullmatch(r"[A-Za-z0-9._-]{3,96}", job_id):
            raise ValueError("Invalid job_id")
        if req.get("schema_version") != 1:
            raise ValueError("schema_version must be 1")
        if not isinstance(action, str) or not action.startswith("b1."):
            raise ValueError("Unsupported action")

        prior = self.seen(job_id, req_sha)
        if prior == "CONFLICT":
            return self.result(job_id, action, "FAIL_CONFLICT", error="Same job_id was already used with different request bytes.")
        if prior == "PASS":
            return self.result(job_id, action, "SKIPPED_ALREADY_PROCESSED", output="Original request already completed successfully.")

        try:
            state, status_out = self.adb_status()
            if state == "AUTH_PENDING":
                self.write_status("AUTH_PENDING", status_out)
                return self.result(job_id, action, "AUTH_PENDING", output=status_out, error="Approve 'Allow USB debugging' on B1, then wait for next bridge run.", transient=True)
            if state != "CONNECTED":
                self.write_status("OFFLINE", status_out)
                return self.result(job_id, action, "OFFLINE", output=status_out, error="B1 ADB is not reachable at configured target.", transient=True)

            identity = self.verify_identity()

            if action == "b1.status":
                _, out = self.adb_shell(
                    "echo '=== IDENTITY ==='; getprop ro.product.model; getprop ro.product.manufacturer; getprop ro.product.device; "
                    "echo '=== RECEIVER ==='; dumpsys package com.fks.b1remote | grep -E 'versionName|versionCode' | head -20; "
                    "dumpsys activity services com.fks.b1remote | head -100; "
                    "echo '=== ACCESSIBILITY ==='; settings get secure enabled_accessibility_services; settings get secure accessibility_enabled",
                    timeout=30)

            elif action == "b1.enter":
                _, out = self.adb_shell("input keyevent 66", timeout=15)

            elif action == "b1.keyevent":
                name = str(args.get("key", "")).upper()
                if name not in KEYEVENTS:
                    raise ValueError("key must be one of: " + ", ".join(sorted(KEYEVENTS)))
                _, out = self.adb_shell(f"input keyevent {KEYEVENTS[name]}", timeout=15)

            elif action == "b1.shell":
                command_id = str(args.get("command_id", ""))
                if command_id not in SHELL_COMMANDS:
                    raise ValueError("command_id must be one of: " + ", ".join(sorted(SHELL_COMMANDS)))
                _, out = self.adb_shell(SHELL_COMMANDS[command_id], timeout=30)

            elif action == "b1.logs":
                lines = max(50, min(int(args.get("lines", 250)), 500))
                _, out = self.adb_shell(f"logcat -d -t {lines}", timeout=30)

            elif action == "b1.restart_receiver":
                _, out = self.adb_shell(
                    "am stopservice -n com.fks.b1remote/.BleRemoteService >/dev/null 2>&1; "
                    "sleep 1; am start-foreground-service -n com.fks.b1remote/.BleRemoteService; "
                    "sleep 1; dumpsys activity services com.fks.b1remote | head -80",
                    timeout=30)

            elif action == "b1.install_apk":
                name = os.path.basename(str(args.get("file", "")))
                expected = str(args.get("sha256", "")).lower()
                if req.get("confirm") != f"INSTALL:{job_id}":
                    raise ValueError(f"install requires confirm=INSTALL:{job_id}")
                if not re.fullmatch(r"[A-Za-z0-9._-]+\.apk", name):
                    raise ValueError("Invalid APK filename")
                if not re.fullmatch(r"[0-9a-f]{64}", expected):
                    raise ValueError("sha256 must be 64 lowercase hex characters")
                apk = (self.files_dir / name).resolve()
                if apk.parent != self.files_dir.resolve() or not apk.is_file():
                    raise FileNotFoundError("APK not found in B1_BRIDGE/FILES")
                actual = sha256_file(apk)
                if actual != expected:
                    raise ValueError(f"APK_SHA256_MISMATCH actual={actual}")
                command = (
                    "adb start-server >/dev/null 2>&1; "
                    f"adb connect {self.serial} >/dev/null 2>&1 || true; "
                    f"adb -s {self.serial} install -r '/input/{name}'; "
                    f"adb -s {self.serial} shell dumpsys package com.fks.b1remote | grep -E 'versionName|versionCode' | head -20"
                )
                rc, out = self.docker(command, timeout=180)
                if rc != 0 or "Failure [" in out:
                    raise RuntimeError("APK_INSTALL_FAILED: " + out[-5000:])
            else:
                raise ValueError("Unsupported action")

            self.mark(job_id, req_sha, "PASS", action)
            self.write_status("READY", identity)
            return self.result(job_id, action, "PASS", output=out or "OK")

        except PermissionError as e:
            self.write_status("AUTH_PENDING", str(e))
            return self.result(job_id, action, "AUTH_PENDING", error="Approve USB debugging on B1.", transient=True)
        except ConnectionError as e:
            self.write_status("OFFLINE", str(e))
            return self.result(job_id, action, "OFFLINE", error=str(e), transient=True)
        except Exception as e:
            self.mark(job_id, req_sha, "FAIL", action)
            self.write_status("ERROR", str(e))
            return self.result(job_id, action, "FAIL", error=f"{type(e).__name__}: {e}")

    def run_once(self):
        for path in sorted(self.commands_dir.glob("*.json")):
            try:
                raw = path.read_bytes()
                self.execute(json.loads(raw.decode("utf-8")), sha256_bytes(raw))
            except Exception as e:
                self.result(path.stem[:96], "unknown", "FAIL", error=f"Invalid request file: {type(e).__name__}: {e}")

    def self_test(self):
        checks = {
            "config": CONFIG_PATH.is_file(),
            "docker": subprocess.run(["docker", "version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0,
            "image": subprocess.run(["docker", "image", "inspect", self.image], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0,
            "dirs": all(p.exists() for p in [self.commands_dir, self.files_dir, self.results_dir, self.status_dir, self.key_dir]),
        }
        ok = all(checks.values())
        print(json.dumps({"version": VERSION, "status": "PASS" if ok else "FAIL", "checks": checks}, indent=2))
        return 0 if ok else 1

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--once", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    bridge = Bridge(load_config())
    if args.self_test:
        return bridge.self_test()
    bridge.run_once()
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
