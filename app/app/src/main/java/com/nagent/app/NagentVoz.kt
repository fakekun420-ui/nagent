package com.nagent.app

import android.os.Bundle
import android.service.voice.VoiceInteractionService
import android.service.voice.VoiceInteractionSession
import android.service.voice.VoiceInteractionSessionService

// NagentVoiceService: puerta del SO. Sin hotword (fuera de alcance v0.1.0).
class NagentVoiceService : VoiceInteractionService() {
    override fun onReady() {
        super.onReady()
    }
}

// NagentVoiceSessionService: crea sesiones que hablan con agentd.
class NagentVoiceSessionService : VoiceInteractionSessionService() {
    override fun onNewSession(args: Bundle?): VoiceInteractionSession {
        return NagentSession(this, args)
    }
}

class NagentSession(
    ctx: VoiceInteractionSessionService,
    args: Bundle?
) : VoiceInteractionSession(ctx) {
    // onHandleVoiceAction: SpeechRecognizer (VozLocal) -> POST /tools/call.
    // Si {"estado":"pendiente"} -> TTS pregunta + dialogo (Confirmar.kt).
}
