import 'package:flutter/material.dart';

class AppTypography {
  static const String _family = 'Inter';

  static TextStyle get headingLarge => const TextStyle(
        fontFamily: _family,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      );

  static TextStyle get headingMedium => const TextStyle(
        fontFamily: _family,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      );

  static TextStyle get bodyLarge => const TextStyle(
        fontFamily: _family,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.4,
      );

  static TextStyle get bodyMedium => const TextStyle(
        fontFamily: _family,
        fontSize: 15,
        fontWeight: FontWeight.w400,
      );

  static TextStyle get bodySmall => const TextStyle(
        fontFamily: _family,
        fontSize: 13,
        fontWeight: FontWeight.w400,
      );

  static TextStyle get caption => const TextStyle(
        fontFamily: _family,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
      );

  static TextStyle get label => const TextStyle(
        fontFamily: _family,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      );

  static TextStyle get overline => const TextStyle(
        fontFamily: _family,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      );

  static TextStyle get sidebarItem => const TextStyle(
        fontFamily: _family,
        fontSize: 14,
        fontWeight: FontWeight.w400,
      );

  static TextStyle get sidebarActive => const TextStyle(
        fontFamily: _family,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      );

  static TextStyle get sidebarCount => const TextStyle(
        fontFamily: _family,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      );
}
