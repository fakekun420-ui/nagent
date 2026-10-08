package com.nagent.app

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

// NagentNotificaciones: opt-in en Ajustes (apagado por defecto). Reenvia
// notificaciones como DATO <untrusted>, jamas como orden (C5).
class NagentNotificaciones : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val n = sbn ?: return
        if (!Prefs.optInNotificaciones(this)) return
        val extras = n.notification.extras
        val titulo = extras.getCharSequence("android.title")?.toString() ?: ""
        val texto = extras.getCharSequence("android.text")?.toString() ?: ""
        val dato = "<untrusted src=\"" + n.packageName + "\">" +
            titulo + " " + texto + "</untrusted>"
        ColaLocal.agregar(dato)
    }
}

object Prefs {
    fun optInNotificaciones(ctx: android.content.Context): Boolean {
        return ctx.getSharedPreferences("nagent", 0)
            .getBoolean("optin_notif", false)
    }
}

object ColaLocal {
    private val cola = ArrayDeque<String>()
    fun agregar(dato: String) {
        if (cola.size > 100) cola.removeFirst()
        cola.add(dato)
    }
}
