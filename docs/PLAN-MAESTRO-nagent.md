# PLAN MAESTRO — Terminar el proyecto nagent (modo autónomo)

> Pega este documento completo a la sesión nagent (o guárdalo en `docs/PLAN-MAESTRO.md` del repo y léelo).
> **Reemplaza todos los prompts anteriores**. Lo que no contradiga este documento sigue vigente (reglas de independencia, namespaces, sub-agentes, etc.).
> Objetivo: llevar el proyecto de "spike a medio hacer" a **v0.1.0 instalada y validada en el POCO F3**, sin esperar aprobaciones intermedias.

---

## 0. Modo de operación (léelo primero)

**Este documento es la autorización previa** de todo lo que contiene, salvo lo listado en §3 (los únicos puntos de parada reales).

Reglas para no frenar el trabajo:

1. **No esperes "continuar" ni "APROBADO"** entre bloques. Cada paso tiene **criterios de aceptación automáticos**; si se cumplen, sigues.
2. **Un paso solo se detiene por un tripwire de §3.** Si un paso queda bloqueado, anótalo en `docs/ESTADO.md` con el motivo y **pasa al siguiente paso independiente**. Nunca te quedes ocioso si hay trabajo no bloqueado.
3. **Los turnos son finitos.** Lo que tarda horas (descarga, línea base, corrida completa) lo ejecuta una **cadena desacoplada** (`nohup`, un solo proceso por pidfile, logs en `$LOGS` por `$NS`, copiados al repo con sha). Al lanzar una cadena, **termina el turno con 3 líneas** (qué corre, dónde está el log, qué leerás al volver). Cuando Leonardo escriba cualquier mensaje ("continuar", "estado"), **retoma leyendo `docs/ESTADO.md` y los logs**.
4. **Informes:** al cerrar cada bloque escribe `docs/informes/bloque-<X>.md` (formato corto de §10) y actualiza `docs/ESTADO.md` (máx. 25 líneas: bloque actual, hecho, bloqueado, siguiente). **Escribir el informe no es una parada.**
5. **No pidas acciones a Leonardo.** Excepciones únicas: Wi-Fi no medida y cargador (§3) y la línea de autorización del módulo (§3).
6. **Supervisión asíncrona:** Leonardo puede pegar tus informes a un supervisor (Claude) más tarde. Si el supervisor pide correcciones, aplícalas; mientras tanto, no esperes.

---

## 1. Estado de partida (hechos verificados)

**Dispositivo y sistema (re-baseline, `docs/00-entorno-v2.md`)**
- POCO F3 (`alioth`), **Android 14 / SDK 34**, crDroid `AP2A.240905.003` (2025-05-23), kernel 4.19.322 InfiniR v2.98, SELinux **Enforcing**, Magisk **30700**, 10 módulos.
- CPU: cpu0-3 A55 @1.80 GHz · cpu4-6 A77 @2.42 · cpu7 A77 prime @3.19 (schedutil). Features: fp16, dotprod; **sin** i8mm ni SVE. Máscaras: 3 hilos = `70` (cpu4-6), 4 hilos = `f0` (cpu4-7).
- Zonas térmicas por tipo: `cpu-1-4..7-usr` → 11-14, `battery` → 92 (se resuelven por tipo, nunca por número).
- RAM total ~11.3 GiB. `/data` ~151 GiB libres. toybox 0.8.10 (`taskset` con máscara hex, sin `-c`).
- `/sys/power/wake_lock` existe; `wake_lock_timeout` **no** existe. El TAG del lock **no admite espacios**.
- Puente a Android: `nsenter -t 1 -m --` (`$NS`). El `/data/adb` del chroot es un espejo distinto del real.
- `/data/adb/nagent/` **no existe**: se perdió con el downgrade. Hay que recrearlo con `prep.sh`.
- Sobrevive: chroot, `/sdcard`, repo `/sdcard/projects/nagent`, `/data/adb/*`, módulos Magisk.

**Código del repo (`/sdcard/projects/nagent`)**
- `tools/spike.sh` sha `354d38dc…` (commit `2257f80`), `tools/prep.sh` sha `adc0ccf5…` (commit `c22b091`), `tools/correr-completo.sh` sha `fa40218e…` (commit `a4f53c6`, con 7 defectos pendientes de §4.A1).
- Laboratorio `tools/lab/` + `pruebas-stub.sh`: 77/0 en verde, 15/15 controles negativos.
- llama.cpp **b11146** (commit `7fe450e1`). Modelos: Qwen2.5 1.5B y 3B en Q4_0 y Q4_K_M. Manifiesto: `docs/manifest-sha256.md`.
- Formato real de `llama-bench -o csv`: cabecera de 41 campos, filas entrecomilladas; pp con `n_gen=0`, tg con `n_prompt=0`; `avg_ts` en t/s.
- Hallazgo del dispositivo anterior (re-verificar): los binarios solo arrancaban con `LD_LIBRARY_PATH=$BIN`.
- Smoke del 3-oct (sistema anterior, histórico, con ruido de carga): 1.5B Q4_0, 3 hilos, pp ≈ 38.7 t/s, tg ≈ 14.6 t/s.

**Guard:** `screen-guard.js` v3.37 instalado en disco (la sesión guard está **cerrada**; no se vuelve a usar salvo §3). Concede escrituras bajo `/data/adb/nagent/` **solo vía `nsenter`**; **excluye** `/data/adb/modules`, `/system` y otros proyectos. `curl -o`, `wget`, `git clone` y `rm` **no se juzgan** (límite conocido): por eso los sub-agentes son solo lectura.

---

## 2. Reglas permanentes (siguen vigentes)

1. **Independencia:** nada de Aegis ni de otros proyectos. Nunca leas tokens, claves, `.env` ni bases de datos ajenas. Kaenor-Inc y el guard: no se tocan.
2. **Dos árboles:** todo acceso a rutas de Android (`/data/adb/nagent/...`, `/sys/...`, `/proc/...` de Android) va **por `$NS`** (incluidas las redirecciones, dentro de `$NS sh -c`). El repo y el chroot son el otro árbol. Auditoría de cada `>`/`>>` en cada script nuevo.
3. **FUSE (`/sdcard`):** sin bit de ejecución, sin symlinks, riesgo de truncado: verifica **tamaño y sha** de todo lo escrito allí. Los ejecutables viven en `/data/adb/nagent/bin` o `/tmp`.
4. **Sub-agentes:** mínimo 3 por bloque, **solo lectura** (nada de `curl -o`, `wget`, `tee`, `git`, redirecciones). Un solo escritor por fichero: tú. Toda cita de código de un sub-agente la verifica `reality-checker` con otro modelo. Antes y después de cada delegación: `git status --porcelain`. No uses `test-automation-engineer` para escribir pruebas sin que el `reality-checker` verifique las citas (ya inventó código). Reporta el modelo real solo si lo puedes comprobar; si no, no lo afirmes.
5. **Calidad:** `set -eu`; nunca un log vacío como resultado (un fallo es FALLO); `rc=$?` antes de cualquier otro comando; `dash -n` y auditoría no-ASCII tras **cada** edición; commit por fichero; cada sha aprobado queda en git.
6. **Seguridad SELinux:** siempre Enforcing, nunca `permissive`. Sin symlinks nuevos en el árbol del proyecto.
7. **Datos móviles:** nunca descargues por red medida. Si no hay Wi-Fi no medida, trabaja en lo que no necesita red.
8. **No inventes.** Verifica en el código fuente de la versión fijada o con una medición. Lo no verificado lleva etiqueta `[SUPOSICIÓN]`.

---

## 3. Paradas reales (los únicos tripwires)

| # | Condición | Qué haces |
|---|---|---|
| T1 | Sin Wi-Fi no medida (el tripwire de `prep.sh` aborta) | No toques la red. Trabaja en bloques sin red. El vigilante `esperar-wifi.sh` retoma solo. |
| T2 | El guard DENIEGA una orden | **No la rodees** (ni por texto, ni con otro verbo). Documenta en `docs/SOLICITUD-AUTORIZACION.md` la orden exacta y la línea de autorización necesaria, y continúa con otro paso. |
| T3 | **Instalación del módulo Magisk** (Bloque F): escribe en `/data/adb/modules`, que el guard excluye a propósito | Prepara todo y deja el zip verificado. La instalación necesita **una línea de autorización que escribe Leonardo** (control humano del guard). Redacta `docs/SOLICITUD-AUTORIZACION.md` con la línea exacta y la orden exacta, y pasa a F4/G. |
| T4 | Batería < 30 % sin cargar, `battC ≥ 45` ×3 muestras o `prime ≥ 85` ×3 | Aborta la medición en curso, deja constancia y reintenta tras enfriar (máx. 2 reintentos). |
| T5 | Una acción tocaría fuera de `/sdcard/projects/nagent`, `/data/adb/nagent`, `/tmp/stub-lab` o `/tmp` propio | Para esa acción, anótalo, sigue con otra. |
| T6 | Contradicción entre este documento y una regla global | Gana la regla global; anótalo. |

Todo lo demás **no** es motivo de parada.

---

## 4. Bloque A — Cerrar el spike en el dispositivo

**Objetivo:** medir rendimiento real (CPU) y producir `docs/DECISION-ARQUITECTURA.md`.

### A1. Aplicar correcciones a `correr-completo.sh` (aceptación automática)
1. **Sin tubería** al lanzar `spike.sh`: `sh "$SPIKE" > fichero 2>&1 &`; `SPIKE_PID=$!`; `wait` da el `rc` real; el log se copia después. Prueba con un spike falso que haga `exit 7`: debe terminar con `rc 7`.
2. **Watchdog** de 5 h con `kill` por PID propio y comprobación de `comm` (el objetivo está en el chroot: sin `$NS`). Prueba con proceso dummy.
3. **Resumen correcto:** reutiliza `csv_filas`/`csv_max` de `spike.sh`; separa pp (`n_gen=0`) y tg (`n_prompt=0`) y reporta `avg_ts` (t/s). Suma los `grep -c` de varios ficheros. Valídalo en el lab con CSV conocido, **primero en rojo**.
4. **wake_lock:** sin `wake_lock_timeout`. Toma el lock con TAG sin espacios, renueva cada 30 min, libéralo en `trap`, al inicio y al final. Un **caducador independiente** (proceso aparte con `sleep` y `wake_unlock` tras 4 h) cubre la muerte abrupta del script.
5. **Seguridad térmica y de carga:** aborta según T4; la comprobación de carga queda desactivada hasta medir la línea base.
6. Inicializa `RENEW_PID`, `DOG_PID`, `SPIKE_PID` vacíos al principio (por `set -eu`).
7. **Copiador incremental:** cada 60 s copia al repo con sha los ficheros nuevos o cambiados de `$LOGS`, y copia final.
8. Que el vigilante de Wi-Fi siga escribiendo en el repo (ahí sobrevivió).

**Aceptación:** lab sin FALLOS (cada prueba nueva primero en rojo), `dash -n`, no-ASCII = 0, `reality-checker` verifica las citas, commit. → **Continúa sin esperar.**

### A2. Modo `--smoke-server` en `spike.sh` (aceptación automática)
- Diff pequeño: `PREFIX_MODEL` parametrizable, flag `SMOKE_SERVER`, `TTFT_REQS=3` forzado, rama dry-run + ejecución con `run_prefix_cache` sin cambios. Prueba §15 en el lab (sin binario nuevo), primero en rojo.
- **Aceptación:** lab verde, diff ≤ ~25 líneas, no-ASCII = 0, commit. → Continúa.

### A3. `prep.sh` con caché (aceptación automática)
- Caché verificada en `/sdcard/projects/nagent/cache/` (en `.gitignore`): tamaño + sha. Copia a `$BIN/$MOD` por `$NS` y verifica el sha del destino. Si el sha de la caché no cuadra, la borra y descarga de nuevo. Tripwires de red intactos. Nunca modo offline falso.
- **Aceptación:** lab verde con la caché; commit.

### A4. Vigilante y descarga
- Lanza/valida `tools/esperar-wifi.sh` (un solo proceso por pidfile, heartbeat cada 120 s en el repo).
- En cuanto haya Wi-Fi no medida: `prep.sh --parse-only` → `prep.sh` (descarga 6.3 GB, sha, caché) → verificación: ambos binarios con `--version` (con y sin `LD_LIBRARY_PATH`; documenta cuál hace falta en **este** Android 14) → `find -type l` sin resultados.
- Si `LD_LIBRARY_PATH` es necesario, ya está aplicado en `spike.sh` (`export` en lanzamientos); si falta en algún punto, corrígelo, relanza el lab y commitea.

### A5. Cadena de validación automática (encadenada, sin intervención)
Tras `prep OK`, una sola cadena desacoplada ejecuta, en este orden, y registra todo en `$LOGS`:
1. `medir-reposo.sh` (10 min) → mediana y máximo de load, `cpu4-7`, `battC`; **fija** `MAX_LOAD` y `MAX_TEMP_PRIME` para la corrida (si los datos contradicen 8/60, usa los datos y justifica).
2. `spike.sh --dry-run` (verifica que no crea ni modifica nada).
3. `spike.sh --smoke` (celda 1.5B Q4_0, 3 hilos): aceptación = una fila CSV real con `avg_ts` pp y tg, afinidad `70 → 4-6`, zonas por tipo, `comm=llama-bench`.
4. `spike.sh --smoke-server`: aceptación = servidor arranca, `/health` OK, `cache_n` ≈ 0 en la petición fría y alto en las calientes, puerto libre tras `parar_server`.
5. **Criterio de continuar:** si 3 y 4 cumplen su aceptación → lanza A6 **sin esperar**. Si fallan: lee el log, corrige la causa (una sola vez), relanza esa fase; si vuelve a fallar, anótalo y deja el spike completo en pausa, pero **sigue con los Bloques B y C** (no dependen del resultado).

### A6. Corrida completa
- `tools/correr-completo.sh` desacoplado, con `MAX_LOAD`/`MAX_TEMP_PRIME` medidos y wake_lock. Teléfono cargando, pantalla apagada, sin otras sesiones (la tuya incluida: lanza la cadena y **termina el turno**).
- Salida: `docs/raw/resumen-completo-<ts>.log` con la tabla modelo × formato × hilos (mediana y dispersión de pp y tg), TTFT frío y caliente, RAM pico, nº de celdas RUIDOSAS y subtabla con `load ≤ 5`.

### A7. Análisis y decisión (cuando existan los datos)
Escribe `docs/DECISION-ARQUITECTURA.md`. **Reglas de decisión por defecto** (ajústalas solo con datos y justifícalo):
- **Nivel 0** (reglas deterministas, sin LLM): siempre. Cubre las intenciones simples y frecuentes.
- **Nivel 1** (LLM local ≤ 3B con prefijo cacheado) **es viable** si: TTFT caliente (mediana, orden nueva de ~40 tokens) ≤ 4 s, RAM pico ≤ 3 GB, y precisión de herramientas ≥ 90 % en el set de evaluación (Bloque C). Elige el modelo que cumpla con mayor tg.
- Si Nivel 1 no cumple con ningún modelo: arquitectura de **dos niveles** (Nivel 0 + remoto) y el modelo local queda como opcional.
- **Nivel 2** (remoto, URL compatible con OpenAI, configurable) siempre disponible.
- Si KleidiAI no está en el binario oficial: build propio en Actions (Bloque B3) y compáralo; adóptalo si mejora pp o tg ≥ 15 %.
- Documenta el techo de RAM, el ciclo de carga/descarga por inactividad y las limitaciones del 870 (sin NPU Hexagon útil: v66/v68 por debajo del mínimo v73 de llama.cpp; OpenCL/Adreno solo como prueba aparte opcional al final).

---

## 5. Bloque B — Repositorio público y CI (puede ir en paralelo a A)

No necesita red para escribir el código; los pushes y los workflows sí usan red (Wi-Fi no medida).

- **B1.** Repo público `nagent` en GitHub (`gh` ya autenticado). Estructura:
  ```
  nagent/
  ├─ agentd/        # Go
  ├─ app/           # Kotlin
  ├─ inference/     # scripts de build llama.cpp, manifiesto de modelos
  ├─ module/        # plantilla Magisk
  ├─ tools/         # spike, prep, lab, scripts
  ├─ docs/
  └─ .github/workflows/
  ```
  Secretos solo en GitHub Secrets. Revisa que no se cuele ninguno antes de cada push (`gitleaks`-style con grep o herramienta equivalente).
- **B2.** Workflows (`workflow_dispatch` + push): `build-agentd` (Go, `GOOS=linux GOARCH=arm64 CGO_ENABLED=0`), `build-app` (Gradle + firma con keystore desde Secrets), `package-module` (zip + sha256) y `release`. Caché de Go y Gradle. Ejecuta **un workflow cada vez** y lee los logs antes del siguiente.
- **B3 (condicional):** `build-inference` solo si A7 lo exige (build propio de llama.cpp con NDK, flags: `GGML_CPU_KLEIDIAI=ON`, `GGML_NATIVE=OFF`, `GGML_OPENMP=OFF`, `GGML_LLAMAFILE=OFF`, `LLAMA_OPENSSL=OFF`, `ANDROID_PLATFORM=android-28`; re-confirma contra el `build.md` del commit fijado).
- **B4.** Keystore: genera una vez en el chroot (`keytool`, instala JRE si falta), guárdala **fuera del repo** con permisos 600 y súbela a GitHub Secrets (`gh secret set`). Nunca la commitees.

**Aceptación:** los 4 workflows verdes y artefactos descargables con `gh run download`, sha registrado.

---

## 6. Bloque C — `agentd` (Go, binario estático `linux/arm64`)

Desarrolla en el repo, compila en Actions, prueba en el dispositivo.

**Diseño obligatorio**
1. **DNS:** `net.Resolver{PreferGo: true, Dial: ...}` con servidores en `config.yaml` y DoH de respaldo (en Android no hay `/etc/resolv.conf`). Prueba real de resolución y TLS.
2. **Canal app ↔ agentd:** HTTP en `127.0.0.1` con token Bearer provisto por root en el directorio privado de la app (`chown` al uid + `restorecon`). Cualquier app puede conectarse a loopback, así que **sin token válido, rechazo**. Prueba negativa con otro cliente.
3. **Ejecutor:** cada herramienta es una función tipada con JSON schema. **Sin herramienta genérica de shell** (existe solo tras `--unsafe`, desactivado por defecto).
4. **Riesgo:** bajo (leer estado, abrir apps), medio (cambiar ajustes), alto (enviar, llamar, borrar, instalar, dinero). **Alto = confirmación humana obligatoria** en la app, independientemente de lo que diga el modelo.
5. **Contenido no confiable:** texto de pantalla, notificaciones, mensajes y archivos se delimita como **dato**; una inyección no puede disparar herramientas de riesgo alto sin confirmación.
6. **Auditoría:** JSONL con rotación en `/data/adb/nagent/logs/` (herramienta, argumentos, resultado, origen). Timeouts, límite de salida, cancelación, rate limiting.
7. **Memoria** en dos dominios (`user.db`, `agent.db`) con SQLite en Go puro (`modernc.org/sqlite`, porque `CGO_ENABLED=0`).
8. **Router de tres niveles** según A7 (reglas → LLM local con prefijo cacheado → remoto). Salida estructurada con JSON schema o GBNF. Prompt de sistema **corto y estable** (lo variable al final).
9. **Ciclo de vida de `llama-server`:** carga bajo demanda, descarga tras N min de inactividad (default 5), `--np 1`, `-c` explícito, `exec taskset` con PID/`comm` comprobados, `oom_score_adj` con valores medidos. Mide RAM en reposo con el modelo descargado.
10. **Prueba de integridad al arrancar:** `agentd` verifica el sha de `llama-server` y del modelo antes de lanzarlos (la carpeta `/data/adb/nagent` es escribible por el flujo del proyecto).

**Set de evaluación:** `tools/eval/cases.jsonl` con ≥ 50 casos (frase en español → llamada JSON esperada), **más** ≥ 10 casos negativos (inyección de prompt, órdenes ambiguas, riesgo alto sin confirmación). Script que mide precisión por modelo y por nivel. Sub-agente `prompt-engineer` redacta los casos; `reality-checker` los contrasta con las herramientas reales.

**Aceptación:** `go test` verde en Actions; en el dispositivo: precisión ≥ 90 % (Nivel 1) y 100 % de los negativos sin ejecutar acciones de riesgo alto; canal rechaza clientes sin token; RAM en reposo medida; auditoría escribe y rota. Informe `docs/informes/bloque-C.md`.

---

## 7. Bloque D — Servidores MCP y herramientas (4 grupos)

Transporte HTTP en loopback (+ stdio para pruebas), JSON-RPC 2.0: `initialize`, `tools/list`, `tools/call`. **Valida cada comando en este Android 14** y documenta lo que no funciona.

- **sistema:** batería y estado, brillo, volumen, Wi-Fi/Bluetooth/modo avión, No molestar, pantalla encendida/apagada, `settings` solo sobre allowlist.
- **apps:** listar, lanzar, forzar detención, abrir URL, acciones de UI (`input`), captura (`screencap`), árbol de UI (`uiautomator dump`).
- **comunicación:** notificaciones (idealmente vía `NotificationListenerService` de la app), contactos, iniciar llamada, enviar SMS (todo envío/llamada = riesgo alto).
- **archivos:** listar/leer/escribir/buscar solo en raíces permitidas (`/sdcard` y un workspace propio); prohibido el dato privado de otras apps.
- **memoria:** `remember` / `recall`.

Cada herramienta lleva: JSON schema, nivel de riesgo, prueba, y nota de fragilidad en Android 14.

**Aceptación:** `tools/list` completo; cada herramienta de riesgo bajo/medio probada en el dispositivo con evidencia; las de riesgo alto probadas solo con confirmación simulada (no se envían mensajes ni llamadas reales en las pruebas).

---

## 8. Bloque E — `nagent-app` (Kotlin, asistente sin privilegios especiales)

- Kotlin + Compose, `targetSdk` 34 (el sistema actual), `minSdk` razonable.
- `VoiceInteractionService` + `VoiceInteractionSessionService`; entrada de voz/texto (`SpeechRecognizer`, preferir reconocimiento on-device), TTS nativo, **diálogos de confirmación** para riesgo alto, pantalla de estado (salud de `agentd`, modelo cargado, RAM, últimas acciones).
- `NotificationListenerService` opcional (opt-in) que reenvía notificaciones como datos no confiables.
- Se instala como app de usuario normal firmada con la keystore del proyecto; se fija como asistente predeterminado con root (verifica la sintaxis exacta de `cmd role` en este Android).
- **Wake word:** fuera de alcance de v0.1.0 (backlog).

**Aceptación:** APK firmado y descargable desde Actions; instalado; conecta a `agentd` con el token; una orden de texto y una de voz ejecutan una herramienta de riesgo bajo de punta a punta; un riesgo alto muestra el diálogo y no se ejecuta sin confirmar.

---

## 9. Bloque F — Módulo Magisk (con activación escalonada, sin riesgo de bootloop)

**Diseño de seguridad (obligatorio):**
- **Sin `post-fs-data.sh`** y **sin `sepolicy.rule`** en la primera versión. Solo `service.sh` (tras `sys.boot_completed=1`), `customize.sh` y `uninstall.sh`.
- `customize.sh` valida `alioth`, arm64 y rango de SDK (**34 o superior**, no fijes 35); copia binarios a `/data/adb/nagent/bin`; crea directorios con permisos estrictos; genera el token; no descarga modelos.
- **Activación escalonada:** `service.sh` **solo arranca `agentd` si existe** `/data/adb/nagent/enable-autostart`. La primera instalación **no** crea ese fichero: instala archivos pero no tiene ningún efecto en el arranque.
- Contador de fallos en `service.sh`: si `agentd` cae N veces seguidas, se desactiva y deja marca.
- SELinux Enforcing; si hay AVC reales (`dmesg | grep avc`, `logcat`), añade reglas **mínimas y justificadas** en una versión posterior, nunca `permissive`.

**Pasos**
- **F1.** Construye el zip en Actions (`package-module`) con sha. Verifica `module.prop`, estructura, permisos y que no contiene `post-fs-data.sh` ni `sepolicy.rule`.
- **F2.** `docs/rollback.md`: desactivar con `touch /data/adb/modules/nagent/disable`, modo seguro, y cómo se recupera con el módulo `abootloop` (verifica que está instalado y qué hace en **este** Android: lee su `module.prop`).
- **F3.** Prueba de `agentd` **sin módulo**: lánzalo a mano por `$NS` desde `/data/adb/nagent/bin` y ejecuta los Bloques C y D completos contra él.
- **F4.** **Instalación del módulo = T3.** Redacta `docs/SOLICITUD-AUTORIZACION.md` con: la orden exacta (`magisk --install-module` sobre el zip con sha verificado, por `$NS`), la línea de autorización que debe escribir Leonardo, y el comando de rollback. **Sigue con G mientras tanto.** Si el guard deniega, no lo rodees (T2).
- **F5 (tras instalar y con autorización):** verifica archivos instalados, sin autostart. Arranca `agentd` a mano y repite una prueba corta. Después crea `enable-autostart` y haz un reinicio de prueba **solo si** los precondiciones de §9 se cumplen (abootloop presente y verificado; rollback documentado; `agentd` estable en la prueba manual). Verifica tras el reinicio: `agentd` vivo, app conectada, una orden ejecuta una herramienta. Si algo falla: rollback inmediato y anótalo.

**Etapa 7 (`priv-app`): descartada.**

---

## 10. Bloque G — Aceptación, endurecimiento y entrega

Ejecuta y reporta en `docs/acceptance-report.md`:

| Prueba | Qué medir |
|---|---|
| Arranque | sin bootloop; tiempo de boot extra |
| RAM | en reposo (modelo descargado) y con modelo cargado |
| Latencia | por nivel (0, 1, 2), local y remota |
| Precisión | tool-calling sobre el set de evaluación, por modelo |
| Batería | 8 h con y sin el módulo |
| Temperatura | inferencia sostenida |
| Estabilidad | reinicios de `agentd`, `kill`, 24 h |
| Seguridad | otra app **no** usa el canal; notificación maliciosa **no** dispara riesgo alto; auditoría completa |
| Actualizaciones | qué ocurre tras un dirty flash o downgrade (como el que acaba de pasar) y cómo se reinstala Magisk y el módulo |
| Resiliencia | con la caché en `/sdcard`, reinstalar `/data/adb/nagent` sin volver a descargar |

Entregables finales: `README`, `docs/INSTALACION.md` (desde cero en un POCO F3), `docs/LIMITACIONES.md` (lo que el guard y el sistema no cubren: scripts de sesiones sin cargo, intérpretes inline, symlinks preexistentes, `curl -o`/`wget`/`rm` no juzgados, TOCTOU de hash, la NPU Hexagon sin uso), tag `v0.1.0` y release en GitHub con los artefactos y sus sha.

**Definición de terminado (v0.1.0):**
1. `agentd` + app + módulo instalados en el teléfono y funcionando tras reinicio.
2. Una orden en español (texto o voz) ejecuta una herramienta real de punta a punta.
3. Niveles 0 y 2 operativos; Nivel 1 operativo si A7 lo declaró viable.
4. Acciones de riesgo alto siempre con confirmación humana.
5. `acceptance-report.md` sin FALLOS abiertos críticos y `LIMITACIONES.md` honesto.
6. Todo commiteado, con tag y release.

---

## 11. Formato de informe de bloque (`docs/informes/bloque-<X>.md`, máx. ~50 líneas)

```
INFORME — Bloque <X>
1. Hecho (máx. 8 líneas)
2. Evidencia (salidas reales recortadas)
3. Resultados medidos (tablas, solo si hay)
4. Decisiones tomadas y por qué
5. Suposiciones sin verificar
6. Riesgos y bloqueos (T1..T6 si aplican)
7. Archivos y commits (rutas, sha, hash de commit)
8. AGENTES USADOS: cargo: aportó y evidencia
```

---

## 12. Orden de ejecución y primera acción

**Cola de trabajo (no esperes entre ítems; si uno se bloquea, pasa al siguiente):**

1. A1 → A2 → A3 (código + lab, sin red).
2. Lanza el vigilante y la **cadena A4→A5→A6** (desacoplada) en cuanto A1–A3 estén aceptados.
3. Mientras corre la cadena **sin ocupar el teléfono con trabajo pesado**: B1–B2 (escribir y commitear; los pushes y workflows ligeros no cuentan como carga térmica si esperas a que la cadena esté en fase de espera/enfriamiento; los workflows corren en GitHub, no en el teléfono).
4. C y D (código Go y herramientas) en paralelo con la cadena; las pruebas **en el dispositivo** esperan a que el teléfono esté libre.
5. E (app) tras C/D básicos.
6. F1–F3 → F4 (solicitud) → G.
7. Al terminar la corrida (A6): A7 y ajuste de C si cambia el nivel viable.

**Primera acción de este turno:**
1. Aplica A1, A2 y A3 (con su lab, rojo → verde, `dash -n`, no-ASCII, commits).
2. Lanza el vigilante de Wi-Fi y la cadena A4→A5→A6 desacoplada.
3. Con la cadena corriendo, abre B1 (repo público) y empieza el esqueleto de C.
4. Termina el turno con el resumen de 3 líneas y `docs/ESTADO.md` actualizado.

**Delegación (mín. 3 sub-agentes por bloque, solo lectura):** `reality-checker` (verifica citas y afirmaciones), `devops-automator` (shell POSIX, namespaces, CI), `ai-engineer` (llama.cpp, formatos, modelos); según el bloque, añade `appsec-engineer` (C, F), `backend-architect` o `software-architect` (C, D), `mobile-app-builder` (E), `prompt-engineer` (set de evaluación). Un solo escritor: tú.
