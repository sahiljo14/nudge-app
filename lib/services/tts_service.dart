// lib/services/tts_service.dart
//
// Fire-and-forget wrapper around Android's built-in TextToSpeech engine.
//
// Rules:
//   • Never throws — all errors are swallowed; TTS is non-critical.
//   • Never awaited by callers — call speak() and proceed immediately.
//   • Never blocks save or navigation.
//
// The TTS engine initialises asynchronously on the native side (TtsChannel.kt).
// Any speak() call made before it's ready is queued in Kotlin and spoken once ready.

import 'package:flutter/services.dart';

class TtsService {
  static final TtsService instance = TtsService._();
  TtsService._();

  static const _channel = MethodChannel('com.nudge.app/tts');

  /// Speak [text] without blocking. Fails silently — never throws.
  void speak(String text) {
    if (text.isEmpty) return;
    _channel
        .invokeMethod<void>('speak', {'text': text})
        .catchError((_) {}); // swallow all platform errors
  }

  /// Stop any ongoing speech. Fails silently.
  void stop() {
    _channel.invokeMethod<void>('stop').catchError((_) {});
  }
}
