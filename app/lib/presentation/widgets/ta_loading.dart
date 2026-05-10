/// TaWorld 加载 & 空状态组件
library;

import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';

/// 加载占位动画
///
/// 温暖色调的跳动心形动画，替代冷冰冰的圆形 loading。
class TaLoading extends StatefulWidget {
  const TaLoading({super.key, this.message, this.size = 48});

  final String? message;
  final double size;

  @override
  State<TaLoading> createState() => _TaLoadingState();
}

class _TaLoadingState extends State<TaLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _scaleAnim = Tween(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _scaleAnim,
            child: Icon(
              Icons.favorite_rounded,
              size: widget.size,
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
            ),
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
}

/// 空状态占位
///
/// 当列表为空或数据未加载时显示，包含温暖的插图、文案、可选操作按钮。
class TaEmptyState extends StatelessWidget {
  const TaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionText,
    this.onAction,
  });

  final IconData icon;
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
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
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
      icon: Icons.error_outline_rounded,
      title: '出了点问题',
      subtitle: message,
      actionText: onRetry != null ? '重试' : null,
      onAction: onRetry,
    );
  }
}
