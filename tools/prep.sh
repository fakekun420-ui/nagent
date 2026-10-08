#!/bin/sh
# tools/prep.sh - descarga a /data/adb/nagent/{bin,models} SOLO por nsenter. NO EJECUTAR aun.
# Requiere red y ~7 GB libres en /data; tarda lo que tarde la red (timeouts parciales,
# sin --max-time global).
# Salida 0 = todo verificado; salida 1 = cualquier desacuerdo (no instala nada dudoso).
# Re-ejecucion segura: lo ya verificado se omite, el resto se reintenta desde cero.
#
# Garantias (falla cerrado):
#   - URLs, bytes y SHA salen del manifiesto (ruta literal abajo), no van quemados aqui;
#   - el tarball snapdragon queda listado pero NO se descarga (spike-rendimiento.md p10);
#   - antes de nada se comprueba espacio libre (total + holgura de extraccion + 1 GiB);
#   - cada fichero baja a .part, se compara tamano y SHA, y solo entonces mv atomico
#     (mismo directorio = rename) + chmod; el .part corrupto se borra tras dejar constancia;
#   - el tarball se extrae en $BIN y se exige llama-bench + llama-server directos ahi;
#   - cero symlinks: no se crea ninguno y se comprueba que ningun instalado (ni BIN/MOD) lo sea.
#   - el prechequeo de espacio no descuenta lo ya instalado (con 100+ GB libres sobra).
set -eu

NS=${NAGENT_NS:-"nsenter -t 1 -m --"}
DEV=${NAGENT_DEV:-/data/adb/nagent}
BIN=$DEV/bin
MOD=$DEV/models
# A3: cache verificada en /sdcard (sobrevive al downgrade; ver punto 7 del plan).
# Nunca evita el tripwire de red: solo evita bytes ya verificados.
CACHE=${NAGENT_CACHE:-/sdcard/projects/nagent/cache}
case "$0" in */*) LIBDIR=${0%/*} ;; *) LIBDIR=. ;; esac
CACHELIB=${NAGENT_LIB:-$LIBDIR/prep-cache-lib.sh}
[ -r "$CACHELIB" ] || { echo "[?] FALLO falta lib de cache: $CACHELIB" >&2; exit 1; }
. "$CACHELIB"
MANIFIESTO=/sdcard/projects/nagent/docs/manifest-sha256.md

TARBALL=llama-b11146-bin-android-arm64.tar.gz
MODELOS="qwen2.5-1.5b-instruct-q4_0.gguf
qwen2.5-1.5b-instruct-q4_k_m.gguf
qwen2.5-3b-instruct-q4_0.gguf
qwen2.5-3b-instruct-q4_k_m.gguf"

say() { echo "[$(date '+%H:%M:%S')] $*"; }
die() { say "FALLO $*"; exit 1; }

[ -r "$MANIFIESTO" ] || die "manifiesto ilegible: $MANIFIESTO"

dato_tabla() { # $1 fichero -> "bytes sha" (vacio si no esta en la tabla)
  awk -F'|' -v f="$1" 'index($0, "`" f "`") { gsub(/[` ]/, "", $3); gsub(/[` ]/, "", $4); print $3, $4 }' "$MANIFIESTO"
}

url_de() { # $1 fichero -> url (vacia si no hay); modelos por URL literal, tarball por base
  u=$(grep 'https://' "$MANIFIESTO" 2>/dev/null | grep -F "$1" | head -n 1 | tr -d ' `' || true)
  if [ -n "$u" ]; then printf '%s' "$u"; return 0; fi
  base=$(grep -o 'https://[^`]*download/b11146/[^`<]*' "$MANIFIESTO" | head -n 1 || true)
  [ -n "$base" ] || return 1
  u="$base$1"
  case "$u" in *'<'*) return 1 ;; esac
  printf '%s' "$u"
}

# Vuelca lineas crudas acotadas cuando habia Wi-Fi pero el formato fallo (el parser nunca
# ha visto el caso Wi-Fi: sin este vuelco el aborto seria ciego). Solo lectura.
vuelca_red() { # $1 motivo
  say "--- vuelca red ($1): formato no previsto ---"
  printf '%s' "${con:-}" | grep -E 'NetworkAgentInfo|Active default network|ni\{|InterfaceName|Transports' | head -n 20 || true
  printf '%s' "${npol:-}" | grep -iE 'metered' | head -n 10 || true
}

# Punto 1 (autorizacion): solo Wi-Fi no medida, demostrado, no supuesto. Falla cerrado:
# sin agente Wi-Fi CONECTADO, sin red por defecto Wi-Fi, con la interfaz en el conjunto metered
# del SO, o sin poder demostrarlo (salidas vacias), aborta ANTES de crear nada. Nada movil.
red_no_medida() {
  con=$($NS dumpsys connectivity 2>/dev/null || true)
  [ -n "$con" ] || die "sin salida de dumpsys connectivity (red no demostrable)"
  [ "$(printf '%s' "$con" | grep -c 'ni{WIFI[A-Za-z0-9_ ."-]* CONNECTED' || true)" -gt 0 ] \
    || die "sin Wi-Fi CONECTADO (solo hay movil o nada)"
  def=$(printf '%s' "$con" | grep -o 'Active default network: [0-9]*' | awk '{print $4}' | head -n 1 || true)
  [ -n "$def" ] || { vuelca_red "sin red por defecto"; die "sin red por defecto (red no demostrable)"; }
  ag=$(printf '%s' "$con" | grep "network{$def}" | head -n 1 || true)
  printf '%s' "$ag" | grep -q 'ni{WIFI[A-Za-z0-9_ ."-]* CONNECTED' \
    || { vuelca_red "agente por defecto ilegible"; die "la red por defecto ($def) no es Wi-Fi"; }
  iface=$(printf '%s' "$ag" | grep -o 'InterfaceName: [^ ]*' | awk '{print $2}' | head -n 1 || true)
  [ -n "$iface" ] || { vuelca_red "interfaz ilegible"; die "interfaz de la red por defecto ilegible"; }
  npol=$($NS dumpsys netpolicy 2>/dev/null || true)
  met=$(printf '%s' "$npol" | grep -o 'Metered ifaces: {[^}]*}' | head -n 1 || true)
  [ -n "$met" ] || { vuelca_red "conjunto metered ilegible"; die "conjunto metered ilegible (red no demostrable)"; }
  set_m=$(printf '%s' "$met" | sed 's/.*{//;s/}.*//' | tr -d ' ' || true)
  case ",$set_m," in *",$iface,"*) die "la interfaz $iface esta declarada medida (Metered ifaces)";; esac
  say "red OK: Wi-Fi por defecto ($def/$iface), fuera del conjunto metered"
}

bajar() { # $1 fichero, $2 dir destino, $3 modo
  f=$1; d=$2; modo=$3
  set -- $(dato_tabla "$f")
  bytes=${1:-}; sha=${2:-}
  [ -n "$bytes" ] && [ -n "$sha" ] || die "manifiesto no trae bytes/sha para $f"
  u=$(url_de "$f") || die "manifiesto no trae URL para $f"
  [ -n "$u" ] || die "manifiesto no trae URL para $f"
  final="$d/$f"; part="$final.part"
  if [ "$($NS sha256sum "$final" 2>/dev/null | cut -d' ' -f1 || true)" = "$sha" ]; then
    say "$f ya esta correcto, se omite"
    return 0
  fi
  # A3: intento desde cache (verificada tamano+sha en ambos lados). La red ni se toca.
  if [ -e "$CACHE/$f" ]; then
    if traer_de_cache "$f" "$final" "$bytes" "$sha"; then
      $NS chmod "$modo" "$final" || die "chmod de $f (desde cache)"
      say "OK $f ($bytes B, desde cache, sha verificado)"
      return 0
    fi
    say "cache de $f no valida, se borra y descarga"
    rm -f "$CACHE/$f" || die "no se puede borrar cache corrupta de $f"
  fi
  $NS rm -f "$part" || die "no se puede limpiar $part"
  # Anti-colgado: corta si baja de 50 KiB/s durante 60 s; 3 reintentos (transitorios).
  $NS curl -fSL --retry 3 --retry-delay 5 --connect-timeout 30 --speed-time 60 --speed-limit 51200 -o "$part" "$u" \
    || die "descarga de $f"
  got_size=$($NS wc -c "$part" 2>/dev/null | awk '{print $1}' || true)
  if [ "$got_size" != "$bytes" ]; then
    $NS rm -f "$part"
    die "tamano de $f: manifiesto=$bytes real=${got_size:-?}"
  fi
  got=$($NS sha256sum "$part" 2>/dev/null | cut -d' ' -f1 || true)
  if [ "$got" != "$sha" ]; then
    $NS rm -f "$part"
    die "SHA de $f no cuadra (manifiesto=$sha real=${got:-?})"
  fi
  $NS mv "$part" "$final" || die "mv atomico de $f"
  $NS chmod "$modo" "$final" || die "chmod de $f"
  $NS test ! -L "$final" || die "$final es un symlink"
  guardar_en_cache "$final" "$f" "$bytes" "$sha" || say "aviso: no se pudo poblar cache de $f"
  say "OK $f ($bytes B, sha verificado)"
}

# --red-check: solo corre red_no_medida (para el vigilante). Sale 0/1 sin tocar nada.
if [ "${1:-}" = --red-check ]; then
  red_no_medida
  exit $?
fi
# Punto 4: --parse-only es solo lectura (aqui ya estan definidos los helpers); imprime lo
# parseado y aborta si algo falta. Se ejecuta antes de descargar y se compara contra el manifiesto.
if [ "${1:-}" = --parse-only ]; then
  for f in "$TARBALL" $MODELOS; do
    set -- $(dato_tabla "$f")
    printf '%s -> bytes=%s sha=%s url=%s\n' "$f" "${1:-?}" "${2:-?}" "$(url_de "$f" || true)"
    [ -n "${1:-}" ] && [ -n "${2:-}" ] && [ -n "$(url_de "$f" || true)" ] \
      || die "parseo incompleto para $f"
  done
  exit 0
fi
red_no_medida
say "=== prep Etapa 0.5: manifiesto $MANIFIESTO ==="
$NS mkdir -p "$BIN" "$MOD" || die "no se puede crear $BIN $MOD"
$NS test ! -L "$BIN" || die "$BIN es un symlink"
$NS test ! -L "$MOD" || die "$MOD es un symlink"

total=0
set -- $(dato_tabla "$TARBALL"); tb_bytes=${1:-}
[ -n "$tb_bytes" ] || die "manifiesto no trae el tarball"
total=$((total + tb_bytes))
for m in $MODELOS; do
  set -- $(dato_tabla "$m")
  [ -n "${1:-}" ] || die "manifiesto no trae el modelo $m"
  total=$((total + $1))
done
[ "$total" -gt 6000000000 ] || die "total del manifiesto sospechoso ($total B, se esperaban 6.4 GB)"
need_kb=$(( (total + tb_bytes * 2 + 1073741824 + 1023) / 1024 ))
free_kb=$($NS df -k /data | tail -n 1 | awk '{print $4}' || true)
[ -n "$free_kb" ] && [ "$free_kb" -gt "$need_kb" ] || die "espacio en /data: libres=${free_kb:-?}KiB necesarios=${need_kb}KiB"
say "espacio OK (libres=${free_kb}KiB, necesarios=${need_kb}KiB)"

# Punto 3: antes de extraer se lista y se falla ante rutas absolutas, .. o enlaces.
# Formato esperado de `tar -tzf` (toybox, sin -v): las absolutas empiezan por /, los enlaces
# muestran `->` (symlink) o `link to` (hardlink estilo GNU). Si el formato cambiara y estas
# marcas no aparecieran, el chequeo de bins directos tras extraer sigue cerrando el fallo.
verificar_tar() { # $1 tarball en $BIN
  lista=$($NS tar -tzf "$BIN/$1" 2>/dev/null || true)
  [ -n "$lista" ] || die "tar ilegible o vacio: $1"
  printf '%s' "$lista" | grep -qE '^/' && die "tar con rutas absolutas: $1"
  printf '%s' "$lista" | grep -qE '(^|/)\.\.(/|$)' && die "tar con ..: $1"
  printf '%s' "$lista" | grep -qE ' -> |link to ' && die "tar con enlaces: $1"
  say "tar limpio ($1)"
}

bajar "$TARBALL" "$BIN" 644
verificar_tar "$TARBALL"
$NS tar -xzf "$BIN/$TARBALL" -C "$BIN" || die "extraccion de $TARBALL (inspeccionar con tar -tzf)"
for b in llama-bench llama-server; do
  # Candidatos = hallados MENOS la copia plana anterior: asi cada corrida reinstala desde el
  # tarball recien verificado y un cambio de version no queda enmascarado por la copia vieja.
  # Si el tarball trae 2 de verdad con el mismo nombre: ambiguo y se para.
  # Nota: si algun dia cambia TARBALL de version, limpiar $BIN a mano antes (restos .so viejos).
  cands=$($NS find "$BIN" -name "$b" -type f 2>/dev/null | grep -v -x -F "$BIN/$b" || true)
  [ -n "$cands" ] || die "$b ausente tras extraer (ver tar -tzf)"
  # OJO wc: la sustitucion recorta el \n final, asi que se repone con %s\n; y wc puede
  # rellenar con espacios, que se quitan para comparar.
  [ "$(printf '%s\n' "$cands" | wc -l | tr -d ' ')" = 1 ] || die "$b ambiguo tras extraer: $cands"
  $NS cp "$cands" "$BIN/$b" || die "copia de $b a $BIN"
done
for s in $($NS find "$BIN" -name '*.so' -type f 2>/dev/null || true); do
  base=$(basename "$s")
  [ "$s" = "$BIN/$base" ] || $NS cp "$s" "$BIN/$base" || die "copia de $base a $BIN"
done
for b in llama-bench llama-server; do
  $NS test -s "$BIN/$b" || die "$b ausente en $BIN"
  $NS chmod 755 "$BIN/$b" || die "chmod 755 $b"
  $NS test ! -L "$BIN/$b" || die "$b es un symlink"
done
say "OK binarios localizados en $BIN y ejecutables"
# Punto A.1: ningun enlace en todo $BIN (el tar ya se filtro, esto lo confirma tras extraer).
enBin=$($NS find "$BIN" -type l 2>/dev/null || true)
[ -z "$enBin" ] || die "symlinks en $BIN: $enBin"
# Punto A.3: los binarios tienen que arrancar. Primero sin nada; si solo van con
# LD_LIBRARY_PATH, se anota (ver spike.sh); si ni asi, faltan .so del sistema: FALLA.
for b in llama-bench llama-server; do
  if $NS "$BIN/$b" --version >/dev/null 2>&1; then
    say "OK $b arranca sin LD_LIBRARY_PATH"
  elif $NS sh -c 'export LD_LIBRARY_PATH="$1"; shift; exec "$@"' _ "$BIN" "$BIN/$b" --version >/dev/null 2>&1; then
    say "OK $b arranca SOLO con LD_LIBRARY_PATH=$BIN (anotar para spike.sh)"
  elif $NS test -d "$BIN/lib" 2>/dev/null && $NS sh -c 'export LD_LIBRARY_PATH="$1"; shift; exec "$@"' _ "$BIN/lib" "$BIN/$b" --version >/dev/null 2>&1; then
    say "OK $b arranca SOLO con LD_LIBRARY_PATH=$BIN/lib (anotar para spike.sh)"
  else
    err=$($NS sh -c 'export LD_LIBRARY_PATH="$1"; shift; exec "$@"' _ "$BIN" "$BIN/$b" --version 2>&1 | head -5 || true)
    die "$b no arranca (evidencia: $err)"
  fi
done

for m in $MODELOS; do
  bajar "$m" "$MOD" 644
done
say "=== prep fin: todo verificado ==="
