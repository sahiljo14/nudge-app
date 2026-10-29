// lib/widgets/subject_editor_sheet.dart
//
// Single source of truth for the "edit subject" bottom sheet that previously
// existed as four near-identical copies across:
//   - text_import_screen.dart
//   - doc_import_screen.dart
//   - ocr_scan_screen.dart
//   - add_task_screen.dart (twice)
//
// Pure UI helper — owns its own controller and pops with the trimmed result.

import 'package:flutter/material.dart';

/// Shows the subject editor sheet and returns the trimmed user input, or
/// `null` if the user dismissed the sheet without saving.
Future<String?> showSubjectEditor(
  BuildContext context, {
  String initial = '',
  String hintText = 'e.g. Operating Systems, Maths…',
  String title = 'Subject',
}) {
  final ctrl = TextEditingController(text: initial);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheetCtx) => Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(hintText: hintText),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () =>
                  Navigator.pop(sheetCtx, ctrl.text.trim()),
              child: const Text('Done'),
            ),
          ),
        ]),
      ),
    ),
  );
}
