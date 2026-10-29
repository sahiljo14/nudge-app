// lib/services/voice_service.dart
//
// Flutter wrapper around the speech_to_text plugin (Android SpeechRecognizer).
//
// Public API
//   VoiceState enum
//   VoiceService.instance  — singleton
//   init()                 — optional; startListening() calls it automatically
//   startListening({onResult, onPartialResult, onStop})
//   stopListening()        — returns best-effort transcript captured so far
//
// BEHAVIOUR
//   • onPartialResult is called with every partial hypothesis (live text update).
//   • onResult is called once with the final committed transcript.
//   • onStop is called when listening ends with no usable text (silence / error).
//   • pauseFor: 5 s  — stops after 5 s of silence (allows longer dictated phrases).
//   • listenFor: 45 s — hard cap per session.
//   • localeId: 'en_IN' — Indian English, handles Hinglish code-switching.
//
// DOUBLE-DELIVERY GUARD
//   _state is set to VoiceState.ready and callbacks are cleared BEFORE
//   _speech.stop() is called.  All result/status/error callbacks check _state
//   first, so manual-stop never double-fires onResult.
//
// MID-SPEECH STOP FIX
//   Android's SpeechRecognizer fires 'done' status between internal recognition
//   bursts during dictation, not only at genuine end-of-speech.  The old code
//   committed text immediately on every 'done', cutting off mid-phrase.
//
//   Fix: _onStatus debounces the 'done'/'notListening' reaction:
//     • If no speech has been detected yet (_speechDetected == false) → stop
//       immediately (pure silence; avoids adding delay to no-speech case).
//     • If speech was detected → start a 400 ms timer.  If a new partial
//       result arrives within that window (plugin restarted the session), the
//       timer is cancelled and dictation continues.  If the timer fires with
//       no new partial, we commit whatever text was captured.

import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

enum VoiceState { idle, initializing, ready, listening, error }

class VoiceService {
  static final VoiceService instance = VoiceService._();
  VoiceService._();

  final _speech = stt.SpeechToText();

  VoiceState _state = VoiceState.idle;
  VoiceState get state => _state;

  void Function(String)? _onResult;
  void Function(String)? _onPartialResult;
  void Function()? _onStop;

  /// The latest recognized words (partial or committed).
  /// Returned by stopListening() when the user manually stops mid-phrase.
  String _currentText = '';

  /// True once the first non-empty partial result arrives in the current session.
  /// Used by _onStatus to distinguish mid-burst 'done' (debounce) from
  /// genuine silence 'done' (immediate stop).
  bool _speechDetected = false;

  /// Debounce timer: started on 'done'/'notListening' when speech was already
  /// detected.  Cancelled if a new partial arrives before it fires.
  Timer? _statusDebounce;

  // ── Init ──────────────────────────────────────────────────────────────────

  /// Initialize the speech recognizer.
  /// Returns null on success, a user-displayable error string on failure.
  /// Safe to call multiple times; skips if already ready or listening.
  Future<String?> init() async {
    if (_state == VoiceState.ready || _state == VoiceState.listening) return null;
    if (_state == VoiceState.initializing) return null;
    _state = VoiceState.initializing;
    try {
      final available = await _speech.initialize(
        onError: _onError,
        onStatus: _onStatus,
      );
      if (available) {
        _state = VoiceState.ready;
        return null;
      } else {
        _state = VoiceState.error;
        return 'Speech recognition not available on this device. '
            'Check microphone permission in Settings.';
      }
    } catch (e) {
      _state = VoiceState.error;
      return 'Failed to initialize speech recognition: $e';
    }
  }

  // ── Listening ─────────────────────────────────────────────────────────────

  /// Start listening.
  ///
  /// [onResult]        — called once with the final recognized phrase.
  /// [onPartialResult] — called on every partial hypothesis (for live UI).
  /// [onStop]          — called when listening ends with no usable text.
  ///
  /// Returns null on success or an error string if the engine could not start.
  Future<String?> startListening({
    required void Function(String text) onResult,
    void Function(String text)? onPartialResult,
    void Function()? onStop,
  }) async {
    if (_state == VoiceState.listening) {
      await stopListening();
    }

    if (_state != VoiceState.ready) {
      final err = await init();
      if (err != null) return err;
    }

    _onResult = onResult;
    _onPartialResult = onPartialResult;
    _onStop = onStop;
    _currentText = '';
    _speechDetected = false;
    _statusDebounce?.cancel();
    _statusDebounce = null;

    try {
      await _speech.listen(
        onResult: _handleResult,
        localeId: 'en_IN',
        listenFor: const Duration(seconds: 45),
        pauseFor: const Duration(seconds: 5),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
          cancelOnError: false,
        ),
      );
      _state = VoiceState.listening;
      return null;
    } catch (e) {
      _onResult = null;
      _onPartialResult = null;
      _onStop = null;
      _state = VoiceState.ready;
      return 'Could not start listening: $e';
    }
  }

  // ── Internal result / status / error handlers ─────────────────────────────

  void _handleResult(SpeechRecognitionResult result) {
    if (_state != VoiceState.listening) return;

    _currentText = result.recognizedWords;

    if (result.finalResult) {
      // Cancel any pending debounce — finalResult is the authoritative signal.
      _statusDebounce?.cancel();
      _statusDebounce = null;
      _commitOrStop();
    } else {
      // Partial result — user is still speaking.
      final partial = _currentText;
      if (partial.isNotEmpty) {
        // First detected speech: mark and cancel any pending 'done' debounce
        // so the plugin's internal session restart doesn't prematurely stop us.
        _speechDetected = true;
        _statusDebounce?.cancel();
        _statusDebounce = null;
        _onPartialResult?.call(partial);
      }
    }
  }

  void _onError(SpeechRecognitionError error) {
    if (_state != VoiceState.listening) return;
    _statusDebounce?.cancel();
    _statusDebounce = null;
    _commitOrStop();
  }

  void _onStatus(String status) {
    // 'done' / 'notListening' can mean either:
    //   (a) a genuine end-of-speech / silence timeout, or
    //   (b) the end of one internal recognition burst before the plugin
    //       restarts the session (common in dictation mode on Android).
    //
    // We distinguish them with _speechDetected:
    //   • No speech yet  → stop immediately (genuine silence).
    //   • Speech detected → debounce 400 ms.  If a new partial arrives
    //     (plugin restarted), the debounce is cancelled in _handleResult.
    //     If the timer fires, commit whatever text we have.
    if (_state != VoiceState.listening) return;
    if (status != 'done' && status != 'notListening') return;

    _statusDebounce?.cancel();
    _statusDebounce = null;

    if (!_speechDetected) {
      // Pure silence — no speech was detected at all.  Stop immediately.
      _commitOrStop();
    } else {
      // Speech was in progress.  Give the plugin 400 ms to fire a new partial
      // (session restart) before treating this as a genuine end-of-speech.
      _statusDebounce = Timer(const Duration(milliseconds: 400), () {
        _statusDebounce = null;
        if (_state != VoiceState.listening) return;
        _commitOrStop();
      });
    }
  }

  // ── Shared commit/stop logic ──────────────────────────────────────────────

  /// Commit captured text via onResult, or signal silence via onStop.
  /// Clears all session state before firing callbacks (double-delivery guard).
  void _commitOrStop() {
    final text = _currentText.trim();
    final cb = _onResult;
    final stopCb = _onStop;
    _onResult = null;
    _onPartialResult = null;
    _onStop = null;
    _currentText = '';
    _speechDetected = false;
    _state = VoiceState.ready;
    if (text.isNotEmpty) {
      cb?.call(text);
    } else {
      stopCb?.call();
    }
  }

  // ── Stop ──────────────────────────────────────────────────────────────────

  /// Stop any active listen session.
  /// Returns the best-effort transcript captured so far (for manual-stop UX),
  /// or null if nothing was captured.
  Future<String?> stopListening() async {
    _statusDebounce?.cancel();
    _statusDebounce = null;

    final savedText = _currentText.trim();
    _currentText = '';
    _speechDetected = false;

    if (_state != VoiceState.listening) {
      _onResult = null;
      _onPartialResult = null;
      _onStop = null;
      if (_state != VoiceState.ready) _state = VoiceState.idle;
      return null;
    }

    // Clear callbacks BEFORE stop() so that the status/result events fired
    // by stop() are silently ignored (double-delivery guard).
    _state = VoiceState.ready;
    _onResult = null;
    _onPartialResult = null;
    _onStop = null;

    try {
      await _speech.stop();
    } catch (_) {}

    return savedText.isNotEmpty ? savedText : null;
  }
}
