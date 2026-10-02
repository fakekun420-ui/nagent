# Manifiesto SHA-256 — Etapa 0.5 (spike de rendimiento)

Fuentes de los hashes (ambas autoritativas, no hay que confiar en el README):

- **Artefactos**: campo `digest` de la API de GitHub Releases
  (`api.github.com/repos/ggml-org/llama.cpp/releases/tags/b11146`).
  `[VERIFICADO: fetch de la API, 2026-10-02]`
- **Modelos**: campo LFS `oid` de la API de Hugging Face
  (`huggingface.co/api/models/<repo>/tree/main?recursive=1`), que es el SHA-256 real del blob.
  `[VERIFICADO: fetch de la API, 2026-10-02]`

llama.cpp: tag `b11146` → commit **`7fe450e19305b828c199d602c23a8337aaa1f03b`**
`[VERIFICADO: git/refs/tags/b11146 -> .object.sha, tipo "commit"]`

Destino en el dispositivo: `/data/adb/nagent/`. **Nunca dentro del repo.**

---

## A. Artefactos de llama.cpp

| Archivo | Bytes | SHA-256 |
|---|---|---|
| `llama-b11146-bin-android-arm64.tar.gz` | 72535052 | `b0d154dffd3b012cac34830349725a0ee3fb6eb5e11c8aac18527b3357a79687` |
| `llama-b11146-bin-android-arm64-snapdragon.tar.gz` | 56736251 | `f1c8402f869b6fcf9eae39e8f5a87cee7661bde3c59314ff4625ddc986c4ec88` |

URL base: `https://github.com/ggml-org/llama.cpp/releases/download/b11146/<archivo>`

El segundo queda **listado pero no descargado**: ver `docs/spike-rendimiento.md` §10.
Compila con `-march=armv8.7a+...+i8mm` y este SoC no tiene i8mm.

## B. Modelos (repos oficiales de Qwen)

| Archivo | Bytes | SHA-256 |
|---|---|---|
| `qwen2.5-1.5b-instruct-q4_0.gguf` | 1066227232 | `dcd819ff094852c38faba6873d8ff0c9d51eadb2844539e52042ae5d647bbfdb` |
| `qwen2.5-1.5b-instruct-q4_k_m.gguf` | 1117320736 | `6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e` |
| `qwen2.5-3b-instruct-q4_0.gguf` | 1997879712 | `670d82d0fbee6289b661eb323612c65bd2e97ec8c65cdbd9131aa44d30e9816a` |
| `qwen2.5-3b-instruct-q4_k_m.gguf` | 2104932768 | `626b4a6678b86442240e33df819e00132d3ba7dddfe1cdc4fbb18e0a9615c62d` |

URL:

```
https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_0.gguf
https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf
https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_0.gguf
https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf
```

**Total modelos: 6286359448 bytes (≈5,85 GiB).** Con el tarball: 6,42 GB.
Espacio libre en `/data`: **117 GB** (`[VERIFICADO: df -h /data]`). Margen de ~18×.

## C. Verificación

```sh
# sobre los ficheros ya descargados en /data/adb/nagent/
cd /data/adb/nagent
sha256sum -c <<'EOF'
b0d154dffd3b012cac34830349725a0ee3fb6eb5e11c8aac18527b3357a79687  bin/llama-b11146-bin-android-arm64.tar.gz
dcd819ff094852c38faba6873d8ff0c9d51eadb2844539e52042ae5d647bbfdb  models/qwen2.5-1.5b-instruct-q4_0.gguf
6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e  models/qwen2.5-1.5b-instruct-q4_k_m.gguf
670d82d0fbee6289b661eb323612c65bd2e97ec8c65cdbd9131aa44d30e9816a  models/qwen2.5-3b-instruct-q4_0.gguf
626b4a6678b86442240e33df819e00132d3ba7dddfe1cdc4fbb18e0a9615c62d  models/qwen2.5-3b-instruct-q4_k_m.gguf
EOF
```

`tools/spike.sh` hace esta comprobación automáticamente antes de medir y **aborta** si algo
no cuadra. No se mide sobre ficheros no verificados.

## D. Nota sobre el bit de ejecución

`/data` está montado `nosuid,nodev` pero **no** `noexec`
`[VERIFICADO: /proc/mounts -> /dev/block/sda35 ... nosuid,nodev,noatime]`,
y el chroot corre en `u:r:magisk:s0`, desde donde `nsenter` ejecuta arm64 nativo sin problema
`[VERIFICADO: nsenter -t 1 -m -- /data/adb/magisk/busybox uname -m -> aarch64]`.

En `/sdcard/projects/` el bit de ejecución **se pierde** (verificado: `chmod 755` → `rw-rw----`).
Por eso los binarios van a `/data/adb/nagent/bin/` y no al repo.
