/// TaWorld 连续天数火焰等级图标
library;

import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';

/// 连续天数火焰等级
///
/// 根据连续天数显示不同火焰：
/// - 1~3 天 → 小蜡烛
/// - 4~7 天 → 篝火
/// - 8+ 天  → 大火焰
class TaStreakFlame extends StatelessWidget {
  const TaStreakFlame({super.key, required this.days, this.iconSize = 16});

  /// 连续天数
  final int days;

  /// 图标尺寸
  final double iconSize;

  String get _asset {
    if (days <= 3) return 'assets/images/flame_candle.png';
    if (days <= 7) return 'assets/images/flame_campfire.png';
    return 'assets/images/flame_bonfire.png';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: TaAnimation.slow,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: Image.asset(
        _asset,
        key: ValueKey(_asset),
        width: iconSize.toDouble(),
        height: iconSize.toDouble(),
        fit: BoxFit.contain,
      ),
    );
  }
}
