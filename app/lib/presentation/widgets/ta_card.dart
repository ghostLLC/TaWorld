/// TaWorld 统一卡片组件
///
/// 所有页面中的卡片都应使用此组件，确保一致的圆角、阴影、间距。
library;

import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';

/// 统一卡片组件
///
/// 支持三种变体：
/// - [TaCard] 默认白色卡片
/// - [TaCard.gradient] 带渐变头部的卡片
/// - [TaCard.outlined] 描边卡片
class TaCard extends StatelessWidget {
  const TaCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.color,
  })  : _gradient = null,
        _hasGradient = false,
        _outlined = false;

  const TaCard.outlined({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.color,
  })  : _gradient = null,
        _hasGradient = false,
        _outlined = true;

  /// 带渐变头部装饰的卡片
  const TaCard.gradient({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.color,
    Gradient? gradient,
  })  : _gradient = gradient,
        _hasGradient = true,
        _outlined = false;

  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? _gradient;
  final bool _hasGradient;
  final bool _outlined;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final cardColor = color ?? theme.cardTheme.color ?? theme.colorScheme.surface;

    final Gradient? effectiveGradient =
        _hasGradient ? (_gradient ?? TaGradients.warm) : null;

    Widget card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: effectiveGradient != null ? null : cardColor,
        gradient: effectiveGradient,
        borderRadius: TaRadius.borderMd,
        border: _outlined
            ? Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.5),
              )
            : null,
        boxShadow: isDark ? null : TaShadows.sm,
      ),
      child: Padding(
        padding: padding ?? TaSpacing.cardInner,
        child: child,
      ),
    );

    if (onTap != null) {
      card = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: TaRadius.borderMd,
          child: card,
        ),
      );
    }

    return card;
  }
}
