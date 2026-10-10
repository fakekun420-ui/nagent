# ESTADO nagent (max 25 lineas) - 2026-10-10
Bloque actual: SISTEMA APAGADO por orden (hasta resolver bloqueo UID).
Hecho: modulo F4 instalado+deshabilitado; agentd detenido; puertos cerrados.
  Verificado antes de apagar: su={"ok":true} (transporte root SI conecta);
  directo=FALLO (netd restricted sin UID 10528 en allowlist, causa raiz).
  B1+Secrets; CI 3/4; APK su-build instalado; A6+A7 verdes; lab 91/0.
En curso: NADA (todo proceso nagent muerto, telefono libre).
Bloqueado: TODO hasta resolver: permitir UID en netd, reboot F5, o decidir
  arquitectura sin loopback-app. Con tu direccion cuando digas.
Datos intactos: /data/adb/nagent, /data/adb/modules/nagent (disable, reversible).
Siguiente: tu orden -> resolver red-app -> E2E -> F5 -> G.
Informes: bloque-A123.md; bloque-F3.md; LIMITACIONES.md; DECISION.
