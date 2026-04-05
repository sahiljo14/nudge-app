import 'package:flutter/services.dart';

class ShareData {
  final String? text;
  final String? fileUri;
  final String? fileMime;

  const ShareData({this.text, this.fileUri, this.fileMime});

  bool get hasText => text != null && text!.trim().isNotEmpty;
  bool get hasFile => fileUri != null && fileUri!.isNotEmpty;
  bool get isPdf   => fileMime == 'application/pdf';
  bool get isImage => fileMime?.startsWith('image/') == true;
  bool get isDoc   =>
      fileMime == 'application/msword' ||
          fileMime == 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  bool get isEmpty => !hasText && !hasFile;
}

class ShareService {
  ShareService._();
  static const _ch = MethodChannel('com.nudge.app/share');

  static Future<ShareData> getSharedData() async {
    try {
      final raw = await _ch.invokeMethod<Map>('getSharedData');
      if (raw == null) return const ShareData();
      return ShareData(
        text:     raw['text'] as String?,
        fileUri:  raw['fileUri'] as String?,
        fileMime: raw['fileMime'] as String?,
      );
    } catch (_) {
      return const ShareData();
    }
  }
}
