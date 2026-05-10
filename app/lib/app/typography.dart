/// TaWorld 字体配置
///
/// 使用 Google Fonts 的 Nunito（圆润友好的西文字体），
/// 中文使用系统默认字体（Android: Noto Sans CJK / iOS: PingFang SC）。
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 创建 TaWorld 文字主题
///
/// 基于 Nunito 字体，所有字号和字重经过精心调整，
/// 确保温暖友好的视觉感受。
TextTheme createTextTheme({required Color bodyColor, required Color displayColor}) {
  return GoogleFonts.nunitoTextTheme(
    TextTheme(
      // ---- Display ----
      displayLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: displayColor,
      ),
      displayMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: displayColor,
      ),
      displaySmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: displayColor,
      ),

      // ---- Headline ----
      headlineLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: displayColor,
      ),
      headlineMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: displayColor,
      ),
      headlineSmall: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: displayColor,
      ),

      // ---- Title ----
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: displayColor,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
        color: displayColor,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: displayColor,
      ),

      // ---- Body ----
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
        color: bodyColor,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.15,
        color: bodyColor,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        color: bodyColor,
      ),

      // ---- Label ----
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: bodyColor,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: bodyColor,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: bodyColor,
      ),
    ),
  );
}
