import 'package:flutter/material.dart';

import '../../services/background_execution_service.dart';

/// Status and system-setting entry points for Android background delivery.
///
/// Autostart is deliberately shown as unknown because Android exposes no
/// public API that can verify OEM autostart permission.
class BackgroundReadinessCard extends StatelessWidget {
  const BackgroundReadinessCard({
    super.key,
    required this.readiness,
    required this.onOpenNotifications,
    required this.onOpenExactAlarms,
    required this.onOpenBattery,
    required this.onOpenAutoStart,
  });

  final BackgroundExecutionReadiness readiness;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenExactAlarms;
  final VoidCallback onOpenBattery;
  final VoidCallback onOpenAutoStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('后台提醒保障', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  '天气变化由系统后台尽力送达，省电模式、Doze 或厂商限制仍可能造成延迟。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _StatusRow(
            icon: Icons.notifications_outlined,
            title: '通知权限',
            status: readiness.notificationGranted ? '已开启' : '未开启',
            ready: readiness.notificationGranted,
            onTap: onOpenNotifications,
          ),
          _StatusRow(
            icon: Icons.alarm_outlined,
            title: '精确定时',
            status: readiness.exactAlarmAllowed ? '已开启' : '未开启',
            ready: readiness.exactAlarmAllowed,
            subtitle: '未授权时会自动降级为非精确定时',
            onTap: onOpenExactAlarms,
          ),
          _StatusRow(
            icon: Icons.battery_saver_outlined,
            title: '电池无限制',
            status: readiness.batteryOptimizationIgnored ? '已开启' : '未开启',
            ready: readiness.batteryOptimizationIgnored,
            onTap: onOpenBattery,
          ),
          _StatusRow(
            icon: Icons.play_circle_outline_rounded,
            title: '自启动',
            status: readiness.autoStartStatusKnown ? '已确认' : '需在系统中确认',
            ready: readiness.autoStartStatusKnown,
            subtitle: readiness.autoStartGuidanceAvailable
                ? '${readiness.manufacturer} 系统不提供授权状态读取接口'
                : '当前系统没有可识别的自启动专用页面',
            onTap: onOpenAutoStart,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(
              '这些设置必须由你在系统页面确认，TaWorld 无法替你开启或保证后台任务准时运行。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.title,
    required this.status,
    required this.ready,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String status;
  final bool ready;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        icon,
        color: ready ? theme.colorScheme.primary : theme.colorScheme.outline,
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: TextButton(onPressed: onTap, child: Text(status)),
    );
  }
}
