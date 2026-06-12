/// TaWorld 加载 & 空状态组件
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';

// ──────────────────────────────────────────────────────────────
//  心形 CustomPainter
// ──────────────────────────────────────────────────────────────

/// 绘制填充心形的 [CustomPainter]。
class _HeartPainter extends CustomPainter {
  _HeartPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _heartPath(size);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _HeartPainter old) => old.color != color;

  static Path _heartPath(Size s) {
    final w = s.width;
    final h = s.height;
    return Path()
      ..moveTo(w / 2, h * 0.92)
      ..cubicTo(w * -0.15, h * 0.55, w * 0.10, h * 0.02, w / 2, h * 0.28)
      ..cubicTo(w * 0.90, h * 0.02, w * 1.15, h * 0.55, w / 2, h * 0.92)
      ..close();
  }
}

// ──────────────────────────────────────────────────────────────
//  TaLoading — 心跳 + 粒子 加载动画
// ──────────────────────────────────────────────────────────────

/// 加载占位动画
///
/// 跳动心形 + 向外发散的暖色粒子，1.2 秒循环。
class TaLoading extends StatefulWidget {
  const TaLoading({super.key, this.message, this.size = 48});

  final String? message;
  final double size;

  @override
  State<TaLoading> createState() => _TaLoadingState();
}

class _TaLoadingState extends State<TaLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 三段式缩放：膨胀 → 回弹 → 静止
  double _scale(double t) {
    if (t < 0.25) return 1.0 + 0.20 * Curves.easeOut.transform(t / 0.25);
    if (t < 0.50) {
      return 1.20 - 0.25 * Curves.easeIn.transform((t - 0.25) / 0.25);
    }
    return 0.95 + 0.05 * Curves.easeOut.transform((t - 0.50) / 0.50);
  }

  /// 光晕透明度：膨胀时亮，回弹后消退
  double _glow(double t) {
    if (t < 0.25) return 0.35 * Curves.easeOut.transform(t / 0.25);
    if (t < 0.50) return 0.35 - 0.35 * Curves.easeIn.transform((t - 0.25) / 0.25);
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heartColor = theme.colorScheme.primary;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              final sc = _scale(t);
              final gl = _glow(t);

              return SizedBox(
                width: widget.size * 2.5,
                height: widget.size * 2.5,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // ── 光晕圆 ──
                    Transform.scale(
                      scale: 0.6 + sc * 0.4,
                      child: Container(
                        width: widget.size * 1.6,
                        height: widget.size * 1.6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: heartColor.withValues(alpha: gl),
                        ),
                      ),
                    ),
                    // ── 粒子 ──
                    ..._buildParticles(t, theme),
                    // ── 心形 ──
                    Transform.scale(
                      scale: sc,
                      child: CustomPaint(
                        size: Size(widget.size, widget.size * 0.85),
                        painter: _HeartPainter(
                          heartColor.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (widget.message != null) ...[
            const SizedBox(height: TaSpacing.md),
            Text(
              widget.message!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 6 个粒子沿径向发射
  List<Widget> _buildParticles(double t, ThemeData theme) {
    const n = 6;
    final colors = [
      TaLightColors.primary,
      TaLightColors.secondary,
      TaLightColors.primary,
      TaLightColors.secondary,
      TaLightColors.primary,
      TaLightColors.secondary,
    ];

    return List.generate(n, (i) {
      final angle = (i / n) * 2 * math.pi + math.pi / n;
      final maxDist = widget.size * 0.55;
      double dist;
      double opacity;

      if (t < 0.25) {
        final p = t / 0.25;
        dist = maxDist * 0.5 * Curves.easeOut.transform(p);
        opacity = Curves.easeOut.transform(p);
      } else if (t < 0.50) {
        final p = (t - 0.25) / 0.25;
        dist = maxDist * (0.5 + 0.5 * Curves.easeIn.transform(p));
        opacity = 1.0 - Curves.easeIn.transform(p);
      } else {
        opacity = 0;
        dist = maxDist;
      }

      if (opacity < 0.01) return const SizedBox.shrink();

      return Positioned(
        left: widget.size * 1.25 + math.cos(angle) * dist - 2,
        top: widget.size * 1.25 + math.sin(angle) * dist - 2,
        child: Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors[i].withValues(alpha: opacity * 0.8),
          ),
        ),
      );
    });
  }
}

// ──────────────────────────────────────────────────────────────
//  TaThinkingDots — AI 思考三点弹跳指示器
// ──────────────────────────────────────────────────────────────

/// AI 正在思考动画
///
/// 三个珊瑚色圆点依次弹跳，600ms 循环。
class TaThinkingDots extends StatefulWidget {
  const TaThinkingDots({super.key});

  @override
  State<TaThinkingDots> createState() => _TaThinkingDotsState();
}

class _TaThinkingDotsState extends State<TaThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = TaLightColors.primary;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.10;
            double localT = _c.value - delay;
            if (localT < 0) localT += 1.0;

            double dy;
            if (localT < 0.4) {
              dy = -6 *
                  Curves.easeOut
                      .transform(localT < 0.2
                          ? localT / 0.2
                          : 1.0 - (localT - 0.2) / 0.2);
            } else {
              dy = 0;
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Transform.translate(
                offset: Offset(0, dy),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor.withValues(alpha: 0.75),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────
//  TaCelebrateAnimation — 成就解锁粒子庆祝
// ──────────────────────────────────────────────────────────────

/// 成就解锁庆祝动画覆盖层
///
/// 从中心爆发金色 + 珊瑚色粒子 + 闪光，800ms 单次播放。
class TaCelebrateAnimation extends StatefulWidget {
  const TaCelebrateAnimation({super.key, required this.size});

  /// 覆盖层尺寸（通常与徽章大小一致）
  final double size;

  @override
  State<TaCelebrateAnimation> createState() => _TaCelebrateAnimState();
}

class _TaCelebrateAnimState extends State<TaCelebrateAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  /// 预计算的粒子角度和距离
  static final _angles =
      List.generate(10, (i) => (i / 10) * 2 * math.pi + 0.3);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = [
      TaLightColors.secondary,
      TaLightColors.primary,
      TaLightColors.secondary,
      TaLightColors.primary,
      TaLightColors.warning,
      TaLightColors.secondary,
      TaLightColors.primary,
      TaLightColors.secondary,
      TaLightColors.primary,
      TaLightColors.warning,
    ];

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ── 中心闪光 ──
              Container(
                width: widget.size * 0.6 * (1 - t),
                height: widget.size * 0.6 * (1 - t),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: TaLightColors.secondary
                      .withValues(alpha: (1 - t) * 0.5),
                ),
              ),
              // ── 粒子爆发 ──
              ...List.generate(10, (i) {
                final angle = _angles[i];
                final maxDist = widget.size * 0.45;
                final dist =
                    maxDist * Curves.easeOut.transform(t.clamp(0.0, 1.0));
                final opacity = 1.0 - Curves.easeIn.transform(t);
                final particleSize = 3.0 + (1 - t) * 2.0;

                return Positioned(
                  left: widget.size / 2 + math.cos(angle) * dist,
                  top: widget.size / 2 + math.sin(angle) * dist,
                  child: Container(
                    width: particleSize,
                    height: particleSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors[i].withValues(alpha: opacity),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

/// 空状态占位
///
/// 当列表为空或数据未加载时显示，包含温暖的插图、文案、可选操作按钮。
/// 传入 [imageAsset] 时使用图片替代 [icon]。
class TaEmptyState extends StatelessWidget {
  const TaEmptyState({
    super.key,
    this.icon,
    this.imageAsset,
    required this.title,
    this.subtitle,
    this.actionText,
    this.onAction,
  }) : assert(icon != null || imageAsset != null,
            'icon 和 imageAsset 至少提供一个');

  final IconData? icon;
  final String? imageAsset;
  final String title;
  final String? subtitle;
  final String? actionText;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TaSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageAsset != null)
              Image.asset(
                imageAsset!,
                width: 120,
                height: 120,
                fit: BoxFit.contain,
              )
            else
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon!,
                  size: 40,
                  color: theme.colorScheme.primary,
                ),
              ),
            const SizedBox(height: TaSpacing.lg),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: TaSpacing.xs),
              Text(
                subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionText != null && onAction != null) ...[
              const SizedBox(height: TaSpacing.lg),
              OutlinedButton(
                onPressed: onAction,
                child: Text(actionText!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 错误状态
class TaErrorState extends StatelessWidget {
  const TaErrorState({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return TaEmptyState(
      imageAsset: 'assets/images/empty_error.png',
      title: '出了点问题',
      subtitle: message,
      actionText: onRetry != null ? '重试' : null,
      onAction: onRetry,
    );
  }
}
