/// TaWorld 设计令牌（Design Tokens）
///
/// 所有视觉常量的唯一来源。禁止在组件中硬编码颜色、间距、圆角等值。
library;

import 'package:flutter/material.dart';

// ============================================================
// 🎨 颜色系统
// ============================================================

/// 亮色模式色板
abstract final class TaLightColors {
  // ---- 主色 ----
  static const primary = Color(0xFFE8998D);       // 柔珊瑚
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFFFFE0DA);
  static const onPrimaryContainer = Color(0xFF5C2018);

  // ---- 次要色 ----
  static const secondary = Color(0xFFD4A855);      // 暖金
  static const onSecondary = Color(0xFFFFFFFF);
  static const secondaryContainer = Color(0xFFFFF0D4);
  static const onSecondaryContainer = Color(0xFF4A3500);

  // ---- 第三色（天气模块） ----
  static const tertiary = Color(0xFF7EB8CC);       // 天空蓝
  static const onTertiary = Color(0xFFFFFFFF);
  static const tertiaryContainer = Color(0xFFD6EFF7);
  static const onTertiaryContainer = Color(0xFF1A3A45);

  // ---- 背景/表面 ----
  static const background = Color(0xFFFFF8F5);     // 暖奶油白
  static const onBackground = Color(0xFF2C1810);
  static const surface = Color(0xFFFFFFFF);
  static const onSurface = Color(0xFF2C1810);
  static const surfaceVariant = Color(0xFFFFF0EB);  // 淡桃
  static const onSurfaceVariant = Color(0xFF6B5147);

  // ---- 功能色 ----
  static const error = Color(0xFFD32F2F);
  static const onError = Color(0xFFFFFFFF);
  static const outline = Color(0xFFE0C9C2);         // 暖边框
  static const outlineVariant = Color(0xFFF0DDD6);
  static const shadow = Color(0x1A5C4033);           // 暖色阴影

  // ---- 语义色 ----
  static const success = Color(0xFF66BB6A);
  static const warning = Color(0xFFFFB74D);
  static const info = Color(0xFF7EB8CC);
}

/// 暗色模式色板（温暖暗色，非冷灰）
abstract final class TaDarkColors {
  static const primary = Color(0xFFFFB4A2);         // 亮桃粉
  static const onPrimary = Color(0xFF3A1510);
  static const primaryContainer = Color(0xFF6B3028);
  static const onPrimaryContainer = Color(0xFFFFE0DA);

  static const secondary = Color(0xFFFFD699);
  static const onSecondary = Color(0xFF3A2800);
  static const secondaryContainer = Color(0xFF5C4200);
  static const onSecondaryContainer = Color(0xFFFFF0D4);

  static const tertiary = Color(0xFFA8D8EA);
  static const onTertiary = Color(0xFF1A3A45);
  static const tertiaryContainer = Color(0xFF2A5060);
  static const onTertiaryContainer = Color(0xFFD6EFF7);

  static const background = Color(0xFF1A1210);      // 温暖炭棕
  static const onBackground = Color(0xFFF5E6DF);
  static const surface = Color(0xFF2A2220);          // 暖深棕
  static const onSurface = Color(0xFFF5E6DF);
  static const surfaceVariant = Color(0xFF3A312E);   // 暖灰棕
  static const onSurfaceVariant = Color(0xFFD4B8AD);

  static const error = Color(0xFFEF9A9A);
  static const onError = Color(0xFF4A0000);
  static const outline = Color(0xFF5C4A42);
  static const outlineVariant = Color(0xFF3A312E);
  static const shadow = Color(0x40000000);

  static const success = Color(0xFF81C784);
  static const warning = Color(0xFFFFCC80);
  static const info = Color(0xFFA8D8EA);
}

// ============================================================
// 📐 间距系统（8px 基线网格）
// ============================================================

abstract final class TaSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;

  // 页面边距
  static const double pagePadding = 20;

  // 卡片间距
  static const double cardGap = 16;

  // 常用 EdgeInsets
  static const page = EdgeInsets.symmetric(horizontal: pagePadding);
  static const cardInner = EdgeInsets.all(md);
  static const cardInnerLarge = EdgeInsets.all(lg);
  static const listItem = EdgeInsets.symmetric(horizontal: pagePadding, vertical: xs);
}

// ============================================================
// 🔘 圆角系统
// ============================================================

abstract final class TaRadius {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double full = 999;

  // 常用 BorderRadius
  static final borderXs = BorderRadius.circular(xs);
  static final borderSm = BorderRadius.circular(sm);
  static final borderMd = BorderRadius.circular(md);
  static final borderLg = BorderRadius.circular(lg);
  static final borderXl = BorderRadius.circular(xl);
  static final borderFull = BorderRadius.circular(full);
}

// ============================================================
// 🌊 阴影系统（暖色调阴影）
// ============================================================

abstract final class TaShadows {
  static const sm = [
    BoxShadow(
      color: TaLightColors.shadow,
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static const md = [
    BoxShadow(
      color: TaLightColors.shadow,
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];

  static const lg = [
    BoxShadow(
      color: TaLightColors.shadow,
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];
}

// ============================================================
// ⏱️ 动画系统
// ============================================================

abstract final class TaAnimation {
  static const fast = Duration(milliseconds: 200);
  static const normal = Duration(milliseconds: 300);
  static const slow = Duration(milliseconds: 500);
  static const pageTransition = Duration(milliseconds: 350);

  // 标准缓动曲线
  static const curve = Curves.easeInOutCubic;
  static const curveIn = Curves.easeInCubic;
  static const curveOut = Curves.easeOutCubic;
  static const bounce = Curves.elasticOut;
}

// ============================================================
// 📏 尺寸常量
// ============================================================

abstract final class TaSizes {
  // 头像尺寸
  static const double avatarSm = 32;
  static const double avatarMd = 48;
  static const double avatarLg = 64;
  static const double avatarXl = 96;

  // 按钮高度
  static const double buttonHeight = 52;
  static const double buttonHeightSm = 40;

  // 输入框高度
  static const double inputHeight = 52;

  // 底部导航高度
  static const double bottomNavHeight = 72;

  // 图标大小
  static const double iconSm = 20;
  static const double iconMd = 24;
  static const double iconLg = 32;

  // AppBar
  static const double appBarHeight = 64;
}

// ============================================================
// 🌈 渐变系统
// ============================================================

abstract final class TaGradients {
  /// 主渐变（AppBar、主按钮）
  static const primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE8998D), Color(0xFFD4886E)],
  );

  /// 温暖渐变（卡片背景装饰）
  static const warm = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFE0DA), Color(0xFFFFF0D4)],
  );

  /// 成就金色渐变
  static const gold = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFD699), Color(0xFFE8B84D)],
  );

  /// 天气蓝色渐变
  static const sky = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFA8D8EA), Color(0xFF7EB8CC)],
  );
}
