import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../app/design_tokens.dart';
import 'tool_execution_result.dart';

class MilestoneMessageCard extends StatelessWidget {
  const MilestoneMessageCard({
    super.key,
    required this.milestone,
    this.onDismiss,
  });

  final ToolMilestone milestone;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final semanticColor = switch (milestone.status) {
      ToolExecutionStatus.success =>
        isDark ? TaDarkColors.success : TaLightColors.success,
      ToolExecutionStatus.partialSuccess =>
        isDark ? TaDarkColors.warning : TaLightColors.warning,
      ToolExecutionStatus.failure => theme.colorScheme.error,
      ToolExecutionStatus.information =>
        isDark ? TaDarkColors.info : TaLightColors.info,
    };
    final icon = switch (milestone.status) {
      ToolExecutionStatus.success => Icons.check_circle_rounded,
      ToolExecutionStatus.partialSuccess => Icons.warning_amber_rounded,
      ToolExecutionStatus.failure => Icons.error_outline_rounded,
      ToolExecutionStatus.information => Icons.info_outline_rounded,
    };
    final semanticsLabel = switch (milestone.status) {
      ToolExecutionStatus.success => '操作成功',
      ToolExecutionStatus.partialSuccess => '部分完成',
      ToolExecutionStatus.failure => '操作失败',
      ToolExecutionStatus.information => '操作信息',
    };

    return Semantics(
          container: true,
          label: semanticsLabel,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: TaSpacing.xs),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.82,
              ),
              padding: const EdgeInsets.all(TaSpacing.sm),
              decoration: BoxDecoration(
                color: semanticColor.withValues(alpha: isDark ? 0.14 : 0.10),
                borderRadius: TaRadius.borderMd,
                border: Border.all(
                  color: semanticColor.withValues(alpha: 0.42),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 22, color: semanticColor),
                  const SizedBox(width: TaSpacing.xs),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          milestone.title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: TaSpacing.xxs),
                        Text(
                          milestone.detail,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onDismiss != null) ...[
                    const SizedBox(width: TaSpacing.xxs),
                    IconButton(
                      onPressed: onDismiss,
                      tooltip: '收起结果',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                      icon: Icon(
                        Icons.done_rounded,
                        size: 20,
                        color: semanticColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(duration: TaAnimation.fast)
        .slideY(
          begin: 0.06,
          end: 0,
          duration: TaAnimation.fast,
          curve: TaAnimation.curveOut,
        );
  }
}
