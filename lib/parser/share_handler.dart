import 'package:flutter/services.dart';

class ShareHandler {
  static const _channel = MethodChannel('nudge_app/share');

  static Future<String?> getSharedText() async {
    try {
      final text = await _channel.invokeMethod<String>('getSharedText');
      return text;
    } on PlatformException {
      return null;
    }
  }
}