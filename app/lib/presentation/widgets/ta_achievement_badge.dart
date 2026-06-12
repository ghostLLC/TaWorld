/// TaWorld 成就徽章组件
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';

/// 成就徽章
///
/// 展示单个成就的图标、名称、进度环。
/// 解锁后显示金色光芒效果。
class TaAchievementBadge extends StatelessWidget {
  const TaAchievementBadge({
    super.key,
    required this.icon,
    required this.name,
    required this.progress,
    required this.target,
    this.unlocked = false,
    this.onTap,
    this.iconAsset,
  });

  final String icon;
  final String name;
  final int progress;
  final int target;
  final bool unlocked;
  final VoidCallback? onTap;
  final String? iconAsset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = target > 0 ? (progress / target).clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度环 + 图标
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 进度环
                CustomPaint(
                  size: const Size(72, 72),
                  painter: _ProgressRingPainter(
                    progress: ratio,
                    color: unlocked
                        ? TaLightColors.secondary
                        : theme.colorScheme.outline,
                    backgroundColor:
                        theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                // 图标容器
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: unlocked
                        ? TaLightColors.secondaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: iconAsset != null
                        ? Image.asset(
                            iconAsset!,
                            width: 28,
                            height: 28,
                          )
                        : Text(
                            icon,
                            style: TextStyle(
                              fontSize: 28,
                              color: unlocked ? null : Colors.grey,
                            ),
                          ),
                  ),
                ),
                // 解锁标记
                if (unlocked)
                  Positioned(
                    bottom: 0,
                    right: 4,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        gradient: TaGradients.gold,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: TaSpacing.xs),

          // 名称
          Text(
            name,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: unlocked ? FontWeight.w700 : FontWeight.w500,
              color: unlocked
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          // 进度/状态
          Text(
            unlocked ? '已解锁' : '$progress/$target',
            style: theme.textTheme.labelSmall?.copyWith(
              color: unlocked
                  ? TaLightColors.secondary
                  : theme.colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

/// 进度环绘制器
class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  final double progress;
  final Color color;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    const strokeWidth = 3.5;

    // 背景环
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    // 进度环
    if (progress > 0) {
      final progressPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
