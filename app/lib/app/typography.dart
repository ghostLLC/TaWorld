/// TaWorld 字体配置
///
/// 使用内嵌的 Nunito 字体（圆润友好的西文字体），
/// 中文使用系统默认字体（Android: Noto Sans CJK / iOS: PingFang SC）。
/// 字体文件已离线内嵌，无需网络下载。
library;

import 'package:flutter/material.dart';

const _fontFamily = 'Nunito';

/// 创建 TaWorld 文字主题
///
/// 基于 Nunito 字体，所有字号和字重经过精心调整，
/// 确保温暖友好的视觉感受。
TextTheme createTextTheme({required Color bodyColor, required Color displayColor}) {
  return TextTheme(
    // ---- Display ----
    displayLarge: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 32,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      color: displayColor,
    ),
    displayMedium: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 28,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      color: displayColor,
    ),
    displaySmall: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: displayColor,
    ),

    // ---- Headline ----
    headlineLarge: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: displayColor,
    ),
    headlineMedium: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: displayColor,
    ),
    headlineSmall: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: displayColor,
    ),

    // ---- Title ----
    titleLarge: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: displayColor,
    ),
    titleMedium: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.15,
      color: displayColor,
    ),
    titleSmall: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: displayColor,
    ),

    // ---- Body ----
    bodyLarge: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.2,
      color: bodyColor,
    ),
    bodyMedium: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.15,
      color: bodyColor,
    ),
    bodySmall: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.1,
      color: bodyColor,
    ),

    // ---- Label ----
    labelLarge: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: bodyColor,
    ),
    labelMedium: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      color: bodyColor,
    ),
    labelSmall: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      color: bodyColor,
    ),
  );
}
