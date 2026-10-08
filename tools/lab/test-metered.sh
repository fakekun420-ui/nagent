#!/bin/sh
# tools/lab/test-metered.sh - lab del opt-in NAGENT_ALLOW_METERED (datos moviles).
# Sin red real: stub dumpsys con solo movil medido. --red-check no escribe nada.
set -eu
LAB=${LAB:-/tmp/stub-lab}
T=$LAB/metered
PREP=/sdcard/projects/nagent/tools/prep.sh
FAKEBIN=$T/fakebin
rm -rf "$T"
mkdir -p "$FAKEBIN"
cp /sdcard/projects/nagent/tools/lab/stubs/nsenter "$FAKEBIN/nsenter"
chmod +x "$FAKEBIN/nsenter"
cat > "$FAKEBIN/dumpsys" <<'EOF'
#!/bin/sh
if [ "${1:-}" = connectivity ]; then
  echo "NetworkAgentInfo{ ni{MOBILE[LTE] CONNECTED extra: } network{100} lp{} nc{} InterfaceName: rmnet_data1 }"
  echo "Active default network: 100"
elif [ "${1:-}" = netpolicy ]; then
  echo "Metered ifaces: {rmnet_data1}"
fi
exit 0
EOF
chmod +x "$FAKEBIN/dumpsys"
export PATH="$FAKEBIN:$PATH"
export NAGENT_NS="$FAKEBIN/nsenter"

pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
ko() { fail=$((fail+1)); printf '  FALLA %s  (esperado %s, real %s)\n' "$1" "$2" "$3"; }

echo "=== M1: sin opt-in, movil medido -> aborta ==="
if NAGENT_ALLOW_METERED= sh "$PREP" --red-check >/dev/null 2>&1; then
  ko "sin opt-in aborta" "rc!=0" "rc=0"
else
  ok "sin opt-in aborta"
fi

echo "=== M2: con NAGENT_ALLOW_METERED=1 -> pasa con AVISO ==="
out=$(NAGENT_ALLOW_METERED=1 sh "$PREP" --red-check 2>&1) || {
  ko "con opt-in pasa" "rc=0" "rc!=0"; out=""
}
if printf '%s' "$out" | grep -q "AVISO: red medida autorizada por usuario"; then
  ok "con opt-in pasa + AVISO en log"
else
  ko "AVISO en log" "contiene AVISO" "no lo contiene"
fi

echo
printf 'METERED: %d ok, %d FALLOS\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 2
