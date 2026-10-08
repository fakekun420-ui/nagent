#!/bin/sh
# tools/prep-cache-lib.sh - helpers de cache para prep.sh (A3).
# SOLO DEFINICIONES: al cargarlo no se ejecuta nada (seguro para test-cache.sh).
# Requiere del llamador: $NS (nsenter real o stub) y $CACHE (dir local).
# FUSE: nunca basta tamano o mtime; siempre sha256 en ambos lados.
cache_ok() { # $1 fichero $2 bytes $3 sha -> 0 si la cache es valida
  f=$1; bytes=${2:-}; sha=${3:-}
  [ -n "$bytes" ] && [ -n "$sha" ] || return 1
  [ -f "$CACHE/$f" ] || return 1
  [ "$(wc -c < "$CACHE/$f" 2>/dev/null | tr -d ' ' || true)" = "$bytes" ] || return 1
  [ "$(sha256sum "$CACHE/$f" 2>/dev/null | cut -d' ' -f1 || true)" = "$sha" ] || return 1
  return 0
}
traer_de_cache() { # $1 fichero $2 destino-final $3 bytes $4 sha -> 0 si copiado y verificado
  f=$1; dest=$2; bytes=${3:-}; sha=${4:-}
  cache_ok "$f" "$bytes" "$sha" || return 1
  $NS cp "$CACHE/$f" "$dest" 2>/dev/null || return 1
  [ "$($NS wc -c "$dest" 2>/dev/null | awk '{print $1}' || true)" = "$bytes" ] \
    || { $NS rm -f "$dest" 2>/dev/null || true; return 1; }
  [ "$($NS sha256sum "$dest" 2>/dev/null | cut -d' ' -f1 || true)" = "$sha" ] \
    || { $NS rm -f "$dest" 2>/dev/null || true; return 1; }
  $NS test ! -L "$dest" 2>/dev/null || { $NS rm -f "$dest" 2>/dev/null || true; return 1; }
  return 0
}
guardar_en_cache() { # $1 origen-en-DEV $2 nombre-cache $3 bytes $4 sha -> 0 si poblada y verificada
  src=$1; f=$2; bytes=${3:-}; sha=${4:-}
  [ -n "$bytes" ] && [ -n "$sha" ] || return 1
  mkdir -p "$CACHE" 2>/dev/null || return 1
  $NS cp "$src" "$CACHE/$f" 2>/dev/null || return 1
  cache_ok "$f" "$bytes" "$sha" || { rm -f "$CACHE/$f" 2>/dev/null || true; return 1; }
  return 0
}
