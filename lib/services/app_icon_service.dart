import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppIconService {
  static const MethodChannel _channel = MethodChannel('app.icon');

  static Future<void> changeIcon(bool isDark) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    await _channel.invokeMethod<void>('changeIcon', isDark);
  }
}
