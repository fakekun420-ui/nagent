# ESTADO nagent (max 25 lineas) - 2026-10-08
Bloque actual: D+E esqueletos listos. Descarga 6.3 GB en curso (movil).
Hecho: prep opt-in NAGENT_ALLOW_METERED=1 (lab 2/0, red real AVISO ok);
  descarga lanzada .lab/prep-movil.log (~190kB/s); agentd MCP (rpc+5
  grupos+test, sin shell); app E (manifest, voz, TTS, notif opt-in).
Verde: lab 91/0 (A); test-cache 10/0; test-metered 2/0. Go/Kotlin SIN
  compilar aqui (apt golang en fondo; Actions hara go vet+test).
Hecho-extra: keystore B4 fuera del repo (600, ~/.config/nagent);
  F1 zip pendiente de `zip` (dpkg ocupado); Go revisado a mano.
Bloqueado: A4-A6 hasta fin descarga (horas); gh SIN auth (push+secrets
  esperan `gh auth login`); F4 espera zip+linea Leonardo (T3).
Datos: /data/adb/nagent recreandose por prep (tarball primero).
Siguiente: al fin descarga -> verificar -> baseline -> smoke ->
  smoke-server -> completa -> A7 -> F1/F3 -> G.
Informes: bloque-A123.md; este: pendiente bloque-DE al cerrar D/E tests.
