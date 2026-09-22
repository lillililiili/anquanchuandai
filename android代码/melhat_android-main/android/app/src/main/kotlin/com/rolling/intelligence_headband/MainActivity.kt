package com.rolling.intelligence_headband

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Notification
import android.os.Build
import android.content.pm.PackageManager
import android.content.Intent
import android.app.Activity
import android.provider.OpenableColumns

class MainActivity : FlutterActivity() {
    private var documentResult: MethodChannel.Result? = null
    private var documentBytes: ByteArray? = null
    override fun shouldHandleDeeplinking(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rolling/documents")
            .setMethodCallHandler { call, result ->
                if (documentResult != null) {
                    result.error("busy", "请先完成当前文件操作", null)
                } else if (call.method == "openXlsx" || call.method == "saveXlsx") {
                    val saving = call.method == "saveXlsx"
                    documentResult = result
                    documentBytes = if (saving) call.argument<ByteArray>("bytes") else null
                    val intent = Intent(if (saving) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT)
                        .addCategory(Intent.CATEGORY_OPENABLE)
                        .setType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
                    if (saving) intent.putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
                    try { startActivityForResult(intent, if (saving) 702 else 701) }
                    catch (e: Exception) {
                        documentResult = null; documentBytes = null
                        result.error("unavailable", "系统文件选择器不可用", null)
                    }
                } else result.notImplemented()
            }
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

    @Deprecated("Android activity result bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 701 && requestCode != 702) return
        val result = documentResult ?: return
        val bytes = documentBytes
        documentResult = null; documentBytes = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return }
        try {
            if (requestCode == 702) {
                require(bytes != null) { "文件内容为空" }
                val output = contentResolver.openOutputStream(uri) ?: error("无法写入文件")
                output.use { it.write(bytes) }
                result.success(true)
            } else {
                var name = "人员导入.xlsx"
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) name = it.getString(0)
                }
                val input = contentResolver.openInputStream(uri) ?: error("无法读取文件")
                val content = input.use { it.readBytesLimited() }
                result.success(mapOf("name" to name, "bytes" to content))
            }
        } catch (e: Exception) { result.error("document", e.message ?: "文件操作失败", null) }
    }

    private fun java.io.InputStream.readBytesLimited(): ByteArray {
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val count = read(buffer)
            if (count < 0) break
            require(output.size() + count <= 10 * 1024 * 1024) { "请选择不超过 10 MB 的文件" }
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }
}
