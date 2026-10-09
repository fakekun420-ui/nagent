# DECISION-ARQUITECTURA nagent (A7) - 2026-10-09

## Datos (A6 rc=0, 8 celdas x3 reps, crudos en docs/raw/)
Modelo 1.5B Q4_0: t3 pp_med=64.98 tg_med=21.54; t4 pp_med=86.97 tg_med=21.67
Modelo 1.5B Q4_K_M: t3 pp_med=40.26 tg_med=17.05; t4 pp_med=51.49 tg_med=18.94
Modelo 3B Q4_0: t3 pp_med=25.99 tg_med=9.61; t4 pp_med=33.87 tg_med=10.02
Modelo 3B Q4_K_M: t3 pp_med=17.96 tg_med=7.72; t4 pp_med=24.02 tg_med=7.95
RAM: sustained 1.5B pico VmHWM=1998860kB (~1.9 GB), deriva tg 0%, temp_max=63C.
Termica: prime<=49, battC=39 estables; contaminadas=0; ruidosas A6=0.
TTFT medido 2026-10-09 (1.5B, ~40 tok, con ruido diurno): frio prompt_ms=905,
caliente cache_n=30/36 prompt_ms=356. Criterio N1 (<=4s) CUMPLE con margen.
Huecos honestos: cancelacion a 2.0s en smoke-server (mecanismo sin aclarar); RAM pico
de bench ausente en resumen; set eval
62 casos redactado pero sin ejecutar contra modelos (precision sin medir).

## Decision
- Nivel 0 (reglas): SI, siempre.
- Nivel 2 (remoto OpenAI-compatible): SI, siempre.
- Nivel 1 (local): CONDICIONAL. Candidato unico 1.5B Q4_0 en t4.
  3B descartado por tg~8-10 (lento para dialogo) salvo prueba en contrario.
  Se declara viable solo si: TTFT caliente<=4s Y RAM pico<=3 GB Y
  precision>=90% en tools/eval. Sin esos tres, NO viable (estado actual).
- B3 build propio/KleidiAI: NO (sin evidencia de +15%; oficial rinde bien).
- NPU Hexagon: sin uso (v66/v68 < minimo v73 de llama.cpp).
- Smoke RUIDOSA x3 fue por mi carga CI concurrente, no por el dispositivo.
