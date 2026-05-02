import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFFF7F9F8);
  static const surface = Colors.white;
  static const primary = Color(0xFF08A7BD);
  static const primaryDark = Color(0xFF075F73);
  static const primarySoft = Color(0xFFE6F7FA);
  static const text = Color(0xFF1F2933);
  static const muted = Color(0xFF7B8794);
  static const faint = Color(0xFFA7B2BD);
  static const line = Color(0xFFE7ECEB);
  static const green = Color(0xFF2CA66F);
  static const greenSoft = Color(0xFFE9F8F0);
  static const yellow = Color(0xFFF2A93B);
  static const yellowSoft = Color(0xFFFFF5E4);
  static const red = Color(0xFFE35D5B);
  static const redSoft = Color(0xFFFFEEEE);
  static const lavender = Color(0xFF8A6FD1);
  static const lavenderSoft = Color(0xFFF1EDFF);
}

class AppShadows {
  static List<BoxShadow> get soft => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.045),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> get floating => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.075),
      blurRadius: 26,
      offset: const Offset(0, 12),
    ),
  ];
}

class AppTextStyles {
  static const hero = TextStyle(
    fontSize: 44,
    height: 1,
    fontWeight: FontWeight.w900,
    letterSpacing: 0,
    color: AppColors.primaryDark,
  );

  static const title = TextStyle(
    fontSize: 24,
    height: 1.15,
    fontWeight: FontWeight.w900,
    letterSpacing: 0,
    color: AppColors.text,
  );

  static const pageTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
    color: AppColors.text,
  );

  static const section = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
    color: AppColors.text,
  );

  static const body = TextStyle(
    fontSize: 14,
    height: 1.45,
    letterSpacing: 0,
    color: AppColors.text,
  );

  static const bodyMuted = TextStyle(
    fontSize: 15,
    height: 1.55,
    letterSpacing: 0,
    color: AppColors.muted,
  );

  static const listTitle = TextStyle(
    fontSize: 14,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: AppColors.text,
  );

  static const listSubtitle = TextStyle(
    fontSize: 12,
    height: 1.25,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: AppColors.muted,
  );

  static const listMeta = TextStyle(
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: AppColors.primaryDark,
  );

  static const chip = TextStyle(
    fontSize: 13,
    height: 1.1,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: AppColors.text,
  );

  static const caption = TextStyle(
    fontSize: 12,
    height: 1.35,
    letterSpacing: 0,
    color: AppColors.muted,
  );

  static const tiny = TextStyle(
    fontSize: 10,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    color: AppColors.faint,
  );
}

class AppButtonStyles {
  static ButtonStyle get primary => ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    disabledBackgroundColor: AppColors.faint.withValues(alpha: 0.35),
    disabledForegroundColor: Colors.white,
    elevation: 0,
    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );

  static ButtonStyle get outline => OutlinedButton.styleFrom(
    foregroundColor: AppColors.primaryDark,
    side: const BorderSide(color: AppColors.line),
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );

  static ButtonStyle get quiet => TextButton.styleFrom(
    foregroundColor: AppColors.primaryDark,
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}

class AppFormat {
  static String compactDateTime(Object? value) {
    final parsed = DateTime.tryParse('$value');
    final local = parsed?.toLocal();
    if (local == null) return '$value';
    return '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  static String timeOnly(Object? value) {
    final parsed = DateTime.tryParse('$value');
    final local = parsed?.toLocal();
    if (local == null) return '$value';
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
