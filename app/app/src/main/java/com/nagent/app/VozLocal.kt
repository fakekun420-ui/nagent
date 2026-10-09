package com.nagent.app

import android.content.Context
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import java.util.Locale

// VozLocal: reconocimiento on-device si existe + TTS. Solo habla y escucha,
// nunca decide (R8: decide agentd, confirma la app).
class VozLocal(ctx: Context) {
    private val sr: SpeechRecognizer? =
        if (SpeechRecognizer.isOnDeviceRecognitionAvailable(ctx)) {
            SpeechRecognizer.createOnDeviceSpeechRecognizer(ctx)
        } else {
            null // fallback: sin on-device no hay voz local
        }
    private val tts = TextToSpeech(ctx) { /* onInit */ }.apply {
        language = Locale("es", "ES")
    }

    fun escuchar(llamar: (String) -> Unit, onError: () -> Unit) {
        val r = sr ?: run { onError(); return }
        r.setRecognitionListener(object : RecognitionListener {
            override fun onResults(res: Bundle?) {
                val texto = res?.getStringArrayList(RecognizerIntent.EXTRA_RESULTS)
                    ?.firstOrNull() ?: run { onError(); return }
                llamar(texto)
            }
            override fun onError(e: Int) = onError()
            override fun onReadyForSpeech(p: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(v: Float) {}
            override fun onBufferReceived(b: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onPartialResults(p: Bundle?) {}
            override fun onEvent(t: Int, p: Bundle?) {}
        })
    }

    fun hablar(texto: String) {
        tts.speak(texto, TextToSpeech.QUEUE_FLUSH, null, "nagent-1")
    }
}
