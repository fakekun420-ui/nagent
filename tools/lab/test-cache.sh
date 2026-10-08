#!/bin/sh
# tools/lab/test-cache.sh - lab de la cache de prep.sh (A3). Sin red, sin /data/adb real.
# Prueba tools/prep-cache-lib.sh con NS=stub-nsenter: hit, miss, corrupta.
# cache_ok/traer nunca llaman a curl (stub curl-fail lo delata con marcador).
set -eu
LAB=${LAB:-/tmp/stub-lab}
T=$LAB/cachetest
LIB=/sdcard/projects/nagent/tools/prep-cache-lib.sh
[ -r "$LIB" ] || { echo "FALLA falta la lib: $LIB (rojo: sin implementar)"; exit 2; }
FAKEBIN=$T/fakebin
rm -rf "$T"
mkdir -p "$T/cache" "$T/dest" "$FAKEBIN" "$LAB/android/data/adb/nagent-cachetest/models"
cp /sdcard/projects/nagent/tools/lab/stubs/nsenter "$FAKEBIN/nsenter"
chmod +x "$FAKEBIN/nsenter"
cat > "$FAKEBIN/curl" <<'EOF'
#!/bin/sh
echo "STUB-CURL: la red no se usa en este lab" >&2
touch /tmp/stub-lab/cachetest/curl-llamado
exit 1
EOF
chmod +x "$FAKEBIN/curl"
export PATH="$FAKEBIN:$PATH"
CACHE=$T/cache
NS="$FAKEBIN/nsenter"
DEST=/data/adb/nagent-cachetest/models/payload.bin
. "$LIB"

pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
ko() { fail=$((fail+1)); printf '  FALLA %s  (esperado %s, real %s)\n' "$1" "$2" "$3"; }
es() { if [ "$2" = "$3" ]; then ok "$1"; else ko "$1" "$2" "$3"; fi; }

head -c 4096 /dev/urandom > "$T/payload.bin"
BYTES=$(wc -c < "$T/payload.bin" | tr -d ' ')
SHA=$(sha256sum "$T/payload.bin" | cut -d' ' -f1)

echo "=== C1: cache ausente -> falso, sin curl ==="
if cache_ok payload.bin "$BYTES" "$SHA"; then ko "ausente es falso" "rc!=0" "rc=0"; else ok "ausente es falso"; fi
es "y no se llamo a curl" 0 "$(ls "$T/curl-llamado" 2>/dev/null | wc -l | tr -d ' ')"

echo "=== C2: cache correcta -> hit, copia verificada, sin curl ==="
cp "$T/payload.bin" "$CACHE/payload.bin"
if cache_ok payload.bin "$BYTES" "$SHA"; then ok "hit es verdadero"; else ko "hit es verdadero" "rc=0" "rc!=0"; fi
if traer_de_cache payload.bin "$DEST" "$BYTES" "$SHA"; then ok "traer devuelve 0"; else ko "traer devuelve 0" "rc=0" "rc!=0"; fi
es "destino con sha correcto" "$SHA" "$($NS sha256sum "$DEST" 2>/dev/null | cut -d' ' -f1)"
es "y no se llamo a curl" 0 "$(ls "$T/curl-llamado" 2>/dev/null | wc -l | tr -d ' ')"

echo "=== C3: cache corrupta (tamano) -> falso, sin curl ==="
head -c 100 /dev/urandom > "$CACHE/payload.bin"
if cache_ok payload.bin "$BYTES" "$SHA"; then ko "corrupta es falso" "rc!=0" "rc=0"; else ok "corrupta es falso"; fi
if traer_de_cache payload.bin "$DEST" "$BYTES" "$SHA"; then ko "traer corrupta falla" "rc!=0" "rc=0"; else ok "traer corrupta falla"; fi
es "y no se llamo a curl" 0 "$(ls "$T/curl-llamado" 2>/dev/null | wc -l | tr -d ' ')"

echo "=== C4: cache con mismo tamano pero otro sha -> falso ==="
head -c "$BYTES" /dev/urandom > "$CACHE/payload.bin"
if cache_ok payload.bin "$BYTES" "$SHA"; then ko "sha distinto es falso" "rc!=0" "rc=0"; else ok "sha distinto es falso"; fi

echo
printf 'CACHE: %d ok, %d FALLOS\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 2
