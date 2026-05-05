// lib/widgets/photo_source_sheet.dart
// Shared bottom sheet for picking a profile-photo source (camera vs gallery).
// Used by both onboarding and the profile edit sheet.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';

class PhotoSourceSheet extends StatelessWidget {
  final bool isDark;
  const PhotoSourceSheet({super.key, required this.isDark});

  /// Shows the sheet and resolves to the user's chosen [ImageSource],
  /// or `null` if dismissed.
  static Future<ImageSource?> show(
    BuildContext context, {
    required bool isDark,
  }) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => PhotoSourceSheet(isDark: isDark),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
              color: AppTheme.border(isDark),
              borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 20),
        Text('Profile photo',
            style: GoogleFonts.manrope(
                fontSize: 16, fontWeight: FontWeight.w800,
                color: AppTheme.text(isDark))),
        const SizedBox(height: 20),
        _SourceTile(
          icon: Icons.camera_alt_rounded,
          label: 'Take Photo',
          isDark: isDark,
          onTap: () => Navigator.pop(context, ImageSource.camera),
        ),
        const SizedBox(height: 10),
        _SourceTile(
          icon: Icons.photo_library_rounded,
          label: 'Choose from Gallery',
          isDark: isDark,
          onTap: () => Navigator.pop(context, ImageSource.gallery),
        ),
      ]),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  const _SourceTile({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceLow(isDark),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Icon(icon, color: AppTheme.primary, size: 22),
            const SizedBox(width: 14),
            Text(label,
                style: GoogleFonts.manrope(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: AppTheme.text(isDark))),
          ]),
        ),
      );
}
