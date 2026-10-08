# uninstall.sh nagent - para agentd, retira binario+token+flags.
# Conserva models/ y logs/ a proposito (6 GB no se re-descargan).
DEV=/data/adb/nagent
pkill -f "$DEV/bin/agentd" 2>/dev/null || true
rm -f "$DEV/bin/agentd" "$DEV/agentd.token" "$DEV/enable-autostart" "$DEV/failcount" "$DEV/disabled-fail" 2>/dev/null || true
# Borrado total manual (solo con autorizacion):
# rm -rf /data/adb/nagent
exit 0
