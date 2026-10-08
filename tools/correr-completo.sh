#!/bin/sh
set -eu
# tools/correr-completo.sh - corrida completa Etapa 0.5. NO LANZAR sin "APROBADO <sha>".
# Se lanza desacoplado una vez: nohup sh tools/correr-completo.sh >/dev/null 2>&1 &
# Una sola instancia por pidfile. No toca spike.sh: umbrales por entorno.
# Log y resumen se escriben en $LOGS por $NS (Android, no FUSE) y se copian al
# repo con sha verificado al final. TAG de wake_lock sin espacios (el kernel
# rechaza espacios en /sys/power/wake_lock; medido).
PIDFILE=/sdcard/projects/nagent/.lab/correr-completo.pid
SPIKE=/sdcard/projects/nagent/tools/spike.sh
NS="nsenter -t 1 -m --"
SLOGS=/data/adb/nagent/logs
SRAW=/sdcard/projects/nagent/docs/raw
export MAX_LOAD=8
export MAX_TEMP_PRIME=60
WAKE_TAG="nagent-completo-$$"
TS0=$(date +%s)
WLOG="$SLOGS/correr-completo-$TS0.log"

mkdir -p /sdcard/projects/nagent/.lab
if [ -e "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "ya hay una corrida completa (PID $(cat "$PIDFILE"))" >&2
  exit 1
fi
echo $$ > "$PIDFILE"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" | $NS sh -c 'cat >> "$1"' _ "$WLOG" 2>/dev/null || true; }
lock() {
  # Lock clasico sin timeout de kernel (nodo wake_lock_timeout no verificado en este
  # kernel); la renovacion cada 30 min abajo hace de timeout vivo. TAG sin espacios.
  $NS sh -c 'echo "$1" > /sys/power/wake_lock' _ "$WAKE_TAG" 2>/dev/null || true
}
unlock() {
  $NS sh -c 'echo "$1" > /sys/power/wake_unlock' _ "$WAKE_TAG" 2>/dev/null || true
}
copiar_repo() { # $1 basename en $SLOGS -> copia a $SRAW con sha verificado
  $NS cat "$SLOGS/$1" > "$SRAW/$1" 2>/dev/null || { log "FALLO copia $1 (ilegible en origen)"; return 1; }
  a=$($NS sha256sum "$SLOGS/$1" 2>/dev/null | cut -d' ' -f1 || true)
  b=$(sha256sum "$SRAW/$1" 2>/dev/null | cut -d' ' -f1 || true)
  if [ -n "$a" ] && [ "$a" = "$b" ]; then
    log "OK copia $1 sha $a"
  else
    log "FALLO copia $1 origen=${a:-<ilegible>} copia=${b:-<ilegible>}"
    return 1
  fi
}

cleanup() {
  kill "$RENEW_PID" 2>/dev/null || true
  kill "$DOG_PID" 2>/dev/null || true
  unlock "$WAKE_TAG" || true
  rm -f "$PIDFILE"
}
trap cleanup EXIT INT TERM

$NS mkdir -p "$SLOGS" || { echo "FALLO no se pudo crear $SLOGS" >&2; exit 1; }
$NS sh -c 'cat > "$1" < /dev/null' _ "$WLOG" || { echo "FALLO no se pudo crear $WLOG" >&2; exit 1; }

log "correr-completo inicio (PID $$, tag $WAKE_TAG) MAX_LOAD=$MAX_LOAD MAX_TEMP_PRIME=$MAX_TEMP_PRIME"
unlock "$WAKE_TAG" || true
lock "$WAKE_TAG"
log "wake_lock tomado: $WAKE_TAG"

# Renovacion cada 30 min en fondo
( while kill -0 $$ 2>/dev/null; do sleep 1800; lock "$WAKE_TAG" || true; done ) &
RENEW_PID=$!

# Corrida completa en fondo para poder vigilarla (salida por $NS, nunca FUSE directo)
sh "$SPIKE" 2>&1 | $NS sh -c 'cat >> "$1"' _ "$WLOG" &
SPIKE_PID=$!
log "spike lanzado PID=$SPIKE_PID"

# Watchdog global 5 h: mata SOLO si el comm sigue siendo el nuestro
(
  sleep 18000
  if kill -0 "$SPIKE_PID" 2>/dev/null; then
    comm=$(cat "/proc/$SPIKE_PID/comm" 2>/dev/null || echo "?")
    case "$comm" in
      sh|dash|bash)
        log "WATCHDOG 5h: spike colgado (PID=$SPIKE_PID comm=$comm), TERM"
        kill "$SPIKE_PID" 2>/dev/null || true
        sleep 15
        if kill -0 "$SPIKE_PID" 2>/dev/null; then
          log "WATCHDOG 5h: sigue vivo, KILL -9"
          kill -9 "$SPIKE_PID" 2>/dev/null || true
        fi
        ;;
      *)
        log "WATCHDOG 5h: PID=$SPIKE_PID reciclado (comm=$comm), NO se mata"
        ;;
    esac
  else
    log "WATCHDOG 5h: spike ya termino, nada que matar"
  fi
) &
DOG_PID=$!

wait "$SPIKE_PID" || RC=$?
RC=${RC:-0}
log "spike termino rc=$RC"
kill "$DOG_PID" 2>/dev/null || true

# Resumen: lee crudos ya copiados al repo por copiar_al_repo del spike (lectura FUSE
# OK), escribe el resumen en $LOGS por $NS y lo copia con sha. Nada se escribe
# directo en docs/raw salvo la copia verificada.
TS=$(date +%s)
RESNAME="resumen-completo-$TS.log"
{
  echo "# resumen corrida completa $TS rc=$RC MAX_LOAD=$MAX_LOAD MAX_TEMP_PRIME=$MAX_TEMP_PRIME"
  echo "## celdas bench (modelo x formato x hilos: mediana y max de pp y tg)"
  for f in "$SRAW"/bench-*.csv; do
    [ -f "$f" ] || continue
    echo "== $(basename "$f")"
    awk -F'"' 'NF>10{print $(NF-7), $(NF-3)}' "$f" 2>/dev/null | sort -n | awk '
      {v[NR]=$1; w[NR]=$2; n=NR}
      END{if(n==0){print "  sin filas"} else {print "  pp_med=" v[int((n+1)/2)] " pp_max=" v[n] " tg_med=" w[int((n+1)/2)] " tg_max=" w[n] " n=" n}}' 2>/dev/null || true
  done
  echo "## TTFT frio (cache_n bajo) vs caliente (cache_n alto)"
  grep -h "^p[0-9]" "$SRAW"/ttft-*.txt 2>/dev/null | head -20 || echo "sin ttft"
  echo "## RAM pico (VmHWM max)"
  grep -h -o "VmHWM:[ ]*[0-9]* kB" "$SRAW"/ram-*.txt "$SRAW"/sustained-*.log 2>/dev/null | sort -t: -k2 -n | tail -3 || echo "sin ram"
  echo "## RUIDOSAS"
  grep -h -c "RUIDOSA" "$SRAW"/bench-*.csv "$SRAW"/ttft-*.txt "$SRAW"/sustained-*.log 2>/dev/null || echo 0
  echo "## subtabla load<=5 (rep inicios con load1<=5)"
  grep -h "^rep[0-9] inicio" "$SRAW"/bench-*.csv 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /^load1=/){split($i,a,"="); if(a[2]+0<=5) print}}' | wc -l || true
} 2>/dev/null | $NS sh -c 'cat > "$1"' _ "$SLOGS/$RESNAME" || log "FALLO no se pudo escribir $RESNAME en $SLOGS"
log "resumen escrito en $SLOGS/$RESNAME"

copiar_repo "$(basename "$WLOG")" || true
copiar_repo "$RESNAME" || true

unlock "$WAKE_TAG" || true
log "wake_lock liberado: $WAKE_TAG"
# La ultima linea tambien debe quedar en la copia del repo: re-copiar el log tras cerrarlo
copiar_repo "$(basename "$WLOG")" || true
log "fin rc=$RC"
exit "$RC"
