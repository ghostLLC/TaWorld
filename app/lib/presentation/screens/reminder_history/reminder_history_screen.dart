/// TaWorld 提醒历史页面
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../app/design_tokens.dart';
import '../../../services/local/local_reminder_service.dart';
import '../../../data/models/reminder_log.dart';
import '../../widgets/widgets.dart';

/// 提醒历史页面
class ReminderHistoryScreen extends StatefulWidget {
  const ReminderHistoryScreen({required this.configId, super.key});

  final String configId;

  @override
  State<ReminderHistoryScreen> createState() => _ReminderHistoryScreenState();
}

class _ReminderHistoryScreenState extends State<ReminderHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<ReminderLog> _logs = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final logs = await LocalReminderService.getLogs(widget.configId);
      if (mounted) {
        setState(() {
          _logs = logs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '加载提醒记录失败');
      }
    }
  }

  Future<void> _confirmLog(String logId) async {
    await LocalReminderService.confirmReminder(logId);
    await _loadLogs();
  }

  Future<void> _sendReminder() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await LocalReminderService.sendReminder(widget.configId);
      await _loadLogs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('提醒已发送')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('发送失败，请重试')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('提醒历史'),
        centerTitle: true,
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _sending ? null : _sendReminder,
        icon: _sending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.send_rounded),
        label: const Text('立即提醒'),
      ),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    if (_loading) return const TaLoading(message: '加载中...');
    if (_error != null) {
      return TaErrorState(message: _error!, onRetry: _loadLogs);
    }
    if (_logs.isEmpty) {
      return const TaEmptyState(
        imageAsset: 'assets/images/empty_reminder_history.png',
        title: '暂无提醒记录',
        subtitle: '完成第一次提醒后会在这里显示',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLogs,
      child: ListView.separated(
        padding: TaSpacing.page,
        itemCount: _logs.length,
        separatorBuilder: (context, index) => const SizedBox(height: TaSpacing.xs),
        itemBuilder: (context, index) {
          final log = _logs[index];
          final statusInfo = _statusInfo(log.status, theme);

          return TaCard(
            padding: TaSpacing.cardInner,
            child: Row(
              children: [
                // 状态图标
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: statusInfo.color.withValues(alpha: 0.15),
                    borderRadius: TaRadius.borderSm,
                  ),
                  child: Icon(statusInfo.icon, color: statusInfo.color),
                ),
                const SizedBox(width: TaSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log.message ?? '发送了一条提醒',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: TaSpacing.xxs),
                      Text(
                        _formatTime(log.triggeredAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // 状态标签
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TaSpacing.xs,
                    vertical: TaSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: statusInfo.color.withValues(alpha: 0.12),
                    borderRadius: TaRadius.borderXs,
                  ),
                  child: Text(
                    statusInfo.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusInfo.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (log.status == 'sent')
                  Padding(
                    padding: const EdgeInsets.only(left: TaSpacing.xs),
                    child: IconButton(
                      icon: Icon(Icons.check_circle_outline_rounded,
                          color: TaLightColors.success, size: 20),
                      tooltip: '确认已提醒',
                      onPressed: () => _confirmLog(log.id),
                    ),
                  ),
              ],
            ),
          ).animate().fadeIn(delay: (index * 50).ms);
        },
      ),
    );
  }

  _StatusInfo _statusInfo(String status, ThemeData theme) {
    return switch (status) {
      'scheduled' => _StatusInfo(
          Icons.schedule_rounded,
          theme.colorScheme.onSurfaceVariant,
          '待触发',
        ),
      'triggered' => _StatusInfo(
          Icons.notifications_active_rounded,
          TaLightColors.warning,
          '已触发',
        ),
      'sent' => _StatusInfo(
          Icons.send_rounded,
          TaLightColors.tertiary,
          '已发送',
        ),
      'confirmed' => _StatusInfo(
          Icons.check_circle_rounded,
          TaLightColors.success,
          '已确认',
        ),
      _ => _StatusInfo(
          Icons.circle_outlined,
          theme.colorScheme.onSurfaceVariant,
          status,
        ),
    };
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

class _StatusInfo {
  const _StatusInfo(this.icon, this.color, this.label);
  final IconData icon;
  final Color color;
  final String label;
}
