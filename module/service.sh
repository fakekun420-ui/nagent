# service.sh nagent - solo tras boot + solo con enable-autostart (Bloque F).
# Contador de fallos: 5 seguidas -> no arranca y deja marca.
DEV=/data/adb/nagent
BIN=$DEV/bin
LOGS=$DEV/logs
FLAG=$DEV/enable-autostart
FAIL=$DEV/failcount
MARK=$DEV/disabled-fail
MAX=5

i=0
while [ "$(getprop sys.boot_completed)" != "1" ]; do
  sleep 10
  i=$((i + 1))
  [ "$i" -ge 60 ] && exit 0
done

[ -f "$FLAG" ] || exit 0
[ -f "$MARK" ] && exit 0
n=0
[ -f "$FAIL" ] && n=$(cat "$FAIL" 2>/dev/null || echo 0)
case "$n" in ''|*[!0-9]*) n=0 ;; esac
[ "$n" -ge "$MAX" ] && { echo "$(date -u +%FT%TZ) desactivado por $MAX fallos" >> "$LOGS/service.log"; touch "$MARK"; exit 0; }

mkdir -p "$LOGS"
export LD_LIBRARY_PATH="$BIN"
"$BIN/agentd" >> "$LOGS/service.log" 2>&1 &
PID=$!
sleep 30
if kill -0 "$PID" 2>/dev/null; then
  echo 0 > "$FAIL"
else
  echo $((n + 1)) > "$FAIL"
fi
exit 0
