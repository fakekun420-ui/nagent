# Backend Hexagon: descartado para el POCO F3 (alioth / SM8250)

Fecha: 2026-10-02. Decisión: **no usar el backend `GGML_HEXAGON` en este dispositivo.**

Fuente de código: llama.cpp commit `7fe450e19305b828c199d602c23a8337aaa1f03b` (tag `b11146`).

---

## 1. Qué envuelve llama.cpp

`ggml/src/ggml-hexagon/CMakeLists.txt` compila y empaqueta skels HTP **solo para cuatro versiones**:

```cmake
78: build_htp_skel(v73)
79: build_htp_skel(v75)
80: build_htp_skel(v79)
81: build_htp_skel(v81)
```

Instalados: `libggml-htp-v73.so`, `-v75.so`, `-v79.so`, `-v81.so`.
**No existe ningún skel v66, v68 ni v69.** El suelo del backend es v73.

## 2. Qué ocurre con un SoC anterior a v73

`ggml/src/ggml-hexagon/ggml-hexagon.cpp` consulta la versión real al DSP y luego la recorta:

```cpp
7780: int err = htpdrv_get_arch(CDSP_DOMAIN_ID, &opt_arch);
7782:   GGML_LOG_ERROR("ggml-hex: failed to query HTP version (err %d) defaulting to v73\n", err);
7783:   opt_arch = 73;
7785:   if (opt_arch < 73) {
7786:     GGML_LOG_WARN("ggml-hex: Hexagon arch v%d is under supported range, capping at v73\n", opt_arch);
7787:     opt_arch = 73;
7788:   } else if (opt_arch > 81) { ... opt_arch = 81; }

3890: snprintf(htp_uri, ..., "file:///libggml-htp-v%u.so?...", opt_arch);
7803: opt_vmem = opt_arch >= 75 ? HTP_OP_MAX_VMEM_DEFAULT : 3000 * MiB;
7804: opt_dma64 = opt_arch > 79 && (...);
7409: GGML_LOG_INFO("ggml-hex: Hexagon Arch version v%d, DMA64 %s\n", opt_arch, ...);
```

Dos consecuencias, y la segunda es la peligrosa:

1. Sobre un DSP anterior a v73 **intentaría cargar `libggml-htp-v73.so`**. Es una suposición de
   compatibilidad hacia delante, no un camino soportado.
2. **El diagnóstico no diría la verdad.** La línea 7409 imprime `opt_arch`, que ya fue recortado a
   73. Un usuario vería `Hexagon Arch version v73` en un chip que no es v73, y no distinguiría
   "soportado" de "recortado". Solo el `WARN` de 7786 delata el recorte, y es un aviso, no un error.

## 3. Dónde cae el SM8250

| Hecho | Fuente |
|---|---|
| Snapdragon 865 / 865+ / **870** → SoC **SM8250**, DSP **Hexagon 698**, 15 TOPS | tabla de Qualcomm Hexagon (Wikipedia, con cita a las fichas de Qualcomm) `[VERIFICADO: busqueda web]` |
| El coprocesador HMX, que es lo que convierte el CDSP en **HTP** propiamente dicho, aparece a partir de **SM8350** | documentación técnica de Qualcomm/Hexagon `[VERIFICADO: busqueda web]` |
| Qualcomm da por **obsoletos** los targets HVX `v66` y `v68`; el conjunto soportado es `v69, v73, v75, v79` y el mínimo es v68 | *Halide for HVX User Guide*, docs.qualcomm.com `80-PD002-1` `[VERIFICADO: busqueda web]` |
| Documentos de referencia de Qualcomm existen para V68 (`80-N2040-46`, jun-2020) y para V73 (`80-N2040-53/54`, ene-2024) | docs.qualcomm.com `[VERIFICADO: busqueda web]` |

**El SM8250 está por debajo del suelo de v73 que exige llama.cpp.** La cifra exacta
(v66 o v68) es irrelevante para la decisión: ambas quedan por debajo. `[SUPOSICIÓN: el valor
concreto que devolvería htpdrv_get_arch en este teléfono; no se ha medido]`

## 4. Conclusión

El backend Hexagon queda **descartado** para el POCO F3:

- El SoC pertenece a una generación anterior a la aparición del HTP como tal.
- llama.cpp no empaqueta skel para su versión.
- El mecanismo de recorte lo **ocultaría** en el log, dando una falsa impresión de compatibilidad.

La NPU del Snapdragon 870 (Hexagon 698, 15 TOPS) queda por tanto **sin usar** en el proyecto.
No se pierde capacidad de la que dependamos: el plan nunca la había asumido como premisa, así
que no se descarta ninguna decisión previa. El techo de 3B local se decide **solo con CPU**.

## 5. Efecto colateral

Esto refuerza el descarte del build `-snapdragon` ya decidido: además de compilar con
`-march=armv8.7a+...+i8mm` (que este SoC no soporta), su mitad "Hexagon" tampoco aplica aquí.
Del preset solo queda potencialmente útil `GGML_OPENCL`, que se tratan aparte cuando exista
línea base de CPU.