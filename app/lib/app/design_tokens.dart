/// TaWorld 设计令牌（Design Tokens）
///
/// 所有视觉常量的唯一来源。禁止在组件中硬编码颜色、间距、圆角等值。
/// 支持多套调色板切换。
library;

import 'package:flutter/material.dart';

// ============================================================
// 🎨 调色板系统
// ============================================================

/// 单套配色（亮色或暗色）的所有颜色定义
class TaColorSet {
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;
  final Color background;
  final Color onBackground;
  final Color surface;
  final Color onSurface;
  final Color surfaceVariant;
  final Color onSurfaceVariant;
  final Color error;
  final Color onError;
  final Color outline;
  final Color outlineVariant;
  final Color shadow;
  final Color success;
  final Color warning;
  final Color info;

  const TaColorSet({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.background,
    required this.onBackground,
    required this.surface,
    required this.onSurface,
    required this.surfaceVariant,
    required this.onSurfaceVariant,
    required this.error,
    required this.onError,
    required this.outline,
    required this.outlineVariant,
    required this.shadow,
    required this.success,
    required this.warning,
    required this.info,
  });
}

/// 一套完整的调色板（亮色 + 暗色）
class TaColorPalette {
  final String id;
  final String label;
  final Color preview;
  final TaColorSet light;
  final TaColorSet dark;

  const TaColorPalette({
    required this.id,
    required this.label,
    required this.preview,
    required this.light,
    required this.dark,
  });
}

// ============================================================
// 调色板定义
// ============================================================

/// 所有可用调色板
const List<TaColorPalette> kTaPalettes = [
  _paletteCoral,
  _paletteLavender,
  _paletteOcean,
  _paletteSakura,
  _paletteForest,
];

/// 1. 暖珊瑚（默认）— 珊瑚粉 + 暖金
const _paletteCoral = TaColorPalette(
  id: 'coral',
  label: '暖珊瑚',
  preview: Color(0xFFE8998D),
  light: TaColorSet(
    primary: Color(0xFFE8998D),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFFE0DA),
    onPrimaryContainer: Color(0xFF5C2018),
    secondary: Color(0xFFD4A855),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFFFF0D4),
    onSecondaryContainer: Color(0xFF4A3500),
    tertiary: Color(0xFF7EB8CC),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFD6EFF7),
    onTertiaryContainer: Color(0xFF1A3A45),
    background: Color(0xFFFFF8F5),
    onBackground: Color(0xFF2C1810),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF2C1810),
    surfaceVariant: Color(0xFFFFF0EB),
    onSurfaceVariant: Color(0xFF6B5147),
    error: Color(0xFFD32F2F),
    onError: Color(0xFFFFFFFF),
    outline: Color(0xFFE0C9C2),
    outlineVariant: Color(0xFFF0DDD6),
    shadow: Color(0x1A5C4033),
    success: Color(0xFF66BB6A),
    warning: Color(0xFFFFB74D),
    info: Color(0xFF7EB8CC),
  ),
  dark: TaColorSet(
    primary: Color(0xFFFFB4A2),
    onPrimary: Color(0xFF3A1510),
    primaryContainer: Color(0xFF6B3028),
    onPrimaryContainer: Color(0xFFFFE0DA),
    secondary: Color(0xFFFFD699),
    onSecondary: Color(0xFF3A2800),
    secondaryContainer: Color(0xFF5C4200),
    onSecondaryContainer: Color(0xFFFFF0D4),
    tertiary: Color(0xFFA8D8EA),
    onTertiary: Color(0xFF1A3A45),
    tertiaryContainer: Color(0xFF2A5060),
    onTertiaryContainer: Color(0xFFD6EFF7),
    background: Color(0xFF1A1210),
    onBackground: Color(0xFFF5E6DF),
    surface: Color(0xFF2A2220),
    onSurface: Color(0xFFF5E6DF),
    surfaceVariant: Color(0xFF3A312E),
    onSurfaceVariant: Color(0xFFD4B8AD),
    error: Color(0xFFEF9A9A),
    onError: Color(0xFF4A0000),
    outline: Color(0xFF5C4A42),
    outlineVariant: Color(0xFF3A312E),
    shadow: Color(0x40000000),
    success: Color(0xFF81C784),
    warning: Color(0xFFFFCC80),
    info: Color(0xFFA8D8EA),
  ),
);

/// 2. 薰衣草 — 紫色 + 薄荷
const _paletteLavender = TaColorPalette(
  id: 'lavender',
  label: '薰衣草',
  preview: Color(0xFF9B8EC4),
  light: TaColorSet(
    primary: Color(0xFF9B8EC4),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFEDE7F6),
    onPrimaryContainer: Color(0xFF2D1B69),
    secondary: Color(0xFF66BB9A),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFD5F0E5),
    onSecondaryContainer: Color(0xFF003D2B),
    tertiary: Color(0xFF80B4CC),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFD8ECF5),
    onTertiaryContainer: Color(0xFF1A3A4A),
    background: Color(0xFFF8F5FC),
    onBackground: Color(0xFF1C1628),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF1C1628),
    surfaceVariant: Color(0xFFF3EDF9),
    onSurfaceVariant: Color(0xFF5E5170),
    error: Color(0xFFD32F2F),
    onError: Color(0xFFFFFFFF),
    outline: Color(0xFFD0C5DE),
    outlineVariant: Color(0xFFE8E0F0),
    shadow: Color(0x1A3C2866),
    success: Color(0xFF66BB6A),
    warning: Color(0xFFFFB74D),
    info: Color(0xFF80B4CC),
  ),
  dark: TaColorSet(
    primary: Color(0xFFBDA8E8),
    onPrimary: Color(0xFF2D1B69),
    primaryContainer: Color(0xFF4A3580),
    onPrimaryContainer: Color(0xFFEDE7F6),
    secondary: Color(0xFF8DD8B8),
    onSecondary: Color(0xFF003D2B),
    secondaryContainer: Color(0xFF2A6B50),
    onSecondaryContainer: Color(0xFFD5F0E5),
    tertiary: Color(0xFFA8D4E8),
    onTertiary: Color(0xFF1A3A4A),
    tertiaryContainer: Color(0xFF2A5A70),
    onTertiaryContainer: Color(0xFFD8ECF5),
    background: Color(0xFF151020),
    onBackground: Color(0xFFE8E0F5),
    surface: Color(0xFF221A30),
    onSurface: Color(0xFFE8E0F5),
    surfaceVariant: Color(0xFF302845),
    onSurfaceVariant: Color(0xFFC8BAD8),
    error: Color(0xFFEF9A9A),
    onError: Color(0xFF4A0000),
    outline: Color(0xFF504068),
    outlineVariant: Color(0xFF302845),
    shadow: Color(0x40000000),
    success: Color(0xFF81C784),
    warning: Color(0xFFFFCC80),
    info: Color(0xFFA8D4E8),
  ),
);

/// 3. 海洋蓝 — 深蓝 + 暖沙
const _paletteOcean = TaColorPalette(
  id: 'ocean',
  label: '海洋蓝',
  preview: Color(0xFF5B98C4),
  light: TaColorSet(
    primary: Color(0xFF5B98C4),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD6EAF5),
    onPrimaryContainer: Color(0xFF0A3050),
    secondary: Color(0xFFD4A574),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFFFF0E0),
    onSecondaryContainer: Color(0xFF4A3010),
    tertiary: Color(0xFF7EC4A8),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFD6F0E5),
    onTertiaryContainer: Color(0xFF1A4535),
    background: Color(0xFFF5F8FC),
    onBackground: Color(0xFF101C28),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF101C28),
    surfaceVariant: Color(0xFFEBF2F8),
    onSurfaceVariant: Color(0xFF4A5A6B),
    error: Color(0xFFD32F2F),
    onError: Color(0xFFFFFFFF),
    outline: Color(0xFFC2D0DE),
    outlineVariant: Color(0xFFD8E4F0),
    shadow: Color(0x1A283C5C),
    success: Color(0xFF66BB6A),
    warning: Color(0xFFFFB74D),
    info: Color(0xFF5B98C4),
  ),
  dark: TaColorSet(
    primary: Color(0xFF88C0E8),
    onPrimary: Color(0xFF0A3050),
    primaryContainer: Color(0xFF2A5A80),
    onPrimaryContainer: Color(0xFFD6EAF5),
    secondary: Color(0xFFE8C8A0),
    onSecondary: Color(0xFF4A3010),
    secondaryContainer: Color(0xFF6B4A20),
    onSecondaryContainer: Color(0xFFFFF0E0),
    tertiary: Color(0xFFA0D8C0),
    onTertiary: Color(0xFF1A4535),
    tertiaryContainer: Color(0xFF2A6A50),
    onTertiaryContainer: Color(0xFFD6F0E5),
    background: Color(0xFF0C1420),
    onBackground: Color(0xFFDCE8F5),
    surface: Color(0xFF182230),
    onSurface: Color(0xFFDCE8F5),
    surfaceVariant: Color(0xFF253545),
    onSurfaceVariant: Color(0xFFB0C0D0),
    error: Color(0xFFEF9A9A),
    onError: Color(0xFF4A0000),
    outline: Color(0xFF3A5068),
    outlineVariant: Color(0xFF253545),
    shadow: Color(0x40000000),
    success: Color(0xFF81C784),
    warning: Color(0xFFFFCC80),
    info: Color(0xFF88C0E8),
  ),
);

/// 4. 樱花粉 — 粉色 + 梅紫
const _paletteSakura = TaColorPalette(
  id: 'sakura',
  label: '樱花粉',
  preview: Color(0xFFE88DAA),
  light: TaColorSet(
    primary: Color(0xFFE88DAA),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFFE0EA),
    onPrimaryContainer: Color(0xFF5C1830),
    secondary: Color(0xFF9B7EC4),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFF0E4F9),
    onSecondaryContainer: Color(0xFF2D1B69),
    tertiary: Color(0xFF7EB8A8),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFD6F0E8),
    onTertiaryContainer: Color(0xFF1A4538),
    background: Color(0xFFFFF5F8),
    onBackground: Color(0xFF281018),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF281018),
    surfaceVariant: Color(0xFFFFE8F0),
    onSurfaceVariant: Color(0xFF6B4755),
    error: Color(0xFFD32F2F),
    onError: Color(0xFFFFFFFF),
    outline: Color(0xFFE0C2D0),
    outlineVariant: Color(0xFFF0D6E2),
    shadow: Color(0x1A5C3344),
    success: Color(0xFF66BB6A),
    warning: Color(0xFFFFB74D),
    info: Color(0xFF7EB8A8),
  ),
  dark: TaColorSet(
    primary: Color(0xFFFFB4CC),
    onPrimary: Color(0xFF5C1830),
    primaryContainer: Color(0xFF8B3050),
    onPrimaryContainer: Color(0xFFFFE0EA),
    secondary: Color(0xFFBDA8E8),
    onSecondary: Color(0xFF2D1B69),
    secondaryContainer: Color(0xFF4A3580),
    onSecondaryContainer: Color(0xFFF0E4F9),
    tertiary: Color(0xFFA0D8C8),
    onTertiary: Color(0xFF1A4538),
    tertiaryContainer: Color(0xFF2A6A58),
    onTertiaryContainer: Color(0xFFD6F0E8),
    background: Color(0xFF1A1018),
    onBackground: Color(0xFFF5E0E8),
    surface: Color(0xFF2A2028),
    onSurface: Color(0xFFF5E0E8),
    surfaceVariant: Color(0xFF3A2E38),
    onSurfaceVariant: Color(0xFFD4B0C0),
    error: Color(0xFFEF9A9A),
    onError: Color(0xFF4A0000),
    outline: Color(0xFF5C4250),
    outlineVariant: Color(0xFF3A2E38),
    shadow: Color(0x40000000),
    success: Color(0xFF81C784),
    warning: Color(0xFFFFCC80),
    info: Color(0xFFA0D8C8),
  ),
);

/// 5. 森林绿 — 鼠尾草绿 + 暖棕
const _paletteForest = TaColorPalette(
  id: 'forest',
  label: '森林绿',
  preview: Color(0xFF7EAA88),
  light: TaColorSet(
    primary: Color(0xFF7EAA88),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD6F0DE),
    onPrimaryContainer: Color(0xFF1A4528),
    secondary: Color(0xFFC49B6E),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFF5E8D6),
    onSecondaryContainer: Color(0xFF4A3518),
    tertiary: Color(0xFF88A8C4),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFD8E8F5),
    onTertiaryContainer: Color(0xFF1A3550),
    background: Color(0xFFF5F9F5),
    onBackground: Color(0xFF101C14),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF101C14),
    surfaceVariant: Color(0xFFE8F2E8),
    onSurfaceVariant: Color(0xFF4A5C4A),
    error: Color(0xFFD32F2F),
    onError: Color(0xFFFFFFFF),
    outline: Color(0xFFC2D8C2),
    outlineVariant: Color(0xFFD8E8D8),
    shadow: Color(0x1A285C33),
    success: Color(0xFF66BB6A),
    warning: Color(0xFFFFB74D),
    info: Color(0xFF88A8C4),
  ),
  dark: TaColorSet(
    primary: Color(0xFFA0D0A8),
    onPrimary: Color(0xFF1A4528),
    primaryContainer: Color(0xFF2A6A3A),
    onPrimaryContainer: Color(0xFFD6F0DE),
    secondary: Color(0xFFE0C090),
    onSecondary: Color(0xFF4A3518),
    secondaryContainer: Color(0xFF6B4A20),
    onSecondaryContainer: Color(0xFFF5E8D6),
    tertiary: Color(0xFFA8C8E0),
    onTertiary: Color(0xFF1A3550),
    tertiaryContainer: Color(0xFF2A5A78),
    onTertiaryContainer: Color(0xFFD8E8F5),
    background: Color(0xFF0C160E),
    onBackground: Color(0xFFDCE8DC),
    surface: Color(0xFF182218),
    onSurface: Color(0xFFDCE8DC),
    surfaceVariant: Color(0xFF283828),
    onSurfaceVariant: Color(0xFFB0C8B0),
    error: Color(0xFFEF9A9A),
    onError: Color(0xFF4A0000),
    outline: Color(0xFF3A583A),
    outlineVariant: Color(0xFF283828),
    shadow: Color(0x40000000),
    success: Color(0xFF81C784),
    warning: Color(0xFFFFCC80),
    info: Color(0xFFA8C8E0),
  ),
);

// ============================================================
// 活动调色板（运行时切换）
// ============================================================

/// 当前活动的调色板 ID（由 ThemeService 管理）
String _activePaletteId = 'coral';

/// 获取当前活动调色板
TaColorPalette get activePalette =>
    kTaPalettes.firstWhere((p) => p.id == _activePaletteId,
        orElse: () => kTaPalettes.first);

/// 设置活动调色板（内部调用，由 ThemeService 管理）
void setActivePalette(String id) {
  if (kTaPalettes.any((p) => p.id == id)) {
    _activePaletteId = id;
  }
}

// ============================================================
// 🎨 动态颜色访问（保持向后兼容）
// ============================================================

/// 亮色模式色板（动态读取当前调色板）
abstract final class TaLightColors {
  static TaColorSet get _c => activePalette.light;

  static Color get primary => _c.primary;
  static Color get onPrimary => _c.onPrimary;
  static Color get primaryContainer => _c.primaryContainer;
  static Color get onPrimaryContainer => _c.onPrimaryContainer;
  static Color get secondary => _c.secondary;
  static Color get onSecondary => _c.onSecondary;
  static Color get secondaryContainer => _c.secondaryContainer;
  static Color get onSecondaryContainer => _c.onSecondaryContainer;
  static Color get tertiary => _c.tertiary;
  static Color get onTertiary => _c.onTertiary;
  static Color get tertiaryContainer => _c.tertiaryContainer;
  static Color get onTertiaryContainer => _c.onTertiaryContainer;
  static Color get background => _c.background;
  static Color get onBackground => _c.onBackground;
  static Color get surface => _c.surface;
  static Color get onSurface => _c.onSurface;
  static Color get surfaceVariant => _c.surfaceVariant;
  static Color get onSurfaceVariant => _c.onSurfaceVariant;
  static Color get error => _c.error;
  static Color get onError => _c.onError;
  static Color get outline => _c.outline;
  static Color get outlineVariant => _c.outlineVariant;
  static Color get shadow => _c.shadow;
  static Color get success => _c.success;
  static Color get warning => _c.warning;
  static Color get info => _c.info;
}

/// 暗色模式色板（动态读取当前调色板）
abstract final class TaDarkColors {
  static TaColorSet get _c => activePalette.dark;

  static Color get primary => _c.primary;
  static Color get onPrimary => _c.onPrimary;
  static Color get primaryContainer => _c.primaryContainer;
  static Color get onPrimaryContainer => _c.onPrimaryContainer;
  static Color get secondary => _c.secondary;
  static Color get onSecondary => _c.onSecondary;
  static Color get secondaryContainer => _c.secondaryContainer;
  static Color get onSecondaryContainer => _c.onSecondaryContainer;
  static Color get tertiary => _c.tertiary;
  static Color get onTertiary => _c.onTertiary;
  static Color get tertiaryContainer => _c.tertiaryContainer;
  static Color get onTertiaryContainer => _c.onTertiaryContainer;
  static Color get background => _c.background;
  static Color get onBackground => _c.onBackground;
  static Color get surface => _c.surface;
  static Color get onSurface => _c.onSurface;
  static Color get surfaceVariant => _c.surfaceVariant;
  static Color get onSurfaceVariant => _c.onSurfaceVariant;
  static Color get error => _c.error;
  static Color get onError => _c.onError;
  static Color get outline => _c.outline;
  static Color get outlineVariant => _c.outlineVariant;
  static Color get shadow => _c.shadow;
  static Color get success => _c.success;
  static Color get warning => _c.warning;
  static Color get info => _c.info;
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

  static const double pagePadding = 20;
  static const double cardGap = 16;

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

  static final borderXs = BorderRadius.circular(xs);
  static final borderSm = BorderRadius.circular(sm);
  static final borderMd = BorderRadius.circular(md);
  static final borderLg = BorderRadius.circular(lg);
  static final borderXl = BorderRadius.circular(xl);
  static final borderFull = BorderRadius.circular(full);
}

// ============================================================
// 🌊 阴影系统（动态跟随调色板）
// ============================================================

abstract final class TaShadows {
  static List<BoxShadow> get sm => [
        BoxShadow(color: TaLightColors.shadow, blurRadius: 8, offset: const Offset(0, 2)),
      ];
  static List<BoxShadow> get md => [
        BoxShadow(color: TaLightColors.shadow, blurRadius: 16, offset: const Offset(0, 4)),
      ];
  static List<BoxShadow> get lg => [
        BoxShadow(color: TaLightColors.shadow, blurRadius: 24, offset: const Offset(0, 8)),
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

  static const curve = Curves.easeInOutCubic;
  static const curveIn = Curves.easeInCubic;
  static const curveOut = Curves.easeOutCubic;
  static const bounce = Curves.elasticOut;
}

// ============================================================
// 📏 尺寸常量
// ============================================================

abstract final class TaSizes {
  static const double avatarSm = 32;
  static const double avatarMd = 48;
  static const double avatarLg = 64;
  static const double avatarXl = 96;

  static const double buttonHeight = 52;
  static const double buttonHeightSm = 40;
  static const double inputHeight = 52;
  static const double bottomNavHeight = 72;

  static const double iconSm = 20;
  static const double iconMd = 24;
  static const double iconLg = 32;
  static const double appBarHeight = 64;
}

// ============================================================
// 🌈 渐变系统（动态跟随调色板）
// ============================================================

abstract final class TaGradients {
  /// 主渐变（AppBar、主按钮）
  static LinearGradient get primary => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          activePalette.light.primary,
          HSLColor.fromColor(activePalette.light.primary)
              .withLightness(
                  (HSLColor.fromColor(activePalette.light.primary).lightness - 0.05)
                      .clamp(0.0, 1.0))
              .toColor(),
        ],
      );

  /// 温暖渐变（卡片背景装饰）
  static LinearGradient get warm => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          activePalette.light.primaryContainer,
          activePalette.light.secondaryContainer,
        ],
      );

  /// 成就金色渐变
  static LinearGradient get gold => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          activePalette.light.secondaryContainer,
          HSLColor.fromColor(activePalette.light.secondary)
              .withLightness(
                  (HSLColor.fromColor(activePalette.light.secondary).lightness - 0.08)
                      .clamp(0.0, 1.0))
              .toColor(),
        ],
      );

  /// 天气蓝色渐变
  static LinearGradient get sky => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          activePalette.light.tertiaryContainer,
          activePalette.light.tertiary,
        ],
      );
}
