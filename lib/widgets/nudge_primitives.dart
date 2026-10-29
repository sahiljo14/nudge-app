// lib/widgets/nudge_primitives.dart
// Reusable design primitives for the Nudge redesign.
// Purely visual — no data fetching or business logic.

import 'dart:math' show pi;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

// ── Ambient shadow card ────────────────────────────────────────────────────────

class NudgeCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final double radius;
  final bool ambientShadow;

  const NudgeCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.radius = 20,
    this.ambientShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: color ?? AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: ambientShadow && !isDark
            ? [
                BoxShadow(
                  color: const Color(0xFF4A40E0).withValues(alpha: 0.07),
                  blurRadius: 32,
                  spreadRadius: 0,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: padding != null
          ? Padding(padding: padding!, child: child)
          : child,
    );
  }
}

// ── Section header (overline + h1 title) ──────────────────────────────────────

class NudgeSectionHeader extends StatelessWidget {
  final String overline;
  final String title;

  const NudgeSectionHeader({
    super.key,
    required this.overline,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        overline.toUpperCase(),
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.07 * 11,
          color: AppTheme.subtext(isDark),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        title,
        style: GoogleFonts.manrope(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.03 * 28,
          color: AppTheme.text(isDark),
          height: 1.1,
        ),
      ),
    ]);
  }
}

// ── Gradient stat card ─────────────────────────────────────────────────────────

class NudgeStatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final List<Color> gradient;

  const NudgeStatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 22),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.manrope(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.08 * 10,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ]),
    );
  }
}

// ── Filter chip ────────────────────────────────────────────────────────────────

class NudgeFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const NudgeFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary
              : (isDark ? AppTheme.darkCard : AppTheme.lightSurfaceLow),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? AppTheme.onPrimary : AppTheme.subtext(isDark),
          ),
        ),
      ),
    );
  }
}

// ── Gradient progress bar ──────────────────────────────────────────────────────

class NudgeProgressBar extends StatelessWidget {
  /// 0.0 to 1.0
  final double value;
  final double height;
  final List<Color>? gradient;
  final Color? trackColor;

  const NudgeProgressBar({
    super.key,
    required this.value,
    this.height = 8,
    this.gradient,
    this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final track = trackColor ??
        (isDark ? const Color(0xFF2A2D3E) : const Color(0xFFE7E8FF));
    final grad = gradient ??
        [AppTheme.primary, AppTheme.primaryContainer, AppTheme.secondary];

    return LayoutBuilder(builder: (_, constraints) {
      final total = constraints.maxWidth;
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => Stack(children: [
          Container(
            height: height,
            width: total,
            decoration: BoxDecoration(
              color: track,
              borderRadius: BorderRadius.circular(height),
            ),
          ),
          Container(
            height: height,
            width: total * v,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: grad),
              borderRadius: BorderRadius.circular(height),
            ),
          ),
        ]),
      );
    });
  }
}

// ── Glass search bar ───────────────────────────────────────────────────────────

class NudgeSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const NudgeSearchBar({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFF4A40E0).withValues(alpha: 0.08),
        ),
      ),
      child: Row(children: [
        const SizedBox(width: 14),
        Icon(Icons.search_rounded,
            color: AppTheme.subtext(isDark), size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.text(isDark),
            ),
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: true,
              fillColor: Colors.transparent,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 14),
              isDense: true,
              hintStyle: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.subtext(isDark),
              ),
            ),
          ),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, v, __) => v.text.isNotEmpty
              ? GestureDetector(
                  onTap: onClear,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(Icons.close_rounded,
                        color: AppTheme.subtext(isDark), size: 18),
                  ),
                )
              : const SizedBox(width: 14),
        ),
      ]),
    );
  }
}

// ── Gradient ring progress ─────────────────────────────────────────────────────

class NudgeRingProgress extends StatelessWidget {
  /// 0.0 to 1.0
  final double value;
  final double size;
  final List<Color> gradient;
  final Color? trackColor;
  final double strokeWidth;
  final Widget? center;

  const NudgeRingProgress({
    super.key,
    required this.value,
    required this.gradient,
    this.size = 80,
    this.trackColor,
    this.strokeWidth = 10,
    this.center,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final track =
        trackColor ?? (isDark ? const Color(0xFF2A2D3E) : const Color(0xFFE2E7FF));

    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              progress: v,
              gradient: gradient,
              trackColor: track,
              strokeWidth: strokeWidth,
            ),
          ),
        ),
        if (center != null) center!,
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final List<Color> gradient;
  final Color trackColor;
  final double strokeWidth;

  const _RingPainter({
    required this.progress,
    required this.gradient,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    // Track (full circle)
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = trackColor
        ..strokeCap = StrokeCap.round,
    );

    if (progress <= 0) return;

    // Gradient fill arc
    canvas.drawArc(
      arcRect,
      -pi / 2,
      2 * pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: gradient,
          startAngle: -pi / 2,
          endAngle: -pi / 2 + 2 * pi,
        ).createShader(arcRect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.trackColor != trackColor ||
      old.gradient != gradient;
}

// ── Inline row label (overline style) ─────────────────────────────────────────

class NudgeLabel extends StatelessWidget {
  final String text;
  final Color? color;

  const NudgeLabel(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.07 * 11,
        color: color ?? AppTheme.subtext(isDark),
      ),
    );
  }
}
