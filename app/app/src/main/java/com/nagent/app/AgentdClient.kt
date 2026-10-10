package com.nagent.app

import java.io.File
import java.net.HttpURLConnection
import java.net.URL

// Cliente HTTP a agentd por loopback (C2). Token desde filesDir (lo deja root
// en /data/data/com.nagent.app/files/agentd.token, 600). Sin coroutines a
// proposito: Thread + callback, cero dependencias nuevas.
object AgentdClient {
    const val BASE = "http://127.0.0.1:8765"

    fun leerToken(filesDir: File): String? {
        return try {
            File(filesDir, "agentd.token").takeIf { it.exists() }?.readText()?.trim()
        } catch (_: Exception) {
            null
        }
    }

    private fun get(token: String, path: String): String? {
        return try {
            val c = URL(BASE + path).openConnection() as HttpURLConnection
            c.setRequestProperty("Authorization", "Bearer $token")
            c.connectTimeout = 5000
            c.readTimeout = 15000
            if (c.responseCode != 200) return null
            c.inputStream.bufferedReader().readText()
        } catch (_: Exception) {
            null
        }
    }

    fun salud(token: String): Boolean = get(token, "/health")?.contains("ok") == true

    // Diagnostico visible: dice QUE fallo en vez de solo nulo (E2E).
    fun diagnostico(token: String): String {
        return try {
            val c = URL(BASE + "/health").openConnection() as HttpURLConnection
            c.setRequestProperty("Authorization", "Bearer $token")
            c.connectTimeout = 5000
            c.readTimeout = 15000
            val code = c.responseCode
            if (code != 200) return "HTTP " + code
            val txt = c.inputStream.bufferedReader().readText()
            if (txt.contains("ok")) "agentd OK" else "raro: " + txt.take(60)
        } catch (e: Exception) {
            "EX " + e.javaClass.simpleName + ": " + e.message
        }
    }

    // Devuelve Pair(respuesta, pendiente?): pendiente es el nombre si agentd
    // pidio confirmacion (riesgo alto, R7: nunca ejecuta sin ella).
    fun llamar(token: String, nombre: String, argsJson: String): Pair<String, String?> {
        return try {
            val body = "{\"nombre\":\"" + nombre + "\",\"args\":" + argsJson + "}"
            val c = URL(BASE + "/tools/call").openConnection() as HttpURLConnection
            c.requestMethod = "POST"
            c.setRequestProperty("Authorization", "Bearer $token")
            c.setRequestProperty("Content-Type", "application/json")
            c.doOutput = true
            c.connectTimeout = 5000
            c.readTimeout = 30000
            c.outputStream.bufferedWriter().use { it.write(body) }
            if (c.responseCode != 200) return Pair("HTTP " + c.responseCode, null)
            val txt = try {
                c.inputStream.bufferedReader().readText()
            } catch (_: Exception) {
                ""
            }
            val pend = if (txt.contains("\"estado\":\"pendiente\"")) nombre else null
            Pair(txt, pend)
        } catch (e: Exception) {
            Pair("FALLO red: " + e.message, null)
        }
    }
}
