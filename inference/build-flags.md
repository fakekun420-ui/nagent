# Inference b11146 - flags fijados (Etapa 0.5)

Tag: b11146, commit 7fe450e19305b828c199d602c23a8337aaa1f03b.
Manifiesto de artefactos y modelos: docs/manifest-sha256.md.

Flags de build (si A7 exige build propio en Actions, Bloque B3):
GGML_CPU_KLEIDIAI=ON GGML_NATIVE=OFF GGML_OPENMP=OFF
GGML_LLAMAFILE=OFF LLAMA_OPENSSL=OFF ANDROID_PLATFORM=android-28

SM8250 (Snapdragon 865): sin i8mm ni SVE (verificado en /proc/cpuinfo,
Features del entorno v2). Backend Hexagon descartado para este SoC
(docs/hexagon-backend.md): v66/v68 bajo el minimo v73 de llama.cpp.
Los binarios oficiales solo arrancan con LD_LIBRARY_PATH=$BIN (medido).
