#!/bin/sh
set -eu
# tools/correr-completo.sh - corrida completa Etapa 0.5.
# Se lanza desde la cadena del vigilante (A4-A6) o a mano desacoplado con:
#   nohup sh tools/correr-completo.sh >/dev/null 2>&1 &
# Una sola instancia por pidfile. No toca spike.sh: umbrales por entorno.
# Log y resumen se escriben en $LOGS por $NS (Android, no FUSE) y se copian al
# repo con sha verificado. TAG de wake_lock sin espacios (el kernel rechaza
# espacios en /sys/power/wake_lock; medido).
PIDFILE=/sdcard/projects/nagent/.lab/correr-completo.pid
SPIKE=/sdcard/projects/nagent/tools/spike.sh
NS="nsenter -t 1 -m --"
SLOGS=/data/adb/nagent/logs
SRAW=/sdcard/projects/nagent/docs/raw
export MAX_LOAD=8
export MAX_TEMP_PRIME=60
# A1.5: guardas ajustables por entorno. CHECK_CARGA=0 = solo se registran
# (la comprobacion de carga queda desactivada hasta medir la linea base).
BATT_MAX=${BATT_MAX:-45}
PRIME_ABORT=${PRIME_ABORT:-85}
CONSEC_ABORT=${CONSEC_ABORT:-3}
CHECK_CARGA=${CHECK_CARGA:-0}
WAKE_TAG="nagent-completo-$$"
TS0=$(date +%s)
WLOG="$SLOGS/correr-completo-$TS0.log"
TMPLOCAL=/sdcard/projects/nagent/.lab/spike-salida-$TS0.log
COPSTATE=/sdcard/projects/nagent/.lab/copiados.sha
ABORTF=/sdcard/projects/nagent/.lab/aborto-termico
# A1.6: todo inicializado (con set -eu el trap no puede ver variables sin valor).
RENEW_PID=; DOG_PID=; SPIKE_PID=; EXPIRER_PID=; COPIDOR_PID=; MON_PID=; RC=0

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" | $NS sh -c 'cat >> "$1"' _ "$WLOG" 2>/dev/null || true; }
lock() {
  # Lock clasico sin timeout de kernel (wake_lock_timeout no existe en este
  # kernel; verificado). La renovacion cada 30 min + el caducador de 4 h
  # hacen de timeout vivo. TAG sin espacios.
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
copiar_repo_q() { # como copiar_repo pero sin linea OK (para el copiador incremental)
  $NS cat "$SLOGS/$1" > "$SRAW/$1" 2>/dev/null || return 1
  a=$($NS sha256sum "$SLOGS/$1" 2>/dev/null | cut -d' ' -f1 || true)
  b=$(sha256sum "$SRAW/$1" 2>/dev/null | cut -d' ' -f1 || true)
  [ -n "$a" ] && [ "$a" = "$b" ] || return 1
}
# A1.3: mismos parsers que spike.sh (lineas 375-384, verificadas identicas por
# reality-checker). t/s = avg_ts; pp: n_gen=0; tg: n_prompt=0.
csv_cols() {
  sed -n 's/.*"\([0-9][0-9]*\)","\([0-9][0-9]*\)","\([0-9][0-9]*\)","\([^"]*\)","\([0-9][0-9]*\)","\([0-9][0-9]*\)","\([0-9.eE+-][0-9.eE+-]*\)","\([0-9.eE+-][0-9.eE+-]*\)"$/\1 \2 \7/p'
}
csv_max() {
  tipo=$1
  csv_cols | awk -v tipo="$tipo" '((tipo=="pp"&&$2==0)||(tipo=="tg"&&$1==0)){if($3>m)m=$3} END{if(m=="")print "NA";else printf "%.2f",m}'
}
csv_filas() {
  csv_cols | awk '$2==0{p++} $1==0{t++} END{print (p+0)" "(t+0)}'
}
csv_med() { # $1 pp|tg; stdin csv -> mediana avg_ts de ese tipo, o NA
  tipo=$1
  csv_cols | awk -v tipo="$tipo" '((tipo=="pp"&&$2==0)||(tipo=="tg"&&$1==0)){print $3}' \
    | sort -n | awk '{v[NR]=$1} END{if(NR==0)print "NA"; else print v[int((NR+1)/2)]}'
}
# A1.2: vivo sin zombis (el zombi conserva /proc pero ya murio).
estavivo() { # $1 pid -> 0 si vivo y no zombi
  kill -0 "$1" 2>/dev/null || return 1
  st=$(awk '{print $3}' /proc/"$1"/stat 2>/dev/null || echo "?")
  [ "$st" = "Z" ] && return 1
  return 0
}
chequea_comm() { # $1 pid, $2 patron case -> 0 si el comm casa
  comm=$(cat /proc/"$1"/comm 2>/dev/null || echo "?")
  case "$comm" in $2) return 0 ;; *) return 1 ;; esac
}

cleanup() {
  [ -z "${RENEW_PID:-}" ] || kill "$RENEW_PID" 2>/dev/null || true
  [ -z "${DOG_PID:-}" ] || kill "$DOG_PID" 2>/dev/null || true
  [ -z "${EXPIRER_PID:-}" ] || kill "$EXPIRER_PID" 2>/dev/null || true
  [ -z "${COPIDOR_PID:-}" ] || kill "$COPIDOR_PID" 2>/dev/null || true
  unlock "$WAKE_TAG" || true
  rm -f "$PIDFILE"
}
trap cleanup EXIT INT TERM

mkdir -p /sdcard/projects/nagent/.lab
if [ -e "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "ya hay una corrida completa (PID $(cat "$PIDFILE"))" >&2
  exit 1
fi
echo $$ > "$PIDFILE"

$NS mkdir -p "$SLOGS" || { echo "FALLO no se pudo crear $SLOGS" >&2; exit 1; }
$NS sh -c 'cat > "$1" < /dev/null' _ "$WLOG" || { echo "FALLO no se pudo crear $WLOG" >&2; exit 1; }
: > "$COPSTATE" 2>/dev/null || true
rm -f "$ABORTF"

log "correr-completo inicio (PID $$, tag $WAKE_TAG) MAX_LOAD=$MAX_LOAD MAX_TEMP_PRIME=$MAX_TEMP_PRIME BATT_MAX=$BATT_MAX PRIME_ABORT=$PRIME_ABORT"
# A1.5: pre-chequeo de bateria (una vez, antes de lanzar).
batt=$($NS dumpsys battery 2>/dev/null || true)
lvl=$(printf '%s' "$batt" | grep -o 'level: [0-9]*' | awk '{print $2}' | head -1 || true)
acp=$(printf '%s' "$batt" | grep -o 'AC powered: [a-z]*' | awk '{print $3}' | head -1 || true)
log "bateria: level=${lvl:-?} AC=${acp:-?} (CHECK_CARGA=$CHECK_CARGA)"
if [ "$CHECK_CARGA" = 1 ]; then
  if [ "${lvl:-0}" -lt 30 ] || [ "${acp:-false}" != true ]; then
    log "ABORTO T4: bateria baja o sin cargador (level=${lvl:-?} AC=${acp:-?})"
    exit 6
  fi
fi
unlock "$WAKE_TAG" || true
lock "$WAKE_TAG"
log "wake_lock tomado: $WAKE_TAG"

# Renovacion cada 30 min en fondo.
( while kill -0 $$ 2>/dev/null; do sleep 1800; lock "$WAKE_TAG" || true; done ) &
RENEW_PID=$!
# A1.4: caducador independiente (sobrevive a la muerte abrupta del script).
( sleep 14400; $NS sh -c 'echo "$1" > /sys/power/wake_unlock' _ "$WAKE_TAG" 2>/dev/null || true ) &
EXPIRER_PID=$!

# A1.1: SIN tuberia. TMPLOCAL es local al shell que lanza (.lab del chroot, no
# FUSE critico: se copia a $LOGS por $NS y se borra). $! ES el sh del spike y
# wait da su rc real (con tuberia $! era el consumidor y el rc se perdia).
rm -f "$TMPLOCAL"
sh "$SPIKE" > "$TMPLOCAL" 2>&1 &
SPIKE_PID=$!
log "spike lanzado PID=$SPIKE_PID"

# A1.7: copiador incremental cada 60 s (con estado sha; callado salvo FALLO).
(
  while kill -0 "$SPIKE_PID" 2>/dev/null; do
    sleep 60
    for f in $($NS ls -A "$SLOGS" 2>/dev/null || true); do
      case "$f" in *.log|*.csv|*.txt) ;; *) continue ;; esac
      s=$($NS sha256sum "$SLOGS/$f" 2>/dev/null | cut -d' ' -f1 || true)
      [ -n "$s" ] || continue
      if ! grep -q -F "$s $f" "$COPSTATE" 2>/dev/null; then
        copiar_repo_q "$f" && { grep -v -F " $f" "$COPSTATE" 2>/dev/null > "$COPSTATE.tmp" || true; printf '%s %s\n' "$s" "$f" >> "$COPSTATE.tmp"; mv "$COPSTATE.tmp" "$COPSTATE"; }
      fi
    done
  done
) &
COPIDOR_PID=$!

# A1.5: monitor termico (lee los SNAP que el propio spike deja en los CSV).
(
  cal=0; pri=0
  while kill -0 "$SPIKE_PID" 2>/dev/null; do
    sleep 60
    kill -0 "$SPIKE_PID" 2>/dev/null || break
    ult=$($NS sh -c 'grep -h "^rep[0-9] inicio" "$1"/bench-*.csv 2>/dev/null | tail -1' _ "$SLOGS" || true)
    [ -n "$ult" ] || continue
    bc=$(printf '%s' "$ult" | grep -o 'battC=[0-9]*' | cut -d= -f2 || true)
    pr=$(printf '%s' "$ult" | grep -o 'prime=[0-9]*' | cut -d= -f2 || true)
    if [ -n "$bc" ] && [ "$bc" -ge "$BATT_MAX" ]; then cal=$((cal+1)); else cal=0; fi
    if [ -n "$pr" ] && [ "$pr" -ge "$PRIME_ABORT" ]; then pri=$((pri+1)); else pri=0; fi
    if [ "$cal" -ge "$CONSEC_ABORT" ] || [ "$pri" -ge "$CONSEC_ABORT" ]; then
      log "ABORTO T4: battC=${bc:-?} prime=${pr:-?} 3 seguidas"
      touch "$ABORTF"
      if chequea_comm "$SPIKE_PID" 'sh|dash|bash'; then kill "$SPIKE_PID" 2>/dev/null || true; fi
      break
    fi
  done
) &
MON_PID=$!

# Watchdog global 5 h: mata SOLO si el comm sigue siendo el nuestro (sin $NS:
# el objetivo vive en el chroot).
(
  sleep 18000
  if estavivo "$SPIKE_PID"; then
    if chequea_comm "$SPIKE_PID" 'sh|dash|bash'; then
      comm=$(cat /proc/"$SPIKE_PID"/comm 2>/dev/null || echo "?")
      log "WATCHDOG 5h: spike colgado (PID=$SPIKE_PID comm=$comm), TERM"
      kill "$SPIKE_PID" 2>/dev/null || true
      sleep 15
      if estavivo "$SPIKE_PID"; then
        log "WATCHDOG 5h: sigue vivo, KILL -9"
        kill -9 "$SPIKE_PID" 2>/dev/null || true
      fi
    else
      log "WATCHDOG 5h: PID=$SPIKE_PID reciclado, NO se mata"
    fi
  else
    log "WATCHDOG 5h: spike ya termino, nada que matar"
  fi
) &
DOG_PID=$!

wait "$SPIKE_PID" || RC=$?
log "spike termino rc=$RC"
kill "$DOG_PID" 2>/dev/null || true
wait "$DOG_PID" 2>/dev/null || true
kill "$COPIDOR_PID" 2>/dev/null || true
wait "$COPIDOR_PID" 2>/dev/null || true
kill "$MON_PID" 2>/dev/null || true
wait "$MON_PID" 2>/dev/null || true
if [ -e "$ABORTF" ]; then
  log "fin por ABORTO termico T4"
  RC=7
fi
# Vuelca la salida del spike al WLOG (redireccion DENTRO de $NS) y limpia.
$NS sh -c 'cat "$2" >> "$1"' _ "$WLOG" "$TMPLOCAL" 2>/dev/null || log "FALLO al volcar salida del spike a $WLOG"
rm -f "$TMPLOCAL"

# Resumen: lee crudos del repo (copiados por el spike y el copiador), escribe en
# $LOGS por $NS y copia con sha. pp: n_gen=0; tg: n_prompt=0; t/s = avg_ts.
TS=$(date +%s)
RESNAME="resumen-completo-$TS.log"
{
  echo "# resumen corrida completa $TS rc=$RC MAX_LOAD=$MAX_LOAD MAX_TEMP_PRIME=$MAX_TEMP_PRIME"
  for f in "$SRAW"/bench-*.csv; do
    [ -f "$f" ] || continue
    echo "== $(basename "$f")"
    ft=$(csv_filas < "$f"); set -- $ft
    echo "  filas pp=$1 tg=$2"
    echo "  pp_max=$(csv_max pp < "$f") pp_med=$(csv_med pp < "$f") tg_max=$(csv_max tg < "$f") tg_med=$(csv_med tg < "$f")"
  done
  echo "## TTFT frio vs caliente (por cache_n)"
  for t in "$SRAW"/ttft-*.txt; do
    [ -f "$t" ] || continue
    echo "== $(basename "$t")"
    fr=$(grep '^p[0-9]' "$t" 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i~/^cache_n=/){split($i,a,"="); print a[2]+0, $0}}}' | sort -n | head -1)
    ca=$(grep '^p[0-9]' "$t" 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i~/^cache_n=/){split($i,a,"="); print a[2]+0, $0}}}' | sort -n | tail -1)
    echo "  frio: ${fr:-sin-datos}"
    echo "  caliente: ${ca:-sin-datos}"
  done
  [ -n "$(ls "$SRAW"/ttft-*.txt 2>/dev/null)" ] || echo "sin ttft"
  echo "## RAM pico (VmHWM max kB)"
  grep -h -o "VmHWM:[ ]*[0-9]* kB" "$SRAW"/ram-*.txt "$SRAW"/sustained-*.log 2>/dev/null | grep -o '[0-9]*' | sort -n | tail -1 || echo "sin ram"
  echo "## RUIDOSAS (suma de contadores por fichero)"
  grep -h -c "RUIDOSA" "$SRAW"/bench-*.csv "$SRAW"/ttft-*.txt "$SRAW"/sustained-*.log 2>/dev/null | awk -F: '{s+=$NF} END{print s+0}'
  echo "## subtabla load<=5"
  grep -h "^rep[0-9] inicio" "$SRAW"/bench-*.csv 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /^load1=/){split($i,a,"="); if(a[2]+0<=5) print}}' | wc -l | tr -d ' '
} 2>/dev/null | $NS sh -c 'cat > "$1"' _ "$SLOGS/$RESNAME" || log "FALLO no se pudo escribir $RESNAME en $SLOGS"
log "resumen escrito en $SLOGS/$RESNAME"

copiar_repo "$(basename "$WLOG")" || true
copiar_repo "$RESNAME" || true

unlock "$WAKE_TAG" || true
kill "$EXPIRER_PID" 2>/dev/null || true
kill "$RENEW_PID" 2>/dev/null || true
log "wake_lock liberado: $WAKE_TAG"
copiar_repo "$(basename "$WLOG")" || true
log "fin rc=$RC"
exit "$RC"
