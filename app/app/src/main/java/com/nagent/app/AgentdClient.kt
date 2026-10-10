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
    // Prueba TCP puro a 8765 y a 18080 (cerrado = control: debe dar refused).
    fun diagnostico(token: String): String {
        val r = StringBuilder()
        r.append("token=").append(token.length).append(" ")
        r.append(probar("127.0.0.1", 8765))
        r.append(probar("127.0.0.1", 18080))
        r.append(probar("8.8.8.8", 53))
        if (r.contains("127.0.0.1:8765=ABIERTO")) {
            r.append(salud(token))
        }
        return r.toString().take(200)
    }

    private fun probar(host: String, port: Int): String {
        return try {
            val s = java.net.Socket()
            s.connect(java.net.InetSocketAddress(host, port), 3000)
            s.close()
            host + ":" + port + "=ABIERTO "
        } catch (e: Exception) {
            host + ":" + port + "=" + e.javaClass.simpleName + ":" + e.message + " "
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
