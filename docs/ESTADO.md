# ESTADO nagent (max 25 lineas) - 2026-10-08
Bloque actual: A1-A3 aceptados; B1+C esqueletos listos. A4 en espera T1.
Hecho: agentd/ 13 ficheros (Go estatico, test unitario incluido);
  module/ plantilla F (sin autostart/post-fs-data); 4 workflows;
  eval 62 casos (50+12); app esqueleto targetSdk34; rollback+F4.
Verde: lab 91/0 (A); test-cache 10/0 (A3). Go SIN compilar aqui
  (sin toolchain; compila en Actions: go vet+test primero).
Bloqueado: T1 sin Wi-Fi (A4/prep/cadena); sin gh en chroot (push
  repo y workflows); F4 espera zip+linea Leonardo (T3).
Datos: /data/adb/nagent NO existe. Vigilante PID 9988 sondeando.
Siguiente: D herramientas MCP -> E app completa -> F1 zip ->
  cadena A4-A6 al Wi-Fi -> A7 decision -> G acceptance.
Umbrales: 8/60 propuestos (re-calibrar con medir-reposo en v2).
Informes: docs/informes/bloque-A123.md (este turno: pendiente bloque-BC).
