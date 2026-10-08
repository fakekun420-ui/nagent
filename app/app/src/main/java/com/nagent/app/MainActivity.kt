package com.nagent.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.*

// MainActivity v0.1.0 (esqueleto Bloque E): estado de agentd + dialogo de
// confirmacion para riesgo alto. Sin compilar aqui (sin toolchain; Actions lo hace).
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { PantallaEstado() }
    }
}

@Composable
fun PantallaEstado() {
    var pendiente by remember { mutableStateOf<String?>(null) }
    Column {
        Text("nagent: salud agentd, modelo, RAM, ultimas acciones")
        if (pendiente != null) {
            Text("Confirmar riesgo alto: $pendiente")
            Button(onClick = { confirmarEnAgentd(pendiente!!); pendiente = null }) {
                Text("Confirmar")
            }
            Button(onClick = { pendiente = null }) {
                Text("Rechazar")
            }
        }
    }
}

fun confirmarEnAgentd(pendingId: String) {
    // POST /confirm a agentd por loopback con token de sesion (R8: nunca tool del modelo).
}
