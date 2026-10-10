package com.nagent.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier

// MainActivity v0.1.0 (Bloque E completo): estado de agentd, orden por texto,
// orden por voz (VozLocal on-device), dialogo de confirmacion para riesgo alto.
// Flujo: texto/voz -> Nivel0 (reglas) -> agentd /tools/call -> si pendiente,
// dialogo; confirmar NO re-ejecuta nada (el modelo no decide, R8).
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { PantallaEstado(this) }
    }
}

@Composable
fun PantallaEstado(act: MainActivity) {
    var salud by remember { mutableStateOf("sin comprobar") }
    var entrada by remember { mutableStateOf("") }
    var respuesta by remember { mutableStateOf("") }
    var pendiente by remember { mutableStateOf<String?>(null) }
    var voz by remember { mutableStateOf<VozLocal?>(null) }
    val scroll = rememberScrollState()

    fun ejecutar(texto: String) {
        val par = Nivel0.mapear(texto)
        if (par == null) {
            respuesta = "No entiendo: $texto"
            return
        }
        respuesta = "Ejecutando ${par.first}..."
        Thread {
            val token = AgentdClient.leerToken(act.filesDir)
            val r = if (token == null) {
                Pair("FALLO: sin token (root debe dejarlo en filesDir)", null)
            } else {
                AgentdClient.llamar(token, par.first, par.second)
            }
            act.runOnUiThread {
                respuesta = r.first.take(400)
                pendiente = r.second
            }
        }.start()
    }

    fun comprobar() {
        salud = "comprobando..."
        Thread {
            val token = AgentdClient.leerToken(act.filesDir)
            val r = if (token == null) {
                "token=NO"
            } else {
                "token=" + token.length + " " + AgentdClient.diagnostico(token)
            }
            act.runOnUiThread { salud = r.take(200) }
        }.start()
    }

    Column(Modifier.verticalScroll(scroll)) {
        Text("nagent: salud agentd, modelo, RAM, ultimas acciones")
        Text("Salud: $salud")
        Button(onClick = { comprobar() }) { Text("Comprobar agentd") }
        TextField(
            value = entrada,
            onValueChange = { entrada = it },
            label = { Text("Orden en texto") }
        )
        Button(onClick = { ejecutar(entrada) }) { Text("Enviar") }
        Button(onClick = {
            val v = voz ?: VozLocal(act).also { voz = it }
            v.escuchar(llamar = { ejecutar(it) }, onError = { respuesta = "Voz no disponible" })
        }) { Text("Hablar") }
        Text("Respuesta: $respuesta")
        if (pendiente != null) {
            Text("Confirmar riesgo alto: $pendiente")
            Button(onClick = {
                respuesta = "Requiere confirmacion humana en agentd (pendiente, no ejecutado)"
                pendiente = null
            }) { Text("Confirmar (solo registra)") }
            Button(onClick = { pendiente = null }) { Text("Rechazar") }
        }
    }
}
