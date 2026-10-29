// lib/services/share_service.dart

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class ShareData {
  final String? text;
  final String? fileUri;    // original URI (may be content://)
  final String? localPath;  // copied local path, ready to use
  final String? fileMime;

  const ShareData({
    this.text,
    this.fileUri,
    this.localPath,
    this.fileMime,
  });

  bool get hasText => text != null && text!.trim().isNotEmpty;
  bool get hasFile => (localPath ?? fileUri) != null;
  bool get isPdf   => fileMime == 'application/pdf';
  bool get isImage => fileMime?.startsWith('image/') == true;
  bool get isDoc   =>
      fileMime == 'application/msword' ||
          fileMime == 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  bool get isEmpty => !hasText && !hasFile;

  /// Returns the best available path to use (localPath preferred over raw URI)
  String? get usablePath => localPath ?? fileUri;
}

class ShareService {
  ShareService._();
  static const _ch = MethodChannel('com.nudge.app/share');

  static Future<ShareData> getSharedData() async {
    try {
      final raw = await _ch.invokeMethod<Map>('getSharedData');
      if (raw == null) return const ShareData();

      final text     = raw['text'] as String?;
      final fileUri  = raw['fileUri'] as String?;
      final fileMime = raw['fileMime'] as String?;

      // If we have a file URI, try to copy it to local storage
      String? localPath;
      if (fileUri != null && fileUri.isNotEmpty) {
        localPath = await _copyUriToLocal(fileUri, fileMime);
      }

      return ShareData(
        text:      text,
        fileUri:   fileUri,
        localPath: localPath,
        fileMime:  fileMime,
      );
    } catch (_) {
      return const ShareData();
    }
  }

  /// Copies a content:// or file:// URI to the app's cache directory.
  /// Returns the local file path on success, null on failure.
  static Future<String?> _copyUriToLocal(String uri, String? mime) async {
    try {
      // Use the platform channel to read the URI bytes
      final bytes = await _ch.invokeMethod<Uint8List>('readUriBytes', {'uri': uri});
      if (bytes == null || bytes.isEmpty) return null;

      final dir  = await getApplicationDocumentsDirectory();
      final docsDir = Directory(p.join(dir.path, 'nudge_docs'));
      await docsDir.create(recursive: true);

      final ext  = _extFromMime(mime ?? '');
      final name = 'shared_${DateTime.now().millisecondsSinceEpoch}$ext';
      final file = File(p.join(docsDir.path, name));
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (_) {
      // Fallback: return the URI as-is (works for file:// URIs)
      return uri.startsWith('file://') ? uri.replaceFirst('file://', '') : null;
    }
  }

  static String _extFromMime(String mime) {
    switch (mime) {
      case 'application/pdf':  return '.pdf';
      case 'image/jpeg':       return '.jpg';
      case 'image/png':        return '.png';
      case 'image/webp':       return '.webp';
      case 'application/msword': return '.doc';
      case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        return '.docx';
      default:                 return '';
    }
  }
}
