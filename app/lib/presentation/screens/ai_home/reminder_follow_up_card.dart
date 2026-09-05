import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';
import '../../../data/models/reminder_occurrence_record.dart';
import '../../../services/reminder_occurrence_service.dart';

class ReminderFollowUpCard extends StatelessWidget {
  const ReminderFollowUpCard({
    super.key,
    required this.occurrence,
    required this.onResponse,
  });

  final ReminderOccurrenceRecord occurrence;
  final ValueChanged<ReminderUserResponse> onResponse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: TaSpacing.xs),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.88,
        ),
        padding: const EdgeInsets.all(TaSpacing.sm),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.46),
          borderRadius: TaRadius.borderLg,
          border: Border.all(
            color: theme.colorScheme.secondary.withValues(alpha: 0.24),
          ),
          boxShadow: TaShadows.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  size: 20,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: TaSpacing.xs),
                Expanded(
                  child: Text(
                    occurrence.deliveredAt == null
                        ? '这件事还需要提醒吗？'
                        : '这条提醒处理好了吗？',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: TaSpacing.xs),
            Text(
              occurrence.message ?? '有一条待确认的关心提醒',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: TaSpacing.sm),
            Wrap(
              spacing: TaSpacing.xs,
              runSpacing: TaSpacing.xs,
              children: [
                FilledButton.tonal(
                  onPressed: () => onResponse(ReminderUserResponse.done),
                  child: const Text('关心过了'),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: () => onResponse(ReminderUserResponse.snooze),
                  child: const Text('5分钟后'),
                ),
                TextButton(
                  onPressed: () => onResponse(ReminderUserResponse.outdated),
                  child: const Text('已过时'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
