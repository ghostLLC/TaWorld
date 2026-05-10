/// TaWorld 按钮组件
///
/// 提供渐变主按钮、次要按钮、图标按钮等统一风格。
library;

import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';

/// 渐变主按钮
///
/// 用于页面中最重要的操作（如"登录"、"发送提醒"等）。
/// 自带渐变背景和圆角，按下时有缩放动画。
class TaButton extends StatefulWidget {
  const TaButton({
    super.key,
    required this.onPressed,
    required this.text,
    this.icon,
    this.loading = false,
    this.enabled = true,
    this.gradient,
  });

  final VoidCallback? onPressed;
  final String text;
  final IconData? icon;
  final bool loading;
  final bool enabled;
  final Gradient? gradient;

  @override
  State<TaButton> createState() => _TaButtonState();
}

class _TaButtonState extends State<TaButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnim = Tween(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _controller.forward();
  void _onTapUp(TapUpDetails _) => _controller.reverse();
  void _onTapCancel() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    final isActive = widget.enabled && !widget.loading;

    return ScaleTransition(
      scale: _scaleAnim,
      child: GestureDetector(
        onTapDown: isActive ? _onTapDown : null,
        onTapUp: isActive ? _onTapUp : null,
        onTapCancel: isActive ? _onTapCancel : null,
        child: AnimatedOpacity(
          duration: TaAnimation.fast,
          opacity: isActive ? 1.0 : 0.6,
          child: Container(
            height: TaSizes.buttonHeight,
            decoration: BoxDecoration(
              gradient: widget.gradient ?? TaGradients.primary,
              borderRadius: TaRadius.borderMd,
              boxShadow: isActive ? TaShadows.sm : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isActive ? widget.onPressed : null,
                borderRadius: TaRadius.borderMd,
                child: Center(
                  child: widget.loading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation(
                              Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.icon != null) ...[
                              Icon(
                                widget.icon,
                                color: Theme.of(context).colorScheme.onPrimary,
                                size: TaSizes.iconMd,
                              ),
                              const SizedBox(width: TaSpacing.xs),
                            ],
                            Text(
                              widget.text,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 小号圆形图标按钮
///
/// 用于卡片内的操作按钮（如"确认"、"关闭"等）。
class TaIconButton extends StatelessWidget {
  const TaIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 40,
    this.backgroundColor,
    this.iconColor,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color? backgroundColor;
  final Color? iconColor;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = backgroundColor ?? theme.colorScheme.surfaceContainerHighest;
    final fg = iconColor ?? theme.colorScheme.onSurfaceVariant;

    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: fg, size: size * 0.5),
          ),
        ),
      ),
    );
  }
}
