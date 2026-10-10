# AUTORIZACION F4 - OTORGADA por Leonardo (turno 2026-10-10)

Linea literal de Leonardo (vale como autorizacion T3):
"Crea e instala el modulo magisk sin reiniciar el dispositivo."

Alcance: SOLO instalacion. Sin reinicio (F5 queda pendiente con su OK).

Zip verificado (Actions run 38011598170, package-module con agentd 37969923493):
sha256 927c5a85fda0db21, con bin/agentd, sin post-fs-data, sin sepolicy.rule,
sin enable-autostart (activacion escalonada: instala archivos, no arranca nada).

Orden exacta ejecutada (por $NS; magisk solo en /data/adb/magisk/magisk):
nsenter -t 1 -m -- /data/adb/magisk/magisk --install-module /sdcard/projects/nagent/.lab/stage-module.zip

Rollback sin reinicio (respeta el alcance):
nsenter -t 1 -m -- touch /data/adb/modules/nagent/disable
(nsenter -t 1 -m -- reboot queda SOLO para F5 con OK aparte.)

Precondiciones F5 (pendientes): abootloop presente (verificado en /data/adb/modules),
rollback documentado (docs/rollback.md), agentd estable en F3 (verificado).
