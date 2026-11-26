package com.qanis.app.plugin

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.security.KeyStore
import java.security.MessageDigest
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate

/**
 * Tells the UI where the QANIS CA is trusted:
 *   "system" — present in the system store (installed through root / Magisk)
 *   "user"   — present in the user store only
 *   "none"   — not installed
 */
class CertStatusPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.qanis/cert"
        private const val CACHE_MS = 3000L
    }

    private lateinit var context: Context
    private var channel: MethodChannel? = null
    private var cached: String? = null
    private var cachedAt = 0L

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "caStatus" -> {
                val pem = call.argument<String>("pem")
                if (pem == null) {
                    result.error("bad_args", "pem is required", null)
                    return
                }
                try {
                    result.success(status(pem))
                } catch (e: Exception) {
                    result.error("status_error", e.message ?: e.javaClass.simpleName, null)
                }
            }
            "invalidate" -> {
                cached = null
                cachedAt = 0L
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun status(pem: String): String {
        val now = System.currentTimeMillis()
        if (cached != null && now - cachedAt < CACHE_MS) return cached!!

        var state = "none"
        try {
            val factory = CertificateFactory.getInstance("X.509")
            val ours = (factory.generateCertificate(ByteArrayInputStream(pem.toByteArray())) as X509Certificate).encoded
            val store = KeyStore.getInstance("AndroidCAStore")
            store.load(null, null)
            val aliases = store.aliases()
            while (aliases.hasMoreElements()) {
                val alias = aliases.nextElement()
                val cert = try {
                    store.getCertificate(alias)
                } catch (e: Exception) {
                    null
                } as? X509Certificate ?: continue
                if (!MessageDigest.isEqual(cert.encoded, ours)) continue
                if (alias.startsWith("system:")) {
                    state = "system"
                    break
                }
                state = "user"
            }
        } catch (e: Exception) {
            state = "none"
        }
        cached = state
        cachedAt = now
        return state
    }
}
