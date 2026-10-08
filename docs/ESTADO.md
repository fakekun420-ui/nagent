# ESTADO nagent (max 25 lineas) - 2026-10-08
Bloque actual: A1-A3 ACEPTADOS (lab verde 91/0). Siguiente: A4 cadena.
Hecho: correr 7 fixes; spike --smoke-server (18 lin); prep cache +
  lib + test-cache 10/0; harness sec15+sec16; informe bloque-A123.
Verde: suite-verde.log 91/0 (secs 0-16, codigo nuevo).
Rojo: suite-roja15.log 86/5 (las 5 en sec15, predichas); awk viejo
  pp_med=300/tg_med=10 vs bien 20/2000; pipe pierde rc (0 vs 7).
Commits sgte: spike, pruebas-stub, correr, prep, lib, test-cache,
  gitignore, ESTADO, informe, entorno-v2, plan (uno por fichero).
Bloqueado: T1 sin Wi-Fi (solo movil) -> A4 en espera; T3 modulo -> F4.
Datos: /data/adb/nagent NO existe (solo logs/ vacio de un arranque
  accidental fail-closed exit 3). Wi-Fi al aparecer: prep+cadena.
Siguiente: commits -> lanzar vigilante -> B1 repo -> esqueleto C.
Preparation: wake_lock OK sin espacios; wake_lock_timeout NO existe.
Umbrales: 8/60 propuestos (re-calibrar con medir-reposo en sistema nuevo).
