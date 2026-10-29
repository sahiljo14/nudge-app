// lib/services/ocr_service.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// On-device OCR wrapper using Google ML Kit.
///
/// Processes a local image file completely offline and returns
/// the recognised text as a single string.
class OCRService {
  OCRService._();

  /// Recognise text from a local image file at [path].
  ///
  /// [path] must be a local filesystem path (not a content:// URI).
  /// Returns the full extracted text, or an empty string if nothing
  /// was found or an error occurred.
  static Future<String> extractTextFromImage(String path) async {
    try {
      // Normalize: strip file:// prefix if present
      String normalizedPath = path;
      if (normalizedPath.startsWith('file://')) {
        normalizedPath = normalizedPath.replaceFirst('file://', '');
      }

      final file = File(normalizedPath);
      if (!await file.exists()) {
        debugPrint('[OCRService] File does not exist: $normalizedPath');
        return '';
      }

      debugPrint('[OCRService] Processing image: $normalizedPath');
      final inputImage = InputImage.fromFilePath(normalizedPath);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);

      try {
        final recognised = await recognizer.processImage(inputImage);
        debugPrint('[OCRService] Extracted ${recognised.text.length} characters');
        return recognised.text;
      } finally {
        await recognizer.close();
      }
    } catch (e) {
      debugPrint('[OCRService] Error: $e');
      return '';
    }
  }
}
