# Etapa 0.5 — Spike de rendimiento (informe)

Estado: **BLOQUEADO antes de medir**. Todo lo preparatorio está verificado y fijado; falta
ejecutar el binario y descargar los modelos. Ver §5.

---

## 1. Versiones fijadas

| Elemento | Valor | Fuente |
|---|---|---|
| llama.cpp tag | `b11146` (nightly, 2026-09-23) | `[VERIFICADO: api.github.com/repos/ggml-org/llama.cpp/releases/tags/b11146]` |
| llama.cpp commit | `7fe450e19305b828c199d602c23a8337aaa1f03b` | `[VERIFICADO: git/refs/tags/b11146 -> .object.sha, tipo "commit"]` |
| `docs/build.md` en ese commit | 42 185 bytes | `[VERIFICADO: raw.githubusercontent.com/.../7fe450e1.../docs/build.md]` |
| Artefacto Android arm64 | `llama-b11146-bin-android-arm64.tar.gz`, 72 535 052 B | `[VERIFICADO: release b11146 assets]` |
| SHA-256 del artefacto | `b0d154dffd3b012cac34830349725a0ee3fb6eb5e11c8aac18527b3357a79687` | `[VERIFICADO: campo "digest" de la API de GitHub]` |

NDK: **no fijado todavía**. El build del spike usa el binario oficial precompilado, no un
build propio con NDK. Fijar la versión de NDK corresponde a la Etapa 1 (workflow propio).

## 2. Flags de build — verificados contra el commit fijado

Comprobado por presencia literal en el `build.md` **de `7fe450e1`**, no de `master`:

| Flag | Estado en ese commit |
|---|---|
| `GGML_CPU_KLEIDIAI` | PRESENTE (5 menciones) |
| `GGML_NATIVE` | PRESENTE (5) |
| `GGML_OPENMP` | PRESENTE (5) |
| `GGML_LLAMAFILE` | PRESENTE (2) |
| `LLAMA_OPENSSL` | PRESENTE (2) |
| `ANDROID_ABI` (`arm64-v8a`) / `ANDROID_PLATFORM` (`android-28`) | PRESENTE (3 / 3) |
| `GGML_CPU_ARM_ARCH` | **AUSENTE (0 menciones)** |

`GGML_CPU_ARM_ARCH` queda **eliminado del plan**, como se ordenó.

Comando canónico citado por el propio repo para Android arm64-v8a con KleidiAI:

```bash
cmake -S . -B build-android -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-28 \
  -DGGML_CPU_KLEIDIAI=ON -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF \
  -DGGML_LLAMAFILE=OFF -DLLAMA_OPENSSL=OFF
```

## 3. Modelos candidatos — hashes autoritativos ya obtenidos

Los cuatro existen en los **repos oficiales de Qwen**, con las dos cuantizaciones pedidas.
SHA-256 tomado del campo LFS `oid` de la API de Hugging Face (fuente autoritativa, no del README).

| Modelo | Formato | Tamaño | SHA-256 |
|---|---|---|---|
| `Qwen/Qwen2.5-1.5B-Instruct-GGUF` | Q4_0 | 1.07 GB | `dcd819ff094852c38faba6873d8ff0c9d51eadb2844539e52042ae5d647bbfdb` |
| `Qwen/Qwen2.5-1.5B-Instruct-GGUF` | Q4_K_M | 1.12 GB | `6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e` |
| `Qwen/Qwen2.5-3B-Instruct-GGUF` | Q4_0 | 2.00 GB | `670d82d0fbee6289b661eb323612c65bd2e97ec8c65cdbd9131aa44d30e9816a` |
| `Qwen/Qwen2.5-3B-Instruct-GGUF` | Q4_K_M | 2.10 GB | `626b4a6678b86442240e33df819e00132d3ba7dddfe1cdc4fbb18e0a9615c62d` |

Descarga total: **≈6,3 GB**. Espacio disponible: 117 GB. Sin problema de disco.

## 4. Entorno de medición — línea base registrada

Medido con `nsenter -t 1 -m --`, 2026-10-02:

```
loadavg:      6.08  6.50  5.65  3/4892       (8 nucleos online: 0-7)
MemTotal:     11858276 kB
MemAvailable:  4894028 kB
AC powered: true    status: 2 (cargando)
CPU0..CPU3:   57.2 / 56.8 / 56.4 / 57.2 °C
CPU4..CPU7:   60.0 / 59.2 / 58.8 / 61.9 °C     <-- prime ya a 61.9
battery:      42.7 °C    GPU0: 52.9 °C
```

Consumo actual: `opencode` 47.3 %, `com.termux` 45.4 %, `surfaceflinger` 23.0 %,
`opencode.exe` 22.6 %.

**El teléfono está saturado (load 6.08 de 8) y el prime ya está a 61,9 °C.** Medir
`llama-bench` en este estado daría cifras que no significan nada. Por eso no se ha intentado
ninguna medición todavía.

## 5. Bloqueos que impiden medir

### 5.1 Guard de escritura vs. ruta de binarios — **conflicto de reglas, requiere decisión**

`/data/adb/nagent/` es donde deben vivir binarios y modelos, pero el guard de escritura del
entorno rechaza cualquier orden que mencione esa ruta, y la única vía que ofrece para
autorizarla es escribir un token en
`/sdcard/projects/Kaenor-Inc/estado/autoriza-una-ves.txt`.

Eso choca con tu instrucción literal: **«No toques nada más dentro de `/sdcard/projects/`»**.
No he escrito ese token ni he buscado una vía alternativa. Necesito que decidas cuál regla
gusta.

### 5.2 Saturación del dispositivo — requiere tu confirmación

Por §4.3 no puedo parar procesos sin tu confirmación. Lo que propongo **detener**, en este orden
y solo con tu «continuar»:

1. La sesión `opencode.exe serve` en `:49374` — es la que me está consumiendo el 22-45 % de CPU.
   **Caveat**: pararla me corta a mí mismo y a cualquier otra sesión con trabajo en curso (§5.2
   del entorno global: reiniciar el servidor requiere tu OK explícito).
2. Cerrar las apps que consumen RAM sin necesidad (≈2,8 GB: TTS de Google, diccionario de Gboard,
   GMS). No afecta a la medición de CPU, pero libera margen para el modelo.

Con el load por debajo de 1 y el prime por debajo de 45 °C, el spike es medible.

## 6. Anomalía registrada

`thermalservice` reporta `mType=8, mName=soc, mValue=0.0, mStatus=6`. El estado 6 en
`ThermalManager` corresponde a *shutdown*, pero el valor es 0.0, lo que apunta a un sensor
placeholder de crDroid y no a un evento térmico real. **No se puede afirmar con los datos
actuales**; queda como `SUPOSICIÓN` a verificar antes de fiarse de este sensor en la Etapa 8.

## 7. FUSE — comportamiento comprobado

| Comprobación | Resultado |
|---|---|
| `core.fileMode` / `core.symlinks` en `.git/config` | `false` / `false` `[VERIFICADO: cat .git/config]` |
| Bit de ejecución tras `chmod 755` en `/sdcard/projects/nagent/` | **Se pierde**: el archivo queda `rw-rw----` |
| Integridad de escritura | OK (sha256 y tamaño verificados tras cada escritura) |

La pérdida del bit de ejecución **confirma empíricamente tu instrucción** de que los binarios
no pueden vivir en el repo. Sin esto habríamos intentado ejecutar desde `/sdcard` y habríamos
perdido el tiempo.

## 8. Matriz de medición — PENDIENTE

Sin completar. Se rellena cuando se resuelvan §5.1 y §5.2.

| Modelo | Formato | Hilos (fijados con `taskset`) | pp512 tok/s | tg128 tok/s | TTFT frío | TTFT caliente | RAM pico | Temp. 5 min |
|---|---|---|---|---|---|---|---|---|
| — | — | 3 en cpu4-6 | — | — | — | — | — | — |
| — | — | 4 en cpu4-7 | — | — | — | — | — | — |

Criterio: 3 repeticiones por celda, se reporta **mediana y dispersión**, no la media.

Procedimiento fijado de antemano para que las cifras sean comparables:
- `taskset -c 4,5,6` y `taskset -c 4,5,6,7`
- `llama-bench -p 512 -n 128` con el mismo `--model` y sin `--mlock`
- `llama-server` con `cache_prompt` on/off, prompt de sistema fijo de ~1000 tokens y 10 órdenes
  cortas distintas de ~30-50 tokens; TTFT del primer request (frío) frente a la media de los
  9 siguientes (caliente). `--slot-save-path` solo si existe en `b11146` (no verificado aún).

## 9. Conclusión provisional

Ninguna. Sin mediciones, cualquier conclusión sobre si el techo de 3B es viable sería
inventada. Lo único establecido hasta ahora es que el dispositivo tiene margen de RAM para un
3B Q4 (~4,9 GB disponibles frente a ~2,5 GB de pesos + KV) y que el techo real lo pondrá la
velocidad, no la memoria — pero eso es hipótesis, no dato.

---

## 10. Propuesta (no ejecutada)

Existe `llama-b11146-bin-android-arm64-**snapdragon**.tar.gz` (56,7 MB,
sha256 `f1c8402f869b6fcf9eae39e8f5a87cee7661bde3c59314ff4625ddc986c4ec88`)
`[VERIFICADO: release b11146 assets]`. El changelog de `v0.5.0` incluye
`ee3ecce05: publish snapdragon builds in release workflow (#29007)`, es decir que hay backends
específicos de Snapdragon (QNN/Hexagon). El POCO F3 lleva Snapdragon 870 con **DSP Hexagon 698
y GPU Adreno**, así que un backend acelerado podría cambiar la conclusión del spike por
completo. **No lo he descargado ni probado**: queda fuera del alcance de la Etapa 0.5 y espero
tu "continuar" para tratarlo.