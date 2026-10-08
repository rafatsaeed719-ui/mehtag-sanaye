package com.mehtagsanaye.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    /** قنوات الإشعارات: عادية + عاجلة (طلبات الطوارئ) */
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val isAr = resources.configuration.locales.get(0).language == "ar"

        val normal = NotificationChannel(
            "default",
            if (isAr) "الطلبات والرسائل" else "Requests & messages",
            NotificationManager.IMPORTANCE_HIGH
        )
        manager.createNotificationChannel(normal)

        val urgent = NotificationChannel(
            "urgent",
            if (isAr) "طلبات الطوارئ" else "Emergency requests",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 400, 200, 400, 200, 400)
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build()
            )
        }
        manager.createNotificationChannel(urgent)
    }
}
