/// TaWorld 提醒通知卡片组件
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../app/design_tokens.dart';

/// 提醒卡片的类型
enum ReminderCardType { weather, sleep, meal, custom }

/// 提醒通知卡片
///
/// 用于首页和提醒列表中展示单条提醒。
/// 包含类型图标、消息、时间、确认按钮。
class TaNotificationCard extends StatelessWidget {
  const TaNotificationCard({
    super.key,
    required this.type,
    required this.message,
    this.time,
    this.confirmed = false,
    this.onConfirm,
    this.onTap,
  });

  final ReminderCardType type;
  final String message;
  final String? time;
  final bool confirmed;
  final VoidCallback? onConfirm;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = _typeConfig;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: TaSpacing.xs),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: TaRadius.borderMd,
        border: Border.all(
          color: config.color.withValues(alpha: 0.3),
        ),
        boxShadow: theme.brightness == Brightness.light ? TaShadows.sm : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: TaRadius.borderMd,
          child: Padding(
            padding: TaSpacing.cardInner,
            child: Row(
              children: [
                // 类型图标
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: config.color.withValues(alpha: 0.15),
                    borderRadius: TaRadius.borderSm,
                  ),
                  child: Center(
                    child: Text(
                      config.emoji,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
                const SizedBox(width: TaSpacing.sm),

                // 消息内容
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (time != null) ...[
                        const SizedBox(height: TaSpacing.xxs),
                        Text(
                          time!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // 确认按钮
                if (onConfirm != null && !confirmed)
                  FilledButton.tonal(
                    onPressed: onConfirm,
                    style: FilledButton.styleFrom(
                      backgroundColor: config.color.withValues(alpha: 0.15),
                      foregroundColor: config.color,
                      minimumSize: const Size(60, 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: TaRadius.borderFull,
                      ),
                    ),
                    child: const Text('确认'),
                  ),

                if (confirmed)
                  Icon(
                    Icons.check_circle_rounded,
                    color: TaLightColors.success,
                    size: TaSizes.iconLg,
                  ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: TaAnimation.normal).slideY(
          begin: 0.1,
          curve: TaAnimation.curve,
        );
  }

  _TypeConfig get _typeConfig => switch (type) {
        ReminderCardType.weather =>
          _TypeConfig('🌦️', TaLightColors.tertiary),
        ReminderCardType.sleep =>
          _TypeConfig('🌙', const Color(0xFF7E57C2)),
        ReminderCardType.meal =>
          _TypeConfig('🍚', TaLightColors.secondary),
        ReminderCardType.custom =>
          _TypeConfig('💝', TaLightColors.primary),
      };
}

class _TypeConfig {
  const _TypeConfig(this.emoji, this.color);
  final String emoji;
  final Color color;
}
