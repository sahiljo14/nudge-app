package com.nudgeapp.nudge

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Parcelable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.nudge.app/share"

    private var pendingText: String? = null
    private var pendingFileUri: String? = null
    private var pendingFileMime: String? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        extractIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "getSharedData" -> {
                        val data = mutableMapOf<String, String?>()
                        data["text"]     = pendingText
                        data["fileUri"]  = pendingFileUri
                        data["fileMime"] = pendingFileMime
                        result.success(data)
                        pendingText     = null
                        pendingFileUri  = null
                        pendingFileMime = null
                    }

                    // Read bytes from any content:// or file:// URI.
                    // Essential for WhatsApp / Gmail / Drive file shares.
                    "readUriBytes" -> {
                        val uriStr = call.argument<String>("uri")
                        if (uriStr == null) {
                            result.error("NO_URI", "No URI provided", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val uri = Uri.parse(uriStr)
                            val stream = contentResolver.openInputStream(uri)
                            if (stream == null) {
                                result.error("OPEN_FAILED", "Cannot open URI", null)
                                return@setMethodCallHandler
                            }
                            val bytes = stream.readBytes()
                            stream.close()
                            result.success(bytes)
                        } catch (e: Exception) {
                            result.error("READ_ERROR", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun extractIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        val mime = intent.type ?: return

        when {
            mime == "text/plain" -> {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (!text.isNullOrBlank()) pendingText = text
            }
            else -> {
                val uri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra<Parcelable>(Intent.EXTRA_STREAM) as? Uri
                }
                if (uri != null) {
                    try {
                        contentResolver.takePersistableUriPermission(
                            uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                        )
                    } catch (_: Exception) { /* not all providers support this */ }
                    pendingFileUri  = uri.toString()
                    pendingFileMime = mime
                }
            }
        }
    }
}
