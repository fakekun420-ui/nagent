# INFORME - Bloque A1+A2+A3
1. Hecho: correr-completo reescrito (7 fixes); spike --smoke-server
(18 lin); prep.sh cache + prep-cache-lib + test-cache 10/0; sec.15+sec.16.
2. Evidencia: rojo sec.15 con codigo viejo (8 bench/2 ttft/10 reqs);
awk viejo pp_med=300 tg_med=10 vs bien 20/2000; pipe pierde rc (0 vs 7).
Verde: pendiente suite-verde.log (ver ESTADO).
3. Medidos: lab cache 10/0; parse-only rc=0 (5/5 entradas); dry-run rc=0.
4. Decisiones: TAG sin espacios (rc=1 con espacio); sin wake_lock_timeout
(solo renuevo+caducador 4h); CHECK_CARGA=0 hasta baseline; resumen con
csv_cols/csv_max/csv_filas+csv_med (identidad verificada por diff).
5. Supuestos: e2e de descarga no testeable en lab (6.3 GB + Wi-Fi real);
el cableado bajar()<->cache va por revision, no por ejecucion.
6. Riesgos: T1 (sin Wi-Fi: A4 en espera); mi --smoke-server --dry-run
accidental creo /data/adb/nagent/logs vacio (fail-closed exit 3, inofensivo).
7. Archivos y commits: tools/correr-completo.sh, tools/spike.sh,
tools/prep.sh, tools/prep-cache-lib.sh, tools/lab/test-cache.sh,
tools/pruebas-stub.sh (sec.15+sec.16), .gitignore (cache/). Commits al verde.
8. AGENTES USADOS: general(reality): 7/7 cuadran con file:linea;
general(devops): diseno pipe/watchdog/zombi; general(ai): diff
smoke-server 18 lin + cache sin relajar red. Modelo: no afirmable.
