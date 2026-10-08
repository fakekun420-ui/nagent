# Rollback modulo nagent (F2)

NS = `nsenter -t 1 -m --` (el /data/adb del chroot es otro espejo; todo por $NS).

## 1. Desactivar sin desinstalar (reversible, primer paso ante fallo)
$NS touch /data/adb/modules/nagent/disable
$NS reboot
Reactivar: `$NS rm /data/adb/modules/nagent/disable` + reboot.

## 2. Desinstalar desde Magisk (con sistema arrancado)
App Magisk -> Modulos -> nagent -> Eliminar -> reboot.

## 3. Modo seguro (si no arranca bien)
Volumen-abajo durante el arranque: Magisk safe mode desactiva modulos.
Luego retirar nagent (paso 1-2) y reinicio normal.

## 4. Modulo abootloop (instalado: ver docs/00-entorno-v2.md, 10 modulos)
$NS ls /data/adb/modules
$NS cat /data/adb/modules/abootloop/module.prop
Si hay bootloop, abootloop desactiva modulos solo; despues retirar nagent.

## 5. Manual por root (ultimo recurso)
$NS touch /data/adb/modules/nagent/disable
$NS rm /data/adb/nagent/enable-autostart
$NS pkill -f /data/adb/nagent/bin/agentd
Verificar: agentd muerto, autostart fuera, modulo en disable.

## 6. Que NO se borra solo
/data/adb/nagent/models (6.3 GB) y logs sobreviven: reinstalar no
re-descarga (resiliencia, Bloque G). Borrado total solo manual.
