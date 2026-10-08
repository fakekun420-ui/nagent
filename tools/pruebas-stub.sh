#!/bin/sh
# tools/pruebas-stub.sh - arnes contra tools/lab/stubs/* (diseno $LAB/android). NO toca /data/adb.
#
# Diseno:
#   - el script corre con rutas de PRODUCCION (/data/adb/nagent/...): NAGENT_DEV/BIN/MOD/LOGS
#     NO se sobreescriben, para que el traductor sea lo unico que las redirige;
#   - el stub nsenter traduce /data/adb/* y /sys/* hacia $LAB/android (incluido dentro de
#     cadenas `sh -c`), y deja /proc intacto (comm real de los vivos);
#   - LOGS existe SOLO en el arbol android; si el script escribe desde el chroot, el control
#     negativo lo delata tras cada prueba;
#   - bench habla CSV real (cabecera sin comillas, filas entrecomilladas, pp:n_gen=0 tg:n_prompt=0);
#   - curl recibe body por stdin y devuelve SSE+tiempo por stdout (ultima linea = primer byte);
#   - cada prueba trae su caso rojo documentado; tras cada prueba corre el control negativo.
# NO hay stub de pgrep: que no exista ES la asercion del punto 3 (v2).
# Este fichero no se ejecuta hasta que el laboratorio este autorizado (ver tools/lab/ORDEN-MONTAR).
set -eu

LAB=${LAB:-/tmp/stub-lab}
# LAB fijo: el traductor y el pidfile llevan /tmp/stub-lab horneado. No cambiar sin regenerar.
SCRIPT=${SCRIPT:-/sdcard/projects/nagent/tools/spike.sh}
REPO_LAB=/sdcard/projects/nagent/tools/lab
STUB=$LAB/stubs
ANDROID=$LAB/android
ANDROID_BIN=$ANDROID/data/adb/nagent/bin
ANDROID_MOD=$ANDROID/data/adb/nagent/models
ANDROID_LOGS=$ANDROID/data/adb/nagent/logs
LIVE=$LAB/live

# Modelo que se rompe a proposito. Vacio = ninguno se rompe (para probar el ganador del bench).
STUB_BREAK_MODEL=${STUB_BREAK_MODEL-qwen2.5-3b-instruct-q4_0.gguf}

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
ko()   { fail=$((fail+1)); printf '  FALLA %s  (esperado %s, real %s)\n' "$1" "$2" "$3"; }
es()   { if [ "$2" = "$3" ]; then ok "$1"; else ko "$1" "$2" "$3"; fi; }
cont() { if printf '%s' "$2" | grep -q -- "$3"; then ok "$1"; else ko "$1" "contiene '$3'" "no lo contiene"; fi; }
no_cont(){ if printf '%s' "$2" | grep -q -- "$3"; then ko "$1" "NO contiene '$3'" "si lo contiene"; else ok "$1"; fi; }
vacia(){ if [ -z "$2" ]; then ok "$1"; else ko "$1" "vacio" "$2"; fi; }

# Control negativo: /data/adb/nagent del chroot debe seguir VACIO tras cada prueba
# (existe preexistente y vacio desde antes del lab: Oct 2, 0 ficheros; lo que delata fuga son
# FICHEROS nuevos, no el directorio). Rojo: cualquier escritura fuera del traductor lo llena.
control_neg() { # $1 nombre de la prueba
  if [ -n "$(ls -A /data/adb/nagent 2>/dev/null)" ]; then
    ko "CONTROL NEGATIVO $1: /data/adb/nagent no esta vacio" "vacio" "$(ls /data/adb/nagent 2>/dev/null | tr '\n' ' ')"
  else
    ok "control negativo $1: chroot limpio"
  fi
}

montar() {
  [ -n "$LAB" ] || { echo "LAB vacio, no borro nada" >&2; exit 99; }
  rm -rf "$LAB"
  mkdir -p "$STUB" "$LIVE" "$LAB/raw" "$ANDROID_BIN" "$ANDROID_MOD" "$ANDROID_LOGS"
  cp "$REPO_LAB/stubs/nsenter" "$STUB/nsenter"
  cp "$REPO_LAB/stubs/taskset" "$STUB/taskset"
  cp "$REPO_LAB/stubs/sha256sum" "$STUB/sha256sum"
  cp "$REPO_LAB/stubs/curl" "$STUB/curl"
  cp "$REPO_LAB/stubs/llama-bench" "$ANDROID_BIN/llama-bench"
  cp "$REPO_LAB/stubs/llama-server" "$ANDROID_BIN/llama-server"
  cp /bin/sleep "$LIVE/llama-server"
  cp /bin/sleep "$LIVE/llama-bench"
  for m in qwen2.5-1.5b-instruct-q4_0 qwen2.5-1.5b-instruct-q4_k_m \
           qwen2.5-3b-instruct-q4_0 qwen2.5-3b-instruct-q4_k_m; do
    cp /dev/null "$ANDROID_MOD/$m.gguf"
  done
  for z in 11 12 13 14 92; do
    mkdir -p "$ANDROID/sys/class/thermal/thermal_zone$z"
    cp "$REPO_LAB/android/sys/class/thermal/thermal_zone$z/type" "$ANDROID/sys/class/thermal/thermal_zone$z/type"
    cp "$REPO_LAB/android/sys/class/thermal/thermal_zone$z/temp" "$ANDROID/sys/class/thermal/thermal_zone$z/temp"
  done
  rm -f "$LAB/server.pid"
  chmod +x "$STUB/nsenter" "$STUB/taskset" "$STUB/sha256sum" "$STUB/curl" \
           "$ANDROID_BIN/llama-bench" "$ANDROID_BIN/llama-server" \
           "$LIVE/llama-server" "$LIVE/llama-bench"
}

correr() { # $1 etiqueta, resto args del script. NAGENT_DEV/BIN/MOD/LOGS a proposito SIN fijar:
  etiqueta=$1; shift  # el script usa sus rutas de produccion y el traductor las redirige al lab.
  rc=0
  PATH="$STUB:$PATH" \
  NAGENT_REPO="$LAB" NAGENT_RAWDIR="$LAB/raw" \
  STUB_BREAK_MODEL="$STUB_BREAK_MODEL" \
  COOLDOWN_S=0 MAX_LOAD=9999 MAX_TEMP_PRIME=999 SUSTAIN_S=3 TTFT_REQS=10 \
  timeout 180 sh "$SCRIPT" "$@" > "$LAB/salida-$etiqueta.txt" 2>&1 || rc=$?
  printf '%s' "$rc" > "$LAB/rc-$etiqueta.txt"
  if [ "$rc" -eq 124 ]; then
    echo "  FALLA la corrida '$etiqueta' se quedo colgada 180 s (timeout)"
    fail=$((fail + 1))
  fi
  return 0
}

echo "=== 0) EL ARNES NO SE LLAMA A SI MISMO ==="
montar
# Rojo: dos nsenter encadenados retornan 0 en vez de abortar con 97 (funden los stubs).
PATH="$STUB:$PATH" NSENTER_STUB_DEPTH=1 "$STUB/nsenter" -t 1 -m -- true >/dev/null 2>&1 || true
prof=$("$STUB/nsenter" -t 1 -m -- sh -c 'echo ${NSENTER_STUB_DEPTH:-0}' 2>/dev/null || echo ERR)
es "la guarda de profundidad permite el primer nivel" 1 "$prof"
if NSENTER_STUB_DEPTH=1 "$STUB/nsenter" -t 1 -m -- "$STUB/nsenter" -t 1 -m -- true >/dev/null 2>&1; then
  ko "encadenar nsenter aborta" "salida distinta de 0" "0"
else
  ok "encadenar nsenter aborta en vez de encadenar (no puede recursar)"
fi
no_cont "ninguna corrida del arnes imprime STUB-FATAL" "$(cat "$LAB"/salida-*.txt 2>/dev/null || true)" "STUB-FATAL"
control_neg "0-no-recurse"

echo
echo "=== 1) --dry-run NO CREA NADA ==="
montar
# Rojo pre-fix (trap antes del DRY): el exit 0 disparaba al_salir y copiar_al_repo escribia.
correr dry --dry-run
if [ -e "$ANDROID_LOGS" ] && [ -n "$(ls -A "$ANDROID_LOGS" 2>/dev/null)" ]; then
  ko "--dry-run no deja logs" "vacio o ausente" "con ficheros"
else
  ok "--dry-run no deja logs"
fi
n=$(ls -A "$LAB/raw" 2>/dev/null | wc -l | tr -d ' ')
es "--dry-run no escribe en el repo" 0 "$n"
cont "el plan dice que no crea nada" "$(cat "$LAB/salida-dry.txt")" "NO SE CREA NADA"
cont "el plan anuncia la segunda pasada de prefijo" "$(cat "$LAB/salida-dry.txt")" "B2 ttft sobre el 3B que gane el bench"
control_neg "1-dry-run"

echo
echo "=== 2) SMOKE: una sola celda, 1.5B Q4_0 ==="
montar
correr smoke --smoke
# Rojo: sin el exit 0 del smoke, la corrida seguiria con prefijo y sostenido.
n=$(ls "$ANDROID_LOGS"/bench-*.csv 2>/dev/null | wc -l | tr -d ' ')
es "smoke crea exactamente 1 csv de bench" 1 "$n"
f=$(ls "$ANDROID_LOGS"/bench-*.csv 2>/dev/null | head -1)
cont "el nombre lleva modelo y hilos" "$(basename "$f")" "qwen2.5-1.5b-instruct-q4_0-t3"
no_cont "el smoke NO hace la prueba de prefijo" "$(ls "$ANDROID_LOGS")" "ttft"
no_cont "el smoke NO hace el sostenido" "$(ls "$ANDROID_LOGS")" "sustained"
control_neg "2-smoke"

echo
echo "=== 3) CARRERA COMPLETA: 8 celdas distintas, ninguna encima de otra ==="
montar
STUB_BREAK_MODEL="qwen2.5-3b-instruct-q4_0.gguf"
correr full
# Rojo (etiqueta sin modelo, bug v1): el 2o modelo sobreescribia al 1o y quedaban 4 de 8.
benchs=$(ls "$ANDROID_LOGS"/bench-*.csv 2>/dev/null | wc -l | tr -d ' ')
es "hay 8 csv de bench (4 modelos x 2 hilos)" 8 "$benchs"
distintos=$(ls "$ANDROID_LOGS"/bench-*.csv 2>/dev/null | sed 's/.*\///' | sort -u | wc -l | tr -d ' ')
es "los 8 nombres son DISTINTOS" 8 "$distintos"
conmodelo=0
for f in "$ANDROID_LOGS"/bench-*.csv; do
  [ -e "$f" ] || continue
  b=$(basename "$f")
  case "$b" in
    *-t3.csv|*-t4.csv) conmodelo=$((conmodelo+1)) ;;
  esac
done
es "los 8 nombres llevan modelo Y numero de hilos" 8 "$conmodelo"
control_neg "3-full"

echo
echo "=== 4) UN FALLO MARCA FALLO, NUNCA 0 tok/s ==="
# Rojo: para romper AMBOS 3B hace falta correr con ellos rotos (el full de la sec-3 solo rompe q4_0).
montar
STUB_BREAK_MODEL="qwen2.5-3b-instruct-q4_0.gguf qwen2.5-3b-instruct-q4_k_m.gguf"
correr fallos
# Rojo: bench que falla (exit 3) o sin filas (exit 0 mudo) leido como numero inventado.
logfallo="$ANDROID_LOGS/bench-qwen2.5-3b-instruct-q4_0-t3.csv"
cont "el modelo que falla sale con FALLO y su motivo" "$(cat "$logfallo" 2>/dev/null || true)" "FALLO"
cont "el motivo dice que el bench devolvio error" "$(cat "$logfallo" 2>/dev/null || true)" "devolvio error"
logvacio="$ANDROID_LOGS/bench-qwen2.5-3b-instruct-q4_k_m-t3.csv"
cont "el que sale sin filas TAMBIEN marca FALLO" "$(cat "$logvacio" 2>/dev/null || true)" "sin fila"
vacias=0
for f in "$ANDROID_LOGS"/*.csv "$ANDROID_LOGS"/*.txt; do
  case "$f" in *manifiesto*) continue ;; esac
  [ -e "$f" ] || continue
  if [ ! -s "$f" ]; then vacias=$((vacias+1)); fi
done
es "ningun log de medicion ha quedado vacio" 0 "$vacias"
control_neg "4-fallo"

echo
echo "=== 5) TTFT: prompt_ms/cache_n mandan, primer byte contrasta ==="
# Rojo: timings ausentes leidos como 0, o primer byte tomado como metrica principal.
ttft="$ANDROID_LOGS/ttft-qwen2.5-1.5b-instruct-q4_0-prefijo.txt"
contenido=$(cat "$ttft" 2>/dev/null || true)
cont "la metrica principal es prompt_ms" "$contenido" "prompt_ms=30.958"
cont "y cache_n (tokens reutilizados)" "$contenido" "cache_n=236"
cont "lee prompt_n" "$contenido" "prompt_n=1"
cont "lee predicted_per_second" "$contenido" "tok_s=52.94494935437416"
cont "el primer byte va marcado como contraste" "$contenido" "0.187(contraste)"
peticiones=$(grep -c '^p[0-9]' "$ttft" 2>/dev/null || echo 0)
es "las 10 peticiones dejan linea" 10 "$peticiones"
cont "la peticion que el curl rompe queda como FALLO" "$contenido" "FALLO"
no_cont "y NO se escribe un 0 tok/s como si fuera un resultado" "$contenido" "tok_s=0$"
no_cont "tampoco un prompt_ms=0" "$contenido" "prompt_ms=0"
# Punto 3 rev. v6, comprobacion explicita: PID y comm tras lanzar. La ultima linea "PID propio
# confirmado" corresponde al ultimo server lanzado, igual que server.pid.
conf=$(grep -h "PID propio confirmado" "$LAB/salida-fallos.txt" 2>/dev/null | tail -1 || true)
pid=$(printf '%s' "$conf" | awk '{print $5}')
comm=$(printf '%s' "$conf" | sed 's/.*comm=//')
es "el comm tras lanzar es el del binario final" "llama-server" "$comm"
es "el PID capturado es el del vivo (pidfile del stub)" "$(cat "$LAB/server.pid" 2>/dev/null || echo ?)" "$pid"
control_neg "5-ttft"

echo
echo "=== 6) SHA-256: el fallo tambien corta ==="
montar
# Rojo: con SHA incorrecto el script mide igual (no aborta) y crea logs de medicion.
cat > "$LAB/stubs/sha256sum" <<'EOF'
#!/bin/sh
for a in "$@"; do case "$a" in *=*) printf '0000000000000000000000000000000000000000000000000000000000000000  %s\n' "$a" ;; *) printf '0000000000000000000000000000000000000000000000000000000000000000  %s\n' "$a" ;; esac; done
EOF
chmod +x "$LAB/stubs/sha256sum"
correr shafallo
cont "con SHA incorrecto el script ABORTA" "$(cat "$LAB/salida-shafallo.txt")" "SHA-256 no cuadra"
cont "y no se pone a medir" "$(cat "$LAB/salida-shafallo.txt")" "No se mide sobre ficheros no verificados"
n=$(ls "$ANDROID_LOGS"/bench-*.csv 2>/dev/null | wc -l | tr -d ' ')
es "y no ha creado ningun log de medicion" 0 "$n"
control_neg "6-sha"

echo
echo "=== 7) ESTADO POR CELDA: carga, prime y BATERIA (zonas falsas fijas) ==="
montar
STUB_BREAK_MODEL="qwen2.5-3b-instruct-q4_0.gguf"
correr batt
# Rojo: sin battC (zona battery no encontrada) o sin snapshot por celda.
celdas=$(grep -h 'rep[0-9] inicio' "$ANDROID_LOGS"/bench-*.csv 2>/dev/null | wc -l | tr -d ' ')
if [ "$celdas" -gt 0 ]; then ok "las celdas registran su estado inicial ($celdas lineas)"; else ko "lineas de inicio por celda" ">0" "0"; fi
conbatt=$(grep -h 'rep[0-9] inicio' "$ANDROID_LOGS"/bench-*.csv 2>/dev/null | grep -c 'battC=' || true)
es "TODAS las celdas llevan battC (temperatura de bateria)" "$celdas" "$conbatt"
cont "prime es 45 (zona falsa zone14)" "$(grep -h 'rep[0-9] inicio' "$ANDROID_LOGS"/bench-*.csv 2>/dev/null || true)" "prime=45"
cont "battC es 28 (zona falsa battery)" "$(grep -h 'rep[0-9] inicio' "$ANDROID_LOGS"/bench-*.csv 2>/dev/null || true)" "battC=28"
cont "y el estado tambien va en las lineas de TTFT" "$(cat "$ANDROID_LOGS"/ttft-*.txt 2>/dev/null || true)" "battC="
control_neg "7-batt"

echo
echo "=== 8) MATAR SOLO POR PID PROPIO (estatico) ==="
# Rojo: cualquier pgrep/pkill/killall invocado para matar (en codigo, no en comentarios).
src=$(cat "$SCRIPT")
codigo=$(printf '%s' "$src" | grep -vE '^[[:space:]]*#')
no_cont "el codigo NO invoca pgrep" "$codigo" "pgrep"
no_cont "el codigo NO invoca pkill" "$codigo" "pkill"
no_cont "el codigo NO invoca killall" "$codigo" "killall"
vmat=$(printf '%s' "$codigo" | grep -cE '(^|[[:space:];])(\$NS +)?kill +"' || true)
if [ "$vmat" -ge 1 ]; then ok "hay kill por PID variable ($vmat lineas)"; else ko "kill por PID" ">=1" "$vmat"; fi
cont "y parar_server verifica comm justo antes" "$codigo" "esta VIVO pero no es nuestro"
cont "el laboratorio NO tiene stub de pgrep (si hiciera falta, reventaria)" "$(ls "$STUB")" "nsenter"
if ls "$STUB" | grep -q pgrep; then ko "no hay pgrep en el laboratorio" "no existe" "existe"; else ok "no hay pgrep en el laboratorio"; fi
sr=$(ls "$ANDROID_LOGS"/server-*.log 2>/dev/null | head -1)
if [ -e "$sr" ]; then
  cont "el arranque del server deja constancia de que el PID es propio" "$(cat "$LAB"/salida-batt.txt)" "PID propio confirmado"
fi
control_neg "8-pid"

echo
echo "=== 9) llama-server con -np 1 y -c explicito ==="
# Rojo: sin --np 1 el default auto decide slots y la medida de prefijo se contamina.
cont "el arranque fija -np 1" "$src" "--np 1"
cont "el contexto se pasa por variable, no de serie" "$src" '--ctx-size $SRV_CTX'
n=$(grep -c 'np.*default: -1' "$ANDROID_LOGS"/server-help.txt 2>/dev/null || echo 0)
if [ "$n" -ge 1 ]; then ok "el --help del laboratorio declara que el default de -np es -1 (auto)"; else ko "default de -np leido del --help" ">=1" "$n"; fi
control_neg "9-np"

echo
echo "=== 10) SEGUNDA PASADA DE PREFIJO SOBRE EL 3B QUE GANA ==="
montar
STUB_BREAK_MODEL=""
correr ganador
# Rojo: ganador mal elegido (o empate por filas inventadas) corre la 2a pasada sobre otro modelo.
gan=$(cat "$ANDROID_LOGS"/ganador-3b.txt 2>/dev/null || true)
cont "el ganador se lee de los logs del bench" "$gan" "tg128"
cont "y se elige el 3B con MEJOR tg" "$gan" "qwen2.5-3b-instruct-q4_k_m.gguf"
n=$(ls "$ANDROID_LOGS"/ttft-*.txt 2>/dev/null | wc -l | tr -d ' ')
es "hay DOS ficheros de TTFT: el del 1.5B y el del 3B ganador" 2 "$n"
if ls "$ANDROID_LOGS"/ttft-qwen2.5-3b-instruct-q4_k_m-prefijo.txt >/dev/null 2>&1; then
  ok "la segunda pasada es sobre el 3B ganador"
else
  ko "la segunda pasada es sobre el 3B ganador" "existe el fichero" "no existe"
fi
control_neg "10-ganador"

echo
echo "=== 11) SI NINGUN 3B DA TG, LA SEGUNDA PASADA NO SE HACE ==="
montar
STUB_BREAK_MODEL="qwen2.5-3b-instruct-q4_0.gguf qwen2.5-3b-instruct-q4_k_m.gguf"
correr singanador
# Rojo: segunda pasada sobre nombre vacio o inventado cuando no hay ganador.
cont "lo dice en la salida" "$(cat "$LAB/salida-singanador.txt")" "la segunda pasada de prefijo NO se hace"
n=$(ls "$ANDROID_LOGS"/ttft-*3b* 2>/dev/null | wc -l | tr -d ' ')
es "y no hay TTFT de ningun 3B" 0 "$n"
control_neg "11-singanador"

echo
echo "=== 12) EXIT 5 CONSERVA EL CODIGO (el trap no se lo come) ==="
montar
STUB_BREAK_MODEL="qwen2.5-3b-instruct-q4_0.gguf"
# Rojo (trap con `set +e` antes de `rc=$?`): el codigo real saldria como 0.
sleep 600 & BUSY=$!
echo "$BUSY" > "$LAB/server.pid"
correr puertoocupado
kill "$BUSY" 2>/dev/null || true
wait "$BUSY" 2>/dev/null || true
es "el codigo real de salida es 5" 5 "$(cat "$LAB/rc-puertoocupado.txt")"
cont "y dice por que (puerto ocupado antes de lanzar)" "$(cat "$LAB/salida-puertoocupado.txt")" "ya responde antes de lanzar"
control_neg "12-exit5"

echo
echo "=== 13) --dry-run CON LOGS EXISTENTE NO TOCA NADA ==="
montar
# Rojo pre-fix (trap antes del DRY): al salir, al_salir veia LOGS y copiaba al repo.
FISICO="$ANDROID_LOGS"
# Diseno android futuro: FISICO=$LAB/android/data/adb/nagent/logs (cambiar solo esta linea).
mkdir -p "$FISICO"
echo "ya habia algo" > "$FISICO/previo.txt"
antes_arbol=$(cd "$FISICO" && find . -type f | sort)
antes_sha=$(cd "$FISICO" && find . -type f -exec sha256sum {} + | sort -k2 | sha256sum | cut -d' ' -f1)
antes_raw=$(cd "$LAB/raw" && find . -type f | sort)
correr dryexist --dry-run
despues_arbol=$(cd "$FISICO" && find . -type f | sort)
despues_sha=$(cd "$FISICO" && find . -type f -exec sha256sum {} + | sort -k2 | sha256sum | cut -d' ' -f1)
despues_raw=$(cd "$LAB/raw" && find . -type f | sort)
es "el listado de LOGS es identico" "$antes_arbol" "$despues_arbol"
es "el sha conjunto de LOGS es identico" "$antes_sha" "$despues_sha"
es "el repo/raw tampoco cambia" "$antes_raw" "$despues_raw"
control_neg "13-dryexist"

echo
echo "=== 14) backends-*.txt EN EL ARBOL ANDROID, CHROOT VACIO (punto 1 rev. v7) ==="
montar
STUB_BREAK_MODEL=""
correr backend
# Rojo pre-fix (redireccion abierta por el chroot): el `>` apuntaba a /data/adb/nagent/logs del
# chroot (inexistente ahi) y el fichero NO aparecia en el arbol Android; o peor, si el dir
# existiera, el fichero caia en el chroot real y lo delataba el control negativo.
f=$(ls "$ANDROID_LOGS"/backends-*.txt 2>/dev/null | head -1)
if [ -n "$f" ]; then ok "backends-*.txt existe en el arbol Android ($(basename "$f"))"; else ko "backends-*.txt en arbol Android" "existe" "no existe"; fi
cont "su contenido viene del grep (system_info)" "$(cat "$f" 2>/dev/null || true)" "system_info"
fuera=$(find "$LAB" -name 'backends-*' 2>/dev/null | grep -v "$ANDROID" | grep -v "$LAB/raw/" || true)
vacia "ningun backends fuera del arbol android" "$fuera"
control_neg "14-backends"

echo
echo "=== 15) SMOKE-SERVER: solo TTFT 1.5B, 3 peticiones ==="
montar
STUB_BREAK_MODEL=""
correr smokeserver --smoke-server
# Rojo pre-diff: sin flag --smoke-server el script ignora el argumento y hace la corrida completa.
n=$(ls "$ANDROID_LOGS"/bench-*.csv 2>/dev/null | wc -l | tr -d ' ')
es "smoke-server no hace bench" 0 "$n"
n=$(ls "$ANDROID_LOGS"/ttft-*.txt 2>/dev/null | wc -l | tr -d ' ')
es "smoke-server crea exactamente 1 ttft" 1 "$n"
cont "es el prefijo del 1.5B" "$(ls "$ANDROID_LOGS"/ttft-*.txt 2>/dev/null)" "qwen2.5-1.5b-instruct-q4_0-prefijo"
es "deja 3 peticiones" 3 "$(grep -h -c '^p[0-9]' "$ANDROID_LOGS"/ttft-*.txt 2>/dev/null || echo 0)"
no_cont "sin sostenido" "$(ls "$ANDROID_LOGS")" "sustained"
no_cont "sin segunda pasada 3B" "$(ls "$ANDROID_LOGS")" "3b-instruct"
control_neg "15-smokeserver"

echo
echo "=== 16) RESUMEN: pp/tg separados con mediana por tipo (CSV conocido) ==="
# Rojo pre-fix (awk posicional de correr-completo.sh a4f53c6): pp_med=300 tg_med=10
# sobre este CSV (demostrado one-shot); el correcto es pp_med=20 tg_med=2000.
# Los helpers son copia literal de tools/correr-completo.sh (csv_cols/csv_max/
# csv_filas + csv_med nuevo); reality-checker verifica la identidad por diff.
KCSV=$LAB/csv-conocido.csv
R16='"11146","11146","lab-cpu","","CPU","m.gguf","lab","0","0","2048","512","3","0x0","0","50","f16","f16","0","0","layer","0","0","0","auto","0.00","none","mmap","lazy","0","0","0","0","0"'
{ echo "build_commit,build_number,cpu_info,gpu_info,backends,model_filename,model_type,model_size,model_n_params,n_batch,n_ubatch,n_threads,cpu_mask,cpu_strict,poll,type_k,type_v,n_gpu_layers,n_cpu_moe,split_mode,main_gpu,no_kv_offload,flash_attn,devices,tensor_split,tensor_buft_overrides,load_mode,lazy_mode,embeddings,no_op_offload,no_host,fit_target,fit_min_ctx,n_prompt,n_gen,n_depth,test_time,avg_ns,stddev_ns,avg_ts,stddev_ts"
echo "$R16,\"512\",\"0\",\"0\",\"T\",\"300\",\"0\",\"10\",\"0\""
echo "$R16,\"512\",\"0\",\"0\",\"T\",\"100\",\"0\",\"30\",\"0\""
echo "$R16,\"512\",\"0\",\"0\",\"T\",\"200\",\"0\",\"20\",\"0\""
echo "$R16,\"0\",\"128\",\"0\",\"T\",\"3000\",\"0\",\"1000\",\"0\""
echo "$R16,\"0\",\"128\",\"0\",\"T\",\"1000\",\"0\",\"3000\",\"0\""
echo "$R16,\"0\",\"128\",\"0\",\"T\",\"2000\",\"0\",\"2000\",\"0\""; } > "$KCSV"
csv_cols16() { sed -n 's/.*"\([0-9][0-9]*\)","\([0-9][0-9]*\)","\([0-9][0-9]*\)","\([^"]*\)","\([0-9][0-9]*\)","\([0-9][0-9]*\)","\([0-9.eE+-][0-9.eE+-]*\)","\([0-9.eE+-][0-9.eE+-]*\)"$/\1 \2 \7/p'; }
csv_max16() { tipo=$1; csv_cols16 | awk -v tipo="$tipo" '((tipo=="pp"&&$2==0)||(tipo=="tg"&&$1==0)){if($3>m)m=$3} END{if(m=="")print "NA";else printf "%.2f",m}'; }
csv_filas16() { csv_cols16 | awk '$2==0{p++} $1==0{t++} END{print (p+0)" "(t+0)}'; }
csv_med16() { tipo=$1; csv_cols16 | awk -v tipo="$tipo" '((tipo=="pp"&&$2==0)||(tipo=="tg"&&$1==0)){print $3}' | sort -n | awk '{v[NR]=$1} END{if(NR==0)print "NA"; else print v[int((NR+1)/2)]}'; }
es "filas pp tg" "3 3" "$(csv_filas16 < "$KCSV")"
es "pp_max" "30.00" "$(csv_max16 pp < "$KCSV")"
es "pp_med" "20" "$(csv_med16 pp < "$KCSV")"
es "tg_max" "3000.00" "$(csv_max16 tg < "$KCSV")"
es "tg_med" "2000" "$(csv_med16 tg < "$KCSV")"
es "suma de contadores por fichero" 7 "$(printf 'a:3\nb:4\n' | awk -F: '{s+=$NF} END{print s+0}')"
control_neg "16-resumen"

echo
printf 'STUB: %d ok, %d FALLOS\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 2
