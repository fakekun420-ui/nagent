# customize.sh nagent v0.1.0 - instalacion sin efecto en arranque (Bloque F).
# No crea enable-autostart. No descarga modelos. Solo shell POSIX (dash).
DEV=/data/adb/nagent
BIN=$DEV/bin
MOD=$DEV/models
LOGS=$DEV/logs
SDK_MIN=34

ui_print "- nagent v0.1.0: validando dispositivo"
D=$(getprop ro.product.device)
[ "$D" = "alioth" ] || abort "dispositivo=$D, se exige alioth"
M=$(uname -m)
[ "$M" = "aarch64" ] || abort "arch=$M, se exige aarch64"
S=$(getprop ro.build.version.sdk)
[ "$S" -ge "$SDK_MIN" ] || abort "sdk=$S, se exige >=34"

ui_print "- creando $DEV (700)"
mkdir -p "$BIN" "$MOD" "$LOGS"
chmod 700 "$DEV"
chmod 700 "$BIN" "$MOD" "$LOGS"

ui_print "- copiando binarios"
cp -f "$MODPATH/bin/agentd" "$BIN/agentd"
chmod 755 "$BIN/agentd"
[ -x "$BIN/agentd" ] || abort "agentd no quedo ejecutable"

ui_print "- token (600, solo root lo lee)"
if [ ! -f "$DEV/agentd.token" ]; then
  head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$DEV/agentd.token"
  chmod 600 "$DEV/agentd.token"
else
  ui_print "- token ya existe, se conserva"
fi

ui_print "- primera instalacion: SIN enable-autostart (arranque manual)"
ui_print "- modelos: no se descargan aqui (los pone prep.sh en $MOD)"
ui_print "- OK customize"
