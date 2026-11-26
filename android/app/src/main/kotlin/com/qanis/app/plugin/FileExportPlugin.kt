package com.qanis.app.plugin

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Writes exported files into /sdcard/Download/qanis.
 *
 * Android 10+ blocks direct writes to the public Downloads folder, so the bytes go
 * through MediaStore; older devices fall back to a plain file write.
 */
class FileExportPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.qanis/file"
        const val SUB_DIR = "qanis"
    }

    private lateinit var context: Context
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "saveToDownloads" -> {
                val name = call.argument<String>("name")
                val bytes = call.argument<ByteArray>("bytes")
                if (name == null || bytes == null) {
                    result.error("bad_args", "name and bytes are required", null)
                    return
                }
                try {
                    result.success(save(name, bytes))
                } catch (e: Exception) {
                    result.error("io_error", e.message ?: e.javaClass.simpleName, null)
                }
            }
            "downloadsPath" -> result.success("/sdcard/Download/$SUB_DIR")
            else -> result.notImplemented()
        }
    }

    private fun save(name: String, bytes: ByteArray): String {
        val display = "/sdcard/Download/$SUB_DIR/$name"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, "application/x-x509-ca-cert")
                put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/$SUB_DIR")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("MediaStore refused $display")
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("cannot open $display")
            val done = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
            resolver.update(uri, done, null, null)
            return display
        }
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), SUB_DIR)
        if (!dir.exists() && !dir.mkdirs()) throw IllegalStateException("cannot create ${dir.absolutePath}")
        FileOutputStream(File(dir, name)).use { it.write(bytes) }
        return display
    }
}
