package com.nudgeapp.nudge

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Parcelable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val SHARE_CHANNEL = "com.nudge.app/share"
    private val ICON_CHANNEL = "app.icon"
    private val ttsChannel by lazy { TtsChannel(this) }

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
        ttsChannel.register(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ICON_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "changeIcon" -> {
                        val isDark = readIsDarkArgument(call.arguments)
                        if (isDark == null) {
                            result.error(
                                "BAD_ARGS",
                                "changeIcon expects a Boolean isDark argument",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        try {
                            changeIcon(isDark)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error(
                                "ICON_CHANGE_FAILED",
                                e.message ?: "Unable to change launcher icon",
                                null
                            )
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
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

    private fun readIsDarkArgument(arguments: Any?): Boolean? =
        when (arguments) {
            is Boolean -> arguments
            is Map<*, *> -> arguments["isDark"] as? Boolean
            else -> null
        }

    private fun changeIcon(isDark: Boolean) {
        val lightAlias = aliasComponent("MainActivityLight")
        val darkAlias = aliasComponent("MainActivityDark")
        val activeAlias = if (isDark) darkAlias else lightAlias
        val inactiveAlias = if (isDark) lightAlias else darkAlias

        setAliasEnabled(inactiveAlias, false)
        setAliasEnabled(activeAlias, true)
    }

    private fun aliasComponent(aliasName: String): ComponentName =
        ComponentName(this, "$packageName.$aliasName")

    private fun setAliasEnabled(componentName: ComponentName, enabled: Boolean) {
        val desiredState = if (enabled) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }

        if (packageManager.getComponentEnabledSetting(componentName) == desiredState) {
            return
        }

        packageManager.setComponentEnabledSetting(
            componentName,
            desiredState,
            PackageManager.DONT_KILL_APP
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        ttsChannel.dispose()
        super.onDestroy()
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
