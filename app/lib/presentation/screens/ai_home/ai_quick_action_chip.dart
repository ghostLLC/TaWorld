import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';

/// 小念输入栏上方的快捷操作。
///
/// 所有入口统一采用“文字在左、图标在右”，让扫读顺序稳定；背景只做
/// 低浓度主题色染色，避免图片白底与高饱和按钮争抢对话内容的注意力。
class AiQuickActionChip extends StatelessWidget {
  const AiQuickActionChip({
    super.key,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surfaceContainerLow;
    final background = Color.alphaBlend(
      iconColor.withValues(alpha: 0.08),
      surface,
    );

    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        height: 48,
        child: Material(
          color: background,
          shape: StadiumBorder(
            side: BorderSide(color: iconColor.withValues(alpha: 0.14)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TaSpacing.md,
                vertical: TaSpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(width: TaSpacing.xs),
                  Icon(icon, size: 18, color: iconColor),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
