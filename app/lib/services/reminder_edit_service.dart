import '../data/local/database_helper.dart';
import '../data/models/reminder_config.dart';
import 'local/local_reminder_service.dart';
import 'local/partner_service.dart';
import 'reminder_tool_planner.dart';

abstract final class ReminderEditService {
  static Future<ReminderConfig> update(Map<String, dynamic> arguments) async {
    final id = arguments['reminder_id'];
    final db = await DatabaseHelper.database;
    final rows = await db.query(
      'reminder_configs',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.length != 1) throw StateError('没有找到这条提醒，请先读取提醒列表');
    final before = ReminderConfig.fromMap(rows.single);
    if (arguments['category'] != null &&
        arguments['category'] != before.category) {
      throw StateError('不能直接更改提醒类别，请创建新的提醒后再暂停旧提醒');
    }
    final schedulingKeys = {
      'time',
      'scheduled_at',
      'relative_minutes',
      'repeat_daily',
      'weekdays',
      'message',
      'time_basis',
      'timezone_id',
      'advance_minutes',
      'weather_mode',
      'monitor_start',
      'monitor_end',
      'lead_minutes',
      'cooldown_minutes',
      'notify_conditions',
    };
    final hasScheduleChange = arguments.keys.any(schedulingKeys.contains);
    Map<String, dynamic>? config;
    String? basis, zone;
    if (hasScheduleChange) {
      final values = before.config;
      final meals = values['meals'] as List?;
      Map<String, dynamic>? meal;
      if (before.category == 'meal' && meals != null && meals.isNotEmpty) {
        final selected = meals
            .whereType<Map>()
            .where(
              (m) => meals.length == 1 || m['name'] == arguments['meal_name'],
            )
            .toList();
        if (selected.length != 1) throw StateError('请指定要修改的餐次 meal_name');
        meal = Map<String, dynamic>.from(selected.single);
      }
      final person = before.isSelfReminder
          ? null
          : await PartnerService.getById(before.partnerId);
      final merged = <String, dynamic>{
        ...values,
        'subject': before.isSelfReminder ? 'self' : 'partner',
        'partner_name': person?.nickname ?? '',
        'category': before.category,
        'time_basis': before.timezoneMode,
        if (before.timezoneId != null) 'timezone_id': before.timezoneId,
        'weather_mode': values['mode'] ?? 'daily_digest',
        'time':
            values['target_sleep_time'] ??
            meal?['target_time'] ??
            values['digest_time'] ??
            values['target_time'],
        'advance_minutes':
            meal?['advance_minutes'] ?? values['advance_minutes'] ?? 0,
        ...arguments,
      };
      if (before.category == 'custom' &&
          values['scheduled_at'] != null &&
          arguments['time'] != null &&
          arguments['scheduled_at'] == null &&
          arguments['relative_minutes'] == null) {
        throw StateError('这是一条单次提醒，请根据原日期提供新的 scheduled_at，不要转换成每日重复');
      }
      if (arguments['repeat_daily'] == true || arguments['weekdays'] != null) {
        merged.remove('scheduled_at');
      }
      final parsed = ReminderToolPlanner.parse(merged);
      final plan = parsed.plan;
      if (plan == null) throw StateError(parsed.error ?? '提醒参数不完整');
      basis = plan.timezoneMode;
      zone = person != null
          ? ReminderToolPlanner.resolveTimezoneId(plan: plan, partner: person)
          : null;
      if (basis == 'partner' && zone == null) throw StateError('请先补充可确定的城市或时区');
      config = plan.config;
      if (meal != null) {
        final updatedMeal = (config['meals'] as List).single as Map;
        config = {
          'meals': [
            for (final raw in meals!)
              if (raw is Map && raw['name'] == meal['name'])
                {...updatedMeal, 'name': meal['name']}
              else
                raw,
          ],
        };
      }
    }
    if (!hasScheduleChange && arguments['enabled'] is! bool) {
      throw StateError('没有提供要修改的字段');
    }
    await LocalReminderService.updateConfig(
      before.id,
      config: config,
      enabled: arguments['enabled'] as bool?,
      timezoneMode: basis,
      timezoneId: zone,
      clearTimezoneId: basis == 'user',
    );
    final saved = (await db.query(
      'reminder_configs',
      where: 'id = ?',
      whereArgs: [id],
    )).single;
    return ReminderConfig.fromMap(saved);
  }
}
