INFORME - Bloque F3 (agentd manual + auditoria C6 + TTFT)
1. Hecho: agentd Actions (sha 9d603a07) desplegado a mano en /data/adb/nagent/bin;
  config con shas reales + token 0600; canal 401 sin token y 200 con token;
  riesgo alto siempre pendiente (sms sin enviar); traversal /etc/passwd denegado;
  auditoria C6 cableada tras hallar que Registrar() nadie la llamaba;
  TTFT 1.5B: frio 905ms, caliente 356ms (cache_n=30).
2. Evidencia: /health 401/200; tools/list con riesgo; audit.jsonl con hash,
  sin valores en claro; server n_slots=1 ctx 4096; VmHWM ~2.0 GB.
3. Decisiones: puerto server unificado a 18080 (spike y agentd);
  fix -np 1 en spike.sh y agentd/ciclo.go (--np no existe en b11146).
4. Supuestos: firma APK v2 por verificar con adb install (F5).
5. Riesgos: telefono en uso diurno (load 6-10, LMK activo); eval largo de noche.
