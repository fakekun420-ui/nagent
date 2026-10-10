package com.nagent.app

// Nivel 0: reglas deterministicas texto -> (herramienta, argsJson).
// A7: siempre activo. Si no hay regla segura, null (la app dice que no entiende).
// Riesgo alto (llamar, sms, borrar, instalar, detener) se mapea igual: agentd
// lo deja pendiente y la app pide confirmacion (R7). Nada se ejecuta solo.
object Nivel0 {
    fun mapear(texto: String): Pair<String, String>? {
        val t = texto.lowercase()
        if (t.contains("bateria") || t.contains("carga") || t.contains("nivel")) {
            return Pair("estado_bateria", "{}")
        }
        if (t.contains("brillo")) {
            val n = Regex("(\\d{1,3})").find(t)?.groupValues?.get(1)?.toIntOrNull()
            if (n != null && n in 0..255) return Pair("brillo_set", "{\"valor\":" + n + "}")
            return Pair("ajuste_get", "{\"ns\":\"system\",\"key\":\"screen_brightness\"}")
        }
        if (t.contains("volumen") || t.contains("sonido") || t.contains("silencio")) {
            val dir = if (t.contains("baja") || t.contains("silencio")) "bajar" else "subir"
            return Pair("volumen_tecla", "{\"dir\":\"" + dir + "\",\"pasos\":1}")
        }
        if ((t.contains("app") || t.contains("aplicacion")) &&
            (t.contains("lista") || t.contains("instalada") || t.contains("hay"))
        ) {
            return Pair("listar_apps", "{}")
        }
        if (t.contains("notificacion") || t.contains("notificaciones") || t.contains("aviso")) {
            return Pair("leer_notificaciones", "{}")
        }
        if (t.contains("llama") || t.contains("llamar") || t.contains("llamada")) {
            return Pair("iniciar_llamada", "{\"destino\":\"\"}")
        }
        if (t.contains("sms") || t.contains("mensaje") || t.contains("envia")) {
            return Pair("enviar_sms", "{\"destino\":\"\",\"cuerpo\":\"\"}")
        }
        if (t.contains("borra") || t.contains("borrar") || t.contains("elimina") || t.contains("eliminar")) {
            return Pair("borrar_archivo", "{\"ruta\":\"\"}")
        }
        if (t.contains("instala") || t.contains("instalar")) {
            return Pair("instalar_app", "{\"paquete\":\"\"}")
        }
        if (t.contains("deten") || t.contains("detener") || t.contains("cierra")) {
            return Pair("forzar_detencion", "{\"paquete\":\"\"}")
        }
        if (t.contains("sistema") || t.contains("estado del telefono")) {
            return Pair("estado_sistema", "{}")
        }
        return null
    }
}
