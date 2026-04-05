package com.example.myapp

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.nudge.app/share"

    private var pendingText: String? = null
    private var pendingFileUri: String? = null
    private var pendingFileMime: String? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        extractIntent(intent)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSharedData" -> {
                        val data = mutableMapOf<String, String?>()
                        data["text"] = pendingText
                        data["fileUri"] = pendingFileUri
                        data["fileMime"] = pendingFileMime
                        result.success(data)
                        pendingText = null
                        pendingFileUri = null
                        pendingFileMime = null
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
                pendingText = intent.getStringExtra(Intent.EXTRA_TEXT)
            }
            mime == "application/pdf" ||
                    mime == "application/msword" ||
                    mime == "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ||
                    mime.startsWith("image/") ||
                    mime.startsWith("application/") -> {
                val uri: Uri? = intent.getParcelableExtra(Intent.EXTRA_STREAM)
                pendingFileUri = uri?.toString()
                pendingFileMime = mime
            }
        }
    }
}