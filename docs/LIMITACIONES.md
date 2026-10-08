# LIMITACIONES honestas de nagent v0.1.0 (Bloque G)

Lo que el guard y el sistema NO cubren (verificado, no supuesto):

1. Sesiones sin cargo: el guard decide por agente (event.agent). Una sesion personal no pasa los filtros de empleado. Lo que las gobierna es preguntar antes, no un deny.
2. Interpretes inline: execute/ctx_execute con python/ruby corren codigo que el guard solo ve como texto. La defensa real es no crear la sesion.
3. Symlinks preexistentes: el guard juzga la ruta escrita, no a donde apunta un enlace previo. Por eso prep.sh/spike.sh verifican test ! -L y find -type l tras instalar.
4. curl -o / wget / rm no se juzgan (limite conocido): sub-agentes solo lectura y un solo escritor por fichero.
5. TOCTOU de hash: verificar sha y usar el fichero no es atomico. Se mitiga re-verificando en destino tras cada copia.
6. FUSE (/sdcard): sin bit de ejecucion, mtime mentiroso, truncados a borde de buffer. Binarios solo en /data/adb/nagent/bin; tamano+sha tras escribir.
7. NPU Hexagon sin uso en SM8250 (docs/hexagon-backend.md): v66/v68 bajo el minimo v73 de llama.cpp. Solo CPU + OpenCL opcional.
8. wake_lock_timeout no existe en este kernel: solo lock clasico + renuevo cada 30 min + caducador.
9. Doze difiere red/jobs aunque la CPU siga viva: el wake lock no exime de Doze.
10. Flock en FUSE no funciona: Go necesita GOCACHE/GOMODCACHE fuera de /sdcard.
11. Sin gh autenticado no hay pushes ni Secrets: B1/B4 esperan gh auth login.
12. Sin toolchain local (Go/Kotlin): compilan en Actions; aqui solo revision manual.
