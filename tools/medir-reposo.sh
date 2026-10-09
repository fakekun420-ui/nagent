#!/bin/sh
# tools/medir-reposo.sh - linea base en reposo. SOLO LECTURA: stdout, cero ficheros.
# Muestrea cada 20 s (MUESTRAS, default 9 = 3 min): loadavg (global del kernel, chroot) + cpu4-7 y bateria
# por $NS (lecturas /sys, sin escribir nada). Ejecutar a mano; nunca desde otro script.
NS="nsenter -t 1 -m --"

zona() { # $1 tipo -> ruta de zona o vacio
  $NS sh -c 'for z in /sys/class/thermal/thermal_zone*; do
               [ -r "$z/type" ] || continue
               if [ "$(cat "$z/type")" = "$1" ]; then echo "$z"; exit 0; fi
             done
             exit 1' -- "$1" 2>/dev/null || true
}

temp() { # $1 zona -> grados o NA
  [ -n "${1:-}" ] || { echo NA; return 0; }
  t=$($NS cat "$1/temp" 2>/dev/null || true)
  [ -n "${t:-}" ] || { echo NA; return 0; }
  case "$t" in ''|*[!0-9-]*) echo NA; return 0 ;; esac
  echo $((t / 1000))
}

Z4=$(zona cpu-1-4-usr); Z5=$(zona cpu-1-5-usr); Z6=$(zona cpu-1-6-usr)
Z7=$(zona cpu-1-7-usr); ZB=$(zona battery)
echo "# zonas: 4=${Z4:-?} 5=${Z5:-?} 6=${Z6:-?} 7=${Z7:-?} batt=${ZB:-?}"
echo "# t load1 cpu4 cpu5 cpu6 prime battC (grados)"
N=${MUESTRAS:-9}
i=0
while [ "$i" -lt "$N" ]; do
  printf 't=%ss load1=%s cpu4=%s cpu5=%s cpu6=%s prime=%s battC=%s\n' \
    "$((i * 20))" "$(cut -d' ' -f1 /proc/loadavg)" \
    "$(temp "$Z4")" "$(temp "$Z5")" "$(temp "$Z6")" "$(temp "$Z7")" "$(temp "$ZB")"
  i=$((i + 1))
  [ "$i" -lt "$N" ] && sleep 20
done
exit 0
