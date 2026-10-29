// lib/features/voice_gate.dart
//
// Centralized feature gate for voice input.
//
// PAYWALL TOGGLE
// --------------
// To lock voice behind a paywall, change _voiceEnabled to false and implement
// onDenied to show your subscription/paywall sheet. No other file needs
// to change — all voice entry points call VoiceGate.request().
//
// Example future lock:
//   static const bool _voiceEnabled = false;
//   // onDenied: show paywall bottom sheet, then call onGranted if user subscribes.

class VoiceGate {
  VoiceGate._();

  // Set to false and implement onDenied to activate the paywall.
  static const bool _voiceEnabled = true;

  /// Call before starting any voice interaction.
  ///
  /// [onGranted] — called immediately when access is allowed.
  /// [onDenied]  — called when access is blocked (e.g. paywall). Currently
  ///               a no-op; replace with your paywall presentation logic.
  static void request({
    required void Function() onGranted,
    void Function()? onDenied,
  }) {
    if (_voiceEnabled) {
      onGranted();
    } else {
      onDenied?.call();
    }
  }

  /// Convenience getter for UI that needs to show/hide the voice button.
  static bool get isEnabled => _voiceEnabled;
}
