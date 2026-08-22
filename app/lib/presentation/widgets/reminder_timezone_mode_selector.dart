import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../data/models/partner.dart';

/// Shared wall-clock basis selector for every scheduled reminder.
///
/// Partner-local time is intentionally unavailable until its IANA timezone is
/// confirmed. A guessed or stale timezone must never silently schedule an
/// overseas reminder at the wrong instant.
class ReminderTimezoneModeSelector extends StatelessWidget {
  const ReminderTimezoneModeSelector({
    required this.value,
    required this.partner,
    required this.onChanged,
    super.key,
  });

  final String value;
  final Partner? partner;
  final ValueChanged<String> onChanged;

  static bool canUsePartner(Partner? partner) {
    return partner?.timezoneConfirmed == true &&
        partner?.timezoneId?.trim().isNotEmpty == true;
  }

  static String normalize(String value, Partner? partner) {
    if (value == 'partner' && !canUsePartner(partner)) return 'user';
    return value == 'partner' ? 'partner' : 'user';
  }

  @override
  Widget build(BuildContext context) {
    final partnerAvailable = canUsePartner(partner);
    final normalized = normalize(value, partner);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('时间按谁所在地区计算', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: TaSpacing.xs),
        SegmentedButton<String>(
          segments: [
            const ButtonSegment(value: 'user', label: Text('我的时间')),
            ButtonSegment(
              value: 'partner',
              label: Text('${partner?.nickname ?? 'Ta'}当地'),
              enabled: partnerAvailable,
            ),
          ],
          selected: {normalized},
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
        if (!partnerAvailable)
          Padding(
            padding: const EdgeInsets.only(top: TaSpacing.xs),
            child: Text(
              '尚未确认对方时区，暂时只能按你的当地时间；可在和小念对话时补充。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
