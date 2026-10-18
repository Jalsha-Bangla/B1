#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"
ROOT="/mnt/FKS_VAULT/JALSHA_AI"
SERVICE="$ROOT/SERVICES/fks-b1-bridge"
IN_ROOT="$ROOT/CHATGPT_IN/B1_BRIDGE"
OUT_ROOT="$ROOT/CHATGPT_OUT/B1_BRIDGE"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="fks-b1-adb:$VERSION"
TARGET_HOST="${B1_HOST:-192.168.68.108}"
TARGET_PORT="${B1_PORT:-5555}"

[ "$(id -u)" -eq 0 ] || { echo "ERROR: run with sudo/root"; exit 1; }
for c in python3 docker midclt sha256sum; do command -v "$c" >/dev/null || { echo "ERROR: missing $c"; exit 1; }; done
[ -d "$ROOT/CHATGPT_IN" ] && [ -d "$ROOT/CHATGPT_OUT" ] && [ -d "$ROOT/SERVICES" ] || { echo "ERROR: expected JALSHA_AI baseline not found under $ROOT"; exit 1; }

STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$SERVICE/backups/$STAMP" "$SERVICE/adb_keys" "$SERVICE/state" "$IN_ROOT/COMMANDS" "$IN_ROOT/FILES" "$OUT_ROOT/RESULTS" "$OUT_ROOT/STATUS"
chmod 700 "$SERVICE/adb_keys"

if [ -f "$SERVICE/config.json" ]; then cp -a "$SERVICE/config.json" "$SERVICE/backups/$STAMP/config.json"; fi
cp -a "$SRC_DIR/fks_b1_worker.py" "$SERVICE/fks_b1_worker.py"
mkdir -p "$SERVICE/image"
cp -a "$SRC_DIR/Dockerfile" "$SERVICE/image/Dockerfile"

cat > "$SERVICE/config.json" <<EOF
{
  "schema_version": 1,
  "bridge_name": "FKS B1 Bridge",
  "version": "$VERSION",
  "target_host": "$TARGET_HOST",
  "target_port": $TARGET_PORT,
  "docker_image": "$IMAGE",
  "adb_key_dir": "$SERVICE/adb_keys",
  "commands_dir": "$IN_ROOT/COMMANDS",
  "files_dir": "$IN_ROOT/FILES",
  "results_dir": "$OUT_ROOT/RESULTS",
  "status_dir": "$OUT_ROOT/STATUS",
  "state_db": "$SERVICE/state/jobs.sqlite"
}
EOF

echo "[1/6] Building dedicated ADB image..."
docker build -t "$IMAGE" "$SERVICE/image"

echo "[2/6] Discovering existing Drive PULL task..."
TASKS="$SERVICE/backups/$STAMP/cloudsync.query.json"
midclt call cloudsync.query > "$TASKS"
DISCOVERY="$SERVICE/backups/$STAMP/discovery.txt"
python3 - "$TASKS" "$ROOT/CHATGPT_IN" > "$DISCOVERY" <<'PY'
import json,sys
p,target=sys.argv[1:3]
data=json.load(open(p))
matches=[x for x in data if str(x.get("direction","")).upper()=="PULL" and x.get("path")==target]
print(len(matches))
if len(matches)==1:
    x=matches[0]
    print(x["id"])
    print(json.dumps(x.get("post_script") or ""))
PY
COUNT="$(sed -n '1p' "$DISCOVERY")"
[ "$COUNT" = "1" ] || { echo "ERROR: expected exactly one PULL task for $ROOT/CHATGPT_IN, found $COUNT"; exit 1; }
PULL_ID="$(sed -n '2p' "$DISCOVERY")"
PREV_JSON="$(sed -n '3p' "$DISCOVERY")"
python3 - "$PREV_JSON" "$SERVICE/previous_post_script.txt" <<'PY'
import json,sys
text=json.loads(sys.argv[1])
open(sys.argv[2],"w").write(text)
PY

echo "[3/6] Installing additive post-PULL wrapper..."
cat > "$SERVICE/post_pull_wrapper.sh" <<EOF
#!/usr/bin/env bash
set +e
PREV_FILE="$SERVICE/previous_post_script.txt"
PREV_RC=0
if [ -s "\$PREV_FILE" ]; then
  /bin/bash -lc "\$(cat "\$PREV_FILE")"
  PREV_RC=\$?
fi
/usr/bin/python3 "$SERVICE/fks_b1_worker.py" --once
B1_RC=\$?
if [ "\$PREV_RC" -ne 0 ]; then exit "\$PREV_RC"; fi
exit "\$B1_RC"
EOF
chmod 700 "$SERVICE/post_pull_wrapper.sh"

OUR_POST="/usr/bin/bash $SERVICE/post_pull_wrapper.sh"
python3 - "$PULL_ID" "$OUR_POST" <<'PY'
import json,subprocess,sys
task_id=int(sys.argv[1]); post=sys.argv[2]
data=json.loads(subprocess.check_output(["midclt","call","cloudsync.query"]).decode())
x=next(y for y in data if int(y.get("id"))==task_id)
if (x.get("post_script") or "") != post:
    subprocess.run(["midclt","call","cloudsync.update",str(task_id),json.dumps({"post_script":post})],check=True)
PY

echo "[4/6] Installing management helper..."
cat > "$SERVICE/manage.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
SERVICE="$SERVICE"
case "\${1:-}" in
  status) /usr/bin/python3 "\$SERVICE/fks_b1_worker.py" --self-test ;;
  run) /usr/bin/python3 "\$SERVICE/fks_b1_worker.py" --once ;;
  set-host)
    [ -n "\${2:-}" ] || { echo "usage: manage.sh set-host IP"; exit 2; }
    python3 - "\$SERVICE/config.json" "\$2" <<'PY'
import json,sys,ipaddress
p,host=sys.argv[1:3]; ipaddress.ip_address(host)
d=json.load(open(p)); d["target_host"]=host
open(p,"w").write(json.dumps(d,indent=2)+"\n")
PY
    ;;
  *) echo "usage: manage.sh {status|run|set-host IP}"; exit 2 ;;
esac
EOF
chmod 700 "$SERVICE/manage.sh"

echo "[5/6] Self-test..."
/usr/bin/python3 "$SERVICE/fks_b1_worker.py" --self-test

echo "[6/6] Initial B1 status request..."
cat > "$IN_ROOT/COMMANDS/FKS-B1-INSTALL-PREFLIGHT.json" <<EOF
{
  "schema_version": 1,
  "job_id": "FKS-B1-INSTALL-PREFLIGHT",
  "action": "b1.status",
  "args": {}
}
EOF
/usr/bin/python3 "$SERVICE/fks_b1_worker.py" --once || true

echo "=== FKS B1 BRIDGE v$VERSION INSTALL COMPLETE ==="
echo "Service: $SERVICE"
echo "Target : $TARGET_HOST:$TARGET_PORT"
echo "Input  : $IN_ROOT"
echo "Output : $OUT_ROOT"
echo
echo "If B1 shows Allow USB debugging, choose Always allow + Allow."
echo "Then run: /usr/bin/python3 $SERVICE/fks_b1_worker.py --once"
