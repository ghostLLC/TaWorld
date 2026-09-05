import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/background_execution_service.dart';
import '../../../services/reminder_health_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/notification_identity.dart';

class ReminderHealthCard extends StatelessWidget {
  const ReminderHealthCard({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ReminderHealth?>(
    valueListenable: ReminderHealthService.current,
    builder: (context, value, _) {
      if (value == null || (value.configCount == 0 && value.error == null)) {
        return const SizedBox.shrink();
      }
      final colors = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Material(
          color: value.hasIssue
              ? colors.errorContainer
              : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push('/settings/reminder-health'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    value.hasIssue
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_none_rounded,
                    color: value.hasIssue
                        ? colors.onErrorContainer
                        : colors.onSurfaceVariant,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      value.summary,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: value.hasIssue
                            ? colors.onErrorContainer
                            : colors.onSurface,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 20),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class ReminderHealthScreen extends StatefulWidget {
  const ReminderHealthScreen({super.key});
  @override
  State<ReminderHealthScreen> createState() => _ReminderHealthScreenState();
}

class _ReminderHealthScreenState extends State<ReminderHealthScreen> {
  bool _busy = false;
  List<Map<String, Object?>> _events = [];
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh({bool repair = false}) async {
    await ReminderHealthService.check(repair: repair);
    try {
      final db = await DatabaseHelper.database;
      final rows = await db.rawQuery(
        "SELECT e.*, r.message FROM notification_events e LEFT JOIN reminder_occurrences r ON e.occurrence_id = r.id WHERE e.kind NOT IN ('scheduled', 'cancelled') ORDER BY e.occurred_at DESC LIMIT 60",
      );
      final seen = <String>{};
      final visible = rows
          .where(
            (e) => seen.add(e['occurrence_id'] as String? ?? e['id'] as String),
          )
          .take(20)
          .toList();
      if (mounted) setState(() => _events = visible);
    } catch (_) {
      // The health snapshot already exposes storage/check errors. Keep the
      // last visible history instead of turning a failed refresh into a blank.
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂时未完成，请重试或检查系统权限')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    if (!await NotificationService.pushEnabled()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('提醒已暂停，请先在设置中开启提醒通知')));
      }
      return;
    }
    if (!await NotificationService.requestPermission()) return;
    await NotificationService.show(
      id: notificationIdFor(
        'notification-test:${DateTime.now().millisecondsSinceEpoch}',
      ),
      title: 'TaWorld 提醒测试',
      body: '如果你看到了这条通知，当前手机通知通路可以工作。',
      payload: '/settings/reminder-health',
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('测试通知已提交系统，请查看通知栏')));
    }
  }

  static String _eventLabel(Object? kind) => switch (kind) {
    'observed_in_tray' => '已在通知栏检测到',
    'posted_to_system' => '已提交系统，尚未确认显示',
    'action_done' => '你已确认',
    'action_snooze' => '已安排稍后提醒',
    'action_outdated' => '你标记为过时',
    'blocked_permission' => '被通知设置阻止',
    'publish_failed' || 'schedule_failed' || 'snooze_failed' => '未能完成，请检查提醒',
    'historical_unknown' => '无法确认是否显示',
    'reconcile_failed' => '提醒核对未完成',
    _ => '提醒状态已更新',
  };
  static String _backgroundLabel(String? outcome) => switch (outcome) {
    'notification_submitted' => '已生成建议并提交通知',
    'push_paused' => '提醒通知已暂停',
    'ai_paused' => '主动关心已关闭',
    'no_api_key' => '尚未配置模型',
    'quiet_hours' => '夜间静默，未打扰你',
    'cooldown' => '距上次提醒较近，暂不打扰',
    'daily_limit' => '已达到每天两条的上限',
    'no_candidate' || 'model_skipped' => '暂时没有需要打扰你的事',
    'invalid_response' => '模型返回不完整，本次未发送',
    'failed' => '检查失败，等待下次重试',
    'running' => '正在检查，或上次检查被系统中断',
    _ => '还没有后台记录，系统将择机运行',
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('提醒检查'),
      actions: [
        IconButton(
          tooltip: '重新检查',
          onPressed: _busy ? null : () => _action(_refresh),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: ValueListenableBuilder<ReminderHealth?>(
      valueListenable: ReminderHealthService.current,
      builder: (context, health, _) {
        if (health == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final theme = Theme.of(context);
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(health.summary, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(
                        '最近检查 ${ReminderHealth.formatTime(health.checkedAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      Text('未来已安排 ${health.pendingCount} 次提醒'),
                      if (health.error != null) Text(health.error!),
                      for (final issue in health.issues)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            issue,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('过去 24 小时', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                '通知栏检测到 ${health.observedCount} 次 · 你已确认 ${health.acknowledgedCount} 次',
              ),
              if (health.unknownCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('${health.unknownCount} 次历史提醒缺少显示记录，暂时无法确认。'),
                ),
              const SizedBox(height: 16),
              Text(
                '主动关心最近检查：${_backgroundLabel(health.lastBackgroundOutcome)}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('手机通知与渠道'),
                      subtitle: Text(
                        health.notificationAllowed && health.channelAllowed
                            ? '已开启'
                            : '需要开启',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _action(() async {
                        await BackgroundExecutionService.openNotificationSettings();
                      }),
                    ),
                    ListTile(
                      title: const Text('精确定时'),
                      subtitle: Text(
                        health.exactAllowed ? '已允许' : '未开启，提醒时间可能延后',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _action(() async {
                        await BackgroundExecutionService.openExactAlarmSettings();
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _action(() => _refresh(repair: true)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('修复未来提醒'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : () => _action(_test),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('发送测试通知'),
              ),
              const SizedBox(height: 20),
              Text('最近提醒记录', style: theme.textTheme.titleMedium),
              if (_events.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('还没有可核对的通知记录。'),
                ),
              for (final event in _events)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_eventLabel(event['kind'])),
                  subtitle: Text(
                    '${event['message'] ?? 'TaWorld 提醒'}\n${ReminderHealth.formatTime(DateTime.parse(event['occurred_at'] as String))}',
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                '已排程不等于已显示，已显示也不代表你已经阅读。通知被划掉后，如果没有留下观测记录，只能标记为无法确认。',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    ),
  );
}
