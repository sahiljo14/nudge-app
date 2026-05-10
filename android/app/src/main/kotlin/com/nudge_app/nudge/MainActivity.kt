package com.nudge_app.nudge

import android.content.ComponentName
import android.content.Context
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
    private val ttsChannel by lazy { TtsChannel(this) }

    private var pendingText: String? = null
    private var pendingFileUri: String? = null
    private var pendingFileMime: String? = null

    private val lightAlias by lazy {
        ComponentName(packageName, "com.nudge_app.nudge.LauncherLight")
    }
    private val darkAlias by lazy {
        ComponentName(packageName, "com.nudge_app.nudge.LauncherDark")
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        extractIntent(intent)
        // Reconciles state if the process was killed before onStop ran.
        applyThemedLauncherIcon()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractIntent(intent)
    }

    override fun onStop() {
        applyThemedLauncherIcon()
        super.onStop()
    }

    // shared_preferences plugin stores under file "FlutterSharedPreferences"
    // and prefixes every key with "flutter.".
    private fun isAppThemeDark(): Boolean {
        val prefs = applicationContext.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE
        )
        return prefs.getString("flutter.theme_mode", null) == "dark"
    }

    private fun applyThemedLauncherIcon() {
        val pm = packageManager
        val dark = isAppThemeDark()
        val toEnable = if (dark) darkAlias else lightAlias
        val toDisable = if (dark) lightAlias else darkAlias

        val enabledState = pm.getComponentEnabledSetting(toEnable)
        val disabledState = pm.getComponentEnabledSetting(toDisable)
        val alreadyEnabled = enabledState == PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        val alreadyDisabled = disabledState == PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        if (alreadyEnabled && alreadyDisabled) return

        // Disable inactive first — if both aliases are ever enabled at once
        // the launcher caches two icons.
        pm.setComponentEnabledSetting(
            toDisable,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP
        )
        pm.setComponentEnabledSetting(
            toEnable,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ttsChannel.register(flutterEngine)

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
