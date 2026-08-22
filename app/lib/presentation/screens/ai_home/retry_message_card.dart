import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';

class RetryMessageCard extends StatelessWidget {
  const RetryMessageCard({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: TaSpacing.xs),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        padding: const EdgeInsets.fromLTRB(
          TaSpacing.sm,
          TaSpacing.sm,
          TaSpacing.xs,
          TaSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.08),
          borderRadius: TaRadius.borderMd,
          border: Border.all(color: primary.withValues(alpha: 0.26)),
        ),
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, color: primary, size: 22),
            const SizedBox(width: TaSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '刚才没有连上网络',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: TaSpacing.xxs),
                  Text(
                    '你的消息还在，连接恢复后可以继续',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: TaSpacing.xs),
            FilledButton.tonal(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(60, 38),
                padding: const EdgeInsets.symmetric(horizontal: TaSpacing.sm),
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
