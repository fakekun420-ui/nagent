package com.nagent.app

import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

// Cliente HTTP a agentd por loopback (C2). Token desde filesDir (lo deja root).
// Transporte: directo primero (1.5s); si la sandbox bloquea los sockets del UID
// (netd restricted sin el UID en allowlist, medido 2026-10-10), fallback por
// `su -c curl` (la app tiene root concedido por Magisk). Sin dependencias nuevas.
object AgentdClient {
    const val BASE = "http://127.0.0.1:8765"

    fun leerToken(filesDir: File): String? {
        return try {
            File(filesDir, "agentd.token").takeIf { it.exists() }?.readText()?.trim()
        } catch (_: Exception) {
            null
        }
    }

    // Ejecuta argv y devuelve Pair(rc, stdout recortado). Timeout duro.
    private fun correr(argv: Array<String>, segundos: Long): Pair<Int, String> {
        return try {
            val p = Runtime.getRuntime().exec(argv)
            val ok = p.waitFor(segundos, TimeUnit.SECONDS)
            if (!ok) {
                p.destroyForcibly()
                return Pair(124, "")
            }
            val out = try {
                p.inputStream.bufferedReader().readText()
            } catch (_: Exception) {
                ""
            }
            Pair(p.exitValue(), out)
        } catch (e: Exception) {
            Pair(127, "EX " + e.message)
        }
    }

    // GET por su. Devuelve cuerpo o null.
    private fun suGet(token: String, path: String, cache: File): String? {
        val url = BASE + path
        val cmd = "curl -s -m 10 -H 'Authorization: Bearer " + token + "' '" + url + "'"
        val r = correr(arrayOf("su", "-c", cmd), 15)
        if (r.first != 0) return null
        return r.second.ifEmpty { null }
    }

    private fun directo(path: String, token: String): String? {
        return try {
            val c = URL(BASE + path).openConnection() as HttpURLConnection
            c.setRequestProperty("Authorization", "Bearer $token")
            c.connectTimeout = 1500
            c.readTimeout = 4000
            if (c.responseCode != 200) return null
            c.inputStream.bufferedReader().readText()
        } catch (_: Exception) {
            null
        }
    }

    fun salud(token: String, cache: File): Boolean {
        val d = directo("/health", token)
        if (d != null) return d.contains("ok")
        val s = suGet(token, "/health", cache)
        return s != null && s.contains("ok")
    }

    // Diagnostico visible: prueba directa y por su, dice QUE fallo (E2E).
    fun diagnostico(token: String, cache: File): String {
        val r = StringBuilder()
        r.append("token=").append(token.length).append(" ")
        r.append("directo=").append(directo("/health", token)?.take(20) ?: "FALLO").append(" ")
        val s = suGet(token, "/health", cache)
        r.append("su=").append(s?.take(20) ?: "FALLO")
        return r.toString().take(200)
    }

    // Devuelve Triple(respuesta, pendiente?, via). Intenta directo, luego su.
    fun llamar(token: String, nombre: String, argsJson: String, cache: File): Triple<String, String?, String> {
        val d = directoPost(token, nombre, argsJson)
        if (d != null) return Triple(d.first, d.second, "directo")
        val s = suPost(token, nombre, argsJson, cache)
        return Triple(s.first, s.second, "su")
    }

    private fun directoPost(token: String, nombre: String, argsJson: String): Pair<String, String?>? {
        return try {
            val body = "{\"nombre\":\"" + nombre + "\",\"args\":" + argsJson + "}"
            val c = URL(BASE + "/tools/call").openConnection() as HttpURLConnection
            c.requestMethod = "POST"
            c.setRequestProperty("Authorization", "Bearer $token")
            c.setRequestProperty("Content-Type", "application/json")
            c.doOutput = true
            c.connectTimeout = 1500
            c.readTimeout = 8000
            c.outputStream.bufferedWriter().use { it.write(body) }
            if (c.responseCode != 200) return null
            val txt = try {
                c.inputStream.bufferedReader().readText()
            } catch (_: Exception) {
                ""
            }
            val pend = if (txt.contains("\"estado\":\"pendiente\"")) nombre else null
            Pair(txt, pend)
        } catch (_: Exception) {
            null
        }
    }

    private fun suPost(token: String, nombre: String, argsJson: String, cache: File): Pair<String, String?> {
        return try {
            val body = "{\"nombre\":\"" + nombre + "\",\"args\":" + argsJson + "}"
            val f = File(cache, "nagent-body.json")
            f.writeText(body)
            val cmd = "curl -s -m 20 -X POST -H 'Authorization: Bearer " + token +
                "' -H 'Content-Type: application/json' --data-binary @" +
                f.absolutePath + " '" + BASE + "/tools/call'; rm -f '" + f.absolutePath + "'"
            val r = correr(arrayOf("su", "-c", cmd), 25)
            if (r.first != 0) {
                return Pair("FALLO su rc=" + r.first + " " + r.second.take(80), null)
            }
            val txt = r.second
            val pend = if (txt.contains("\"estado\":\"pendiente\"")) nombre else null
            Pair(txt, pend)
        } catch (e: Exception) {
            Pair("FALLO su EX " + e.message, null)
        }
    }
}
