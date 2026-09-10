package com.rolling.intelligence_headband

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Notification
import android.os.Build
import android.content.pm.PackageManager

class MainActivity : FlutterActivity() {
    override fun shouldHandleDeeplinking(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("wear_events", "现场事件", NotificationManager.IMPORTANCE_HIGH)
            channel.description = "现场事件接警通知"
            channel.lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rolling/wear")
            .setMethodCallHandler { call, result ->
                val info = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
                when (call.method) {
                    "pushAppKey" -> result.success(info.metaData?.getString("JPUSH_APPKEY") ?: "")
                    "pushVendors" -> result.success(info.metaData?.getString("wear.push.vendors") ?: "")
                    else -> result.notImplemented()
                }
            }
    }
}
