# SOLICITUD-AUTORIZACION - F4 instalacion modulo (T3)

Estado: zip pendiente (package-module aun no corre: sin Wi-Fi no medida).
Esta solicitud queda PREPARADA; la instalacion espera al zip verificado.

Orden exacta (por $NS; `magisk` no esta en PATH del host):
sha256sum -c nagent-module-v0.1.0.zip.sha256 && nsenter -t 1 -m -- /data/adb/magisk/magisk --install-module /sdcard/dist/nagent-module-v0.1.0.zip

Linea que debe escribir Leonardo (copiar literal):
AUTORIZO-F4: instala el modulo nagent v0.1.0 con magisk --install-module por $NS sobre el zip con sha verificado.

Rollback inmediato:
nsenter -t 1 -m -- touch /data/adb/modules/nagent/disable && nsenter -t 1 -m -- reboot

Precondiciones F5 antes de enable-autostart: abootloop presente y
verificado, rollback documentado (docs/rollback.md), agentd estable en
prueba manual F3.
