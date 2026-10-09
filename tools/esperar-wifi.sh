#!/bin/sh
set -eu
# tools/esperar-wifi.sh - vigilante de Wi-Fi. UNA sola instancia por pidfile. Solo lectura
# hasta que la red cumple; luego prep.sh --parse-only, prep.sh (maximo 3 intentos), espera
# termica de 300 s, medir-reposo.sh 10 min y, sin intervencion: dry-run verificado, smoke
# real desacoplado con evidencia. Log: docs/raw/espera-wifi.log. NO EJECUTAR aun
# (lo lanza nagent al final del turno, desacoplado con nohup, y confirma con un sondeo).
PIDFILE=/sdcard/projects/nagent/.lab/vigilante.pid
LOG=/sdcard/projects/nagent/docs/raw/espera-wifi.log
PREP=/sdcard/projects/nagent/tools/prep.sh
MEDIR=/sdcard/projects/nagent/tools/medir-reposo.sh
SPIKE=/sdcard/projects/nagent/tools/spike.sh
NS="nsenter -t 1 -m --"
SLOGS=/data/adb/nagent/logs
SRAW=/sdcard/projects/nagent/docs/raw

if [ -e "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "ya hay un vigilante (PID $(cat "$PIDFILE"))" >&2
  exit 1
fi
echo $$ > "$PIDFILE"
mkdir -p /sdcard/projects/nagent/docs/raw /sdcard/projects/nagent/.lab
trap 'rm -f "$PIDFILE"' EXIT
log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $*" >> "$LOG"; }
# Snapshots para 3a. OJO namespaces: los globs de Android se expanden DENTRO de $NS
# (un glob "$SLOGS"/* en el chroot no casa y daria vacio siempre: falso OK).
snap_android() { # stdout: listado + sha de SLOGS (vacio si no existe)
  $NS ls -A "$SLOGS" 2>/dev/null | sort
  $NS sh -c 'sha256sum "$1"/* 2>/dev/null' _ "$SLOGS" || true
}
snap_raw() { # stdout: listado + sha de SRAW (chroot, globs locales: aqui si valen)
  ls -A "$SRAW" 2>/dev/null | sort
  ( cd "$SRAW" 2>/dev/null && sha256sum * 2>/dev/null || true )
}
log "vigilante inicio (PID $$), sondeo cada 120 s hasta 24 h"
i=0
while [ "$i" -lt 720 ]; do
  if sh "$PREP" --red-check >>"$LOG" 2>&1; then
    log "red OK, parse-only:"
    if sh "$PREP" --parse-only >>"$LOG" 2>&1; then
      n=0
      ok=0
      while [ "$n" -lt 3 ]; do
        n=$((n + 1))
        log "prep intento $n/3"
        if sh "$PREP" >>"$LOG" 2>&1; then ok=1; break; fi
        log "prep fallo intento $n/3"
        sleep 120
      done
      if [ "$ok" = 1 ]; then
        log "prep OK, espera termica 300 s"
        sleep 300
        log "linea base 10 min:"
        if MUESTRAS=30 sh "$MEDIR" >>"$LOG" 2>&1; then
          log "linea base 10 min OK"
        else
          log "medir-reposo fallo (se sigue igual, queda registrado)"
        fi
        # Punto 3 (rev.): cadena sin intervencion tras la linea base.
        $NS true 2>/dev/null || { log "FALLO nsenter roto"; exit 1; }
        A1=$(snap_android); R1=$(snap_raw)
        if sh "$SPIKE" --dry-run >>"$LOG" 2>&1; then
          log "dry-run rc=0"
        else
          log "FALLO dry-run rc!=0"; exit 1
        fi
        B1=$(snap_android); R2=$(snap_raw)
        if [ "$A1" = "$B1" ] && [ "$R1" = "$R2" ]; then
          log "3a OK: dry-run no creo ni modifico nada"
        else
          log "FALLO 3a: dry-run modifico LOGS o raw"
          exit 1
        fi
        log "3b smoke real desacoplado (salida por $NS):"
        SMOKELOG="$SLOGS/smoke-$(date +%s).log"
        sh "$SPIKE" --smoke 2>&1 | $NS sh -c 'cat >> "$1"' _ "$SMOKELOG" &
        SMOKEPID=$!
        ( s=0; while kill -0 "$SMOKEPID" 2>/dev/null && [ "$s" -lt 130 ]; do
            $NS sh -c 'for p in /proc/[0-9]*/comm; do c=$(cat "$p" 2>/dev/null || true); case "$c" in llama-bench|llama-server) id=${p#/proc/}; echo "vivo PID=${id%/comm} comm=$c";; esac; done' >>"$LOG" 2>&1 || true
            sleep 10; s=$((s + 1))
          done ) &
        SAMPID=$!
        e=0
        while kill -0 "$SMOKEPID" 2>/dev/null && [ "$e" -lt 1200 ]; do sleep 30; e=$((e + 30)); done
        kill "$SAMPID" 2>/dev/null || true
        wait "$SAMPID" 2>/dev/null || true
        if kill -0 "$SMOKEPID" 2>/dev/null; then
          log "FALLO smoke colgado 1200 s"
          kill "$SMOKEPID" 2>/dev/null || true
          sleep 5
          kill -9 "$SMOKEPID" 2>/dev/null || true
          exit 1
        fi
        # Nota: $SMOKEPID es el cat receptor (asi es $! en un pipe); romperlo cierra el pipe y
        # el spike huerfano termina su bench finito y sale solo. La evidencia (3c) decide, no el rc.
        wait "$SMOKEPID" 2>/dev/null || true
        log "smoke terminado"
        log "3c evidencia (discrepancia = crudo + para):"
        $NS sh -c 'grep -hE "afinidad OK|AFINIDAD INCORRECTA" "$1"/bench-*.csv 2>/dev/null' _ "$SLOGS" | head -5 >>"$LOG" || true
        $NS grep -h "zonas por tipo" "$SMOKELOG" 2>/dev/null | head -2 >>"$LOG" || true
        $NS sh -c 'grep -h "^build_commit" "$1"/bench-*.csv 2>/dev/null' _ "$SLOGS" | head -2 >>"$LOG" || true
        $NS sh -c 'grep -h "^\"" "$1"/bench-*.csv 2>/dev/null' _ "$SLOGS" | head -6 >>"$LOG" || true
        $NS sh -c 'grep -h "rep1 inicio" "$1"/bench-*.csv 2>/dev/null' _ "$SLOGS" | head -3 >>"$LOG" || true
        $NS sh -c 'grep -h "FALLO" "$1"/bench-*.csv "$1"/ttft-*.txt 2>/dev/null' _ "$SLOGS" | head -10 >>"$LOG" || true
        $NS sh -c 'grep -h "RUIDOSA" "$1"/bench-*.csv "$1"/ttft-*.txt 2>/dev/null' _ "$SLOGS" | head -10 >>"$LOG" || true
        H=$($NS sh -c 'grep -c "^build_commit" "$1"/bench-*.csv 2>/dev/null' _ "$SLOGS" | awk -F: '{s+=$NF} END{print s+0}')
        D=$($NS sh -c 'grep -c "^\"" "$1"/bench-*.csv 2>/dev/null' _ "$SLOGS" | awk -F: '{s+=$NF} END{print s+0}')
        log "csv: cabeceras=$H filas=$D"
        if [ "$H" -lt 1 ] || [ "$D" -lt 2 ]; then
          log "FALLO formato CSV inesperado; crudo:"
          $NS sh -c 'tail -20 "$1"/bench-*.csv 2>/dev/null' _ "$SLOGS" >>"$LOG" || true
          exit 1
        fi
        log "fin OK evidencia completa"
        exit 0
      fi
      log "FALLO prep tras 3 intentos"
      exit 1
    else
      log "FALLO parse-only, se sigue vigilando"
    fi
  fi
  sleep 120; i=$((i + 1))
done
log "fin 24 h sin Wi-Fi"
exit 2
