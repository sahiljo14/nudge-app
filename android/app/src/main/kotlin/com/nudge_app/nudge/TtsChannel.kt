// android/app/src/main/kotlin/com/nudge_app/nudge/TtsChannel.kt
//
// Wraps Android's built-in TextToSpeech engine.
// Fully offline — uses the device's on-board TTS synthesizer (no network call).
// Registered on MethodChannel "com.nudge.app/tts".
//
// Methods accepted from Flutter:
//   speak(text: String) — speaks the given text; interrupts any current speech
//   stop()              — silences any ongoing speech

package com.nudge_app.nudge

import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class TtsChannel(private val activity: FlutterActivity) : TextToSpeech.OnInitListener {

    companion object {
        const val METHOD_CHANNEL = "com.nudge.app/tts"
    }

    private var tts: TextToSpeech? = null
    private var isReady = false

    // Text queued before the engine has finished initialising
    private val pendingQueue = mutableListOf<String>()

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            tts?.language = Locale.US
            isReady = true
            pendingQueue.forEach { doSpeak(it) }
            pendingQueue.clear()
        }
        // If status == ERROR the engine isn't available; we just silently discard
        // any queued text — TTS is a "nice to have", not critical to save flow.
    }

    fun register(flutterEngine: FlutterEngine) {
        tts = TextToSpeech(activity, this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "speak" -> {
                        val text = call.argument<String>("text") ?: ""
                        if (text.isNotEmpty()) {
                            if (isReady) doSpeak(text) else pendingQueue.add(text)
                        }
                        result.success(null) // never fails — TTS is fire-and-forget
                    }
                    "stop" -> {
                        tts?.stop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun doSpeak(text: String) {
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "nudge_tts")
    }

    fun dispose() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        isReady = false
    }
}
