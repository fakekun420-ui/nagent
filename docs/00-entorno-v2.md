# Entorno v2 - 2026-10-08 (tras downgrade crDroid)

Metodo: todo por `$NS="nsenter -t 1 -m --"` (el chroot no tiene getprop ni
ve /data/adb). Fecha de medida: 2026-10-08T04:17:31Z (host). Toda cifra
anterior (umbrales, smoke, baselines del 2026-10-03) queda HISTORICA y no
vale para este sistema.

## Identidad
| campo | valor | metodo |
|---|---|---|
| release | 14 | getprop ro.build.version.release |
| sdk | 34 | getprop ro.build.version.sdk |
| display | AP2A.240905.003 | getprop ro.build.display.id |
| date | Fri May 23 08:43:37 CEST 2025 | getprop ro.build.date |
| device | alioth | getprop ro.product.device |
| privapp | enforce | getprop ro.control_privapp_permissions |
| zygote | zygote64_32 | getprop ro.zygote |
| slot | _b | getprop ro.boot.slot_suffix |
| bootreason | reboot, | getprop sys.boot.reason / ro.boot.bootreason |
| uptime | 49 min (04:17Z) | uptime host |

## Kernel y SELinux
- host: Linux 4.19.322~InfiniR_Alioth_v2.98_KSUN_raystef66 #147 SMP PREEMPT
  (uname -a via $NS; chroot ve el mismo -r). Antes: v2.99 (downgrade OK).
- getenforce (host): Enforcing.

## Magisk y modulos (10)
- Magisk: 30700 (bin /data/adb/magisk/magisk; `magisk` no esta en PATH del host).
- Modulos: Malwack abootloop busybox-ndk djs flag-secure-disabler
  playintegrityfix universal-gms-doze zn_magisk_compat zram-swap-manager
  zygisksu (ls /data/adb/modules via $NS).

## CPU (SM8250, 8 cores)
- cpu0-3: max 1804800 min 300000 gov schedutil (little).
- cpu4-6: max 2419200 min 710400 gov schedutil (big).
- cpu7: max 3187200 min 844800 gov schedutil (prime).
- Features (los 8 iguales): fp asimd evtstrm aes pmull sha1 sha2 crc32
  atomics fphp asimdhp cpuid asimdrdm lrcpc dcpop asimddp (/proc/cpuinfo).
- Afinidad del spike (mascara hex toybox, sin -c): AFF_3=70 -> cpu4-6,
  AFF_4=f0 -> cpu4-7. Verificado en smoke real 3-oct.

## Termicas (tipos estables, numeros NO)
- 11=cpu-1-4-usr 12=cpu-1-5-usr 13=cpu-1-6-usr 14=cpu-1-7-usr
  (spike.sh las busca por tipo: zone_by_type).
- 92=battery (41700 = 41.7 C al medir). pm8150b-vbat-lvl0/1/2 = 3786.
- spike.sh/medir-reposo.sh buscan por tipo y abortan si faltan (exit 4);
  los numeros 11-14/92 solo viven en fixtures del lab, no en produccion.

## Power
- /sys/power/wake_lock SI, /sys/power/wake_unlock SI
  (radio:wakelock; root escribe OK).
- /sys/power/wake_lock_timeout NO existe (este kernel).
- Regla medida: el TAG no admite espacios (rc=1 con espacio, rc=0 sin el).

## Memoria y disco
- MemTotal 11858276 kB, MemFree 508640 kB, MemAvailable 5226684 kB.
- /data: 225G total, 75G usados, 151G libres (34%).
- pstore: console-ramoops-0 + pmsg-ramoops-0 presentes.

## Toolchain (toybox 0.8.10-android)
- taskset: `taskset [-ap] [mask] [PID|cmd]` (mascara hex, sin -c).
- nsenter: `nsenter [-t pid] [-F] [-i] [-m] [-n] [-p] [-u] [-U] COMMAND`.
- curl 8.6.0-DEV Android (BoringSSL). tar toybox. sha256sum toybox
  (`???sum [-bcs] [FILE]`). awk 20231124. wc `[-Llwcm]`. df `[-aHhikP]`.

## Que sobrevivio
- SI: chroot /data/local/ubuntu, /sdcard (=/data/media/0, FUSE 151G libres),
  /data/adb/* (config, magisk, 10 modulos, service.d), repo nagent.
- NO: /data/adb/nagent (bins b11146, 4 modelos SHA-OK, $LOGS del smoke).
  Causa: reestructuracion con downgrade informada por Leonardo; no se afirma
  mecanismo mas alla de eso. prep.sh NO se re-ejecuta hasta nueva orden.

## Discrepancias script vs real (ninguna bloquea)
1. SDK: ningun script exige 34/35 (solo ANDROID_PLATFORM=android-28 de build
   en docs). Sin accion.
2. Kernel v2.98 vs v2.99: ningun script lo menciona. Sin accion.
3. Zonas: produccion por tipo (spike.sh:213-235, medir-reposo.sh:7-13);
   `docs/spike-rendimiento.md:139` aun dice `taskset -c` (doc historico).
4. wake_lock_timeout: correr-completo.sh ya usa lock clasico + renuevo
   (nodo inexistente verificado). Sin accion.
5. Umbrales: spike.sh 4/60 vs correr-completo.sh exporta 8/60 vs docs
   viejos 3/50. Valor efectivo depende del lanzador. Re-calibrar con
   medir-reposo.sh en este sistema antes de fijarlos.
