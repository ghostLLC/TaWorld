import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../app/design_tokens.dart';
import '../../data/models/partner.dart';
import 'reminder_timezone_mode_selector.dart';

class CustomReminderEditResult {
  const CustomReminderEditResult({
    required this.config,
    required this.timezoneMode,
  });

  final Map<String, dynamic> config;
  final String timezoneMode;
}

/// Edits an explicit date or recurring wall-clock schedule.
class CustomReminderEditor extends StatefulWidget {
  const CustomReminderEditor({
    super.key,
    required this.initial,
    this.partner,
    this.initialTimezoneMode = 'user',
  });

  final Map<String, dynamic> initial;
  final Partner? partner;
  final String initialTimezoneMode;

  @override
  State<CustomReminderEditor> createState() => _CustomReminderEditorState();
}

class _CustomReminderEditorState extends State<CustomReminderEditor> {
  late final TextEditingController _message;
  late TimeOfDay _time;
  late DateTime _date;
  late String _repeat;
  late Set<int> _weekdays;
  late String _timezoneMode;
  String? _error;

  @override
  void initState() {
    super.initState();
    final value = widget.initial;
    _message = TextEditingController(text: value['message'] as String? ?? '');
    _timezoneMode = ReminderTimezoneModeSelector.normalize(
      widget.initialTimezoneMode,
      widget.partner,
    );
    final parsed = DateTime.tryParse('${value['scheduled_at']}');
    final at = parsed == null ? null : _toDisplayTime(parsed);
    final parts = '${value['target_time'] ?? '09:00'}'.split(':');
    _time = at != null
        ? TimeOfDay.fromDateTime(at)
        : TimeOfDay(
            hour: (int.tryParse(parts.first) ?? 9).clamp(0, 23),
            minute: (int.tryParse(parts.last) ?? 0).clamp(0, 59),
          );
    final today = DateTime.now();
    _date = at ?? today.add(const Duration(days: 1));
    _repeat = at != null || value['repeat_daily'] == false
        ? 'once'
        : value['weekdays'] is List
        ? 'weekly'
        : 'daily';
    _weekdays =
        (value['weekdays'] as List?)?.whereType<int>().toSet() ??
        {1, 2, 3, 4, 5};
  }

  DateTime _toDisplayTime(DateTime value) {
    if (_timezoneMode == 'partner' &&
        ReminderTimezoneModeSelector.canUsePartner(widget.partner)) {
      return tz.TZDateTime.from(
        value,
        tz.getLocation(widget.partner!.timezoneId!),
      );
    }
    return value.toLocal();
  }

  DateTime _toUtc(DateTime value) {
    if (_timezoneMode == 'partner' &&
        ReminderTimezoneModeSelector.canUsePartner(widget.partner)) {
      final location = tz.getLocation(widget.partner!.timezoneId!);
      return tz.TZDateTime(
        location,
        value.year,
        value.month,
        value.day,
        value.hour,
        value.minute,
      ).toUtc();
    }
    return value.toUtc();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _save() {
    final at = _toUtc(
      DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute),
    );
    String? error;
    if (_message.text.trim().isEmpty) error = '请填写要提醒的事';
    if (_repeat == 'once' && !at.isAfter(DateTime.now())) {
      error = '请选择未来的日期和时间';
    }
    if (_repeat == 'weekly' && _weekdays.isEmpty) error = '至少选择一个星期';
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(
      CustomReminderEditResult(
        config: {
          'message': _message.text.trim(),
          'target_time':
              '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
          'repeat_daily': _repeat != 'once',
          if (_repeat == 'once') 'scheduled_at': at.toUtc().toIso8601String(),
          if (_repeat == 'weekly') 'weekdays': _weekdays.toList()..sort(),
        },
        timezoneMode: _timezoneMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('自定义提醒'),
    content: SizedBox(
      width: 340,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _message,
              maxLength: 200,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '要提醒的事',
                hintText: '例如：问问妈妈复查结果',
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: _repeat,
              decoration: const InputDecoration(labelText: '重复'),
              items: const [
                DropdownMenuItem(value: 'once', child: Text('仅一次')),
                DropdownMenuItem(value: 'daily', child: Text('每天')),
                DropdownMenuItem(value: 'weekly', child: Text('指定星期')),
              ],
              onChanged: (v) => setState(() => _repeat = v!),
            ),
            if (_repeat == 'once')
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('日期'),
                subtitle: Text('${_date.year}年${_date.month}月${_date.day}日'),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final today = DateUtils.dateOnly(DateTime.now());
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _date.isBefore(today) ? today : _date,
                    firstDate: today,
                    lastDate: DateTime(today.year + 10),
                  );
                  if (date != null) setState(() => _date = date);
                },
              ),
            ReminderTimezoneModeSelector(
              value: _timezoneMode,
              partner: widget.partner,
              onChanged: (mode) => setState(() => _timezoneMode = mode),
            ),
            const SizedBox(height: TaSpacing.sm),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _timezoneMode == 'partner'
                    ? '时间（${widget.partner?.nickname ?? 'Ta'}当地时间）'
                    : '时间（我的当地时间）',
              ),
              subtitle: Text(_time.format(context)),
              trailing: const Icon(Icons.schedule),
              onTap: () async {
                final time = await showTimePicker(
                  context: context,
                  initialTime: _time,
                );
                if (time != null) setState(() => _time = time);
              },
            ),
            if (_repeat == 'weekly')
              Wrap(
                spacing: 6,
                children: [
                  for (var d = 1; d <= 7; d++)
                    FilterChip(
                      label: Text(
                        '周${['一', '二', '三', '四', '五', '六', '日'][d - 1]}',
                      ),
                      selected: _weekdays.contains(d),
                      onSelected: (selected) => setState(() {
                        selected ? _weekdays.add(d) : _weekdays.remove(d);
                      }),
                    ),
                ],
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存提醒')),
    ],
  );
}
