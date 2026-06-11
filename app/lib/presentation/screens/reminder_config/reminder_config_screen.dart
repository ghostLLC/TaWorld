/// TaWorld 提醒配置页面
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../services/local/local_reminder_service.dart';
import '../../../services/local/partner_service.dart';
import '../../../data/models/reminder_config.dart';
import '../../../data/models/partner.dart';
import '../../widgets/widgets.dart';

/// 提醒配置页面 — 管理某段关系下的所有提醒配置
class ReminderConfigScreen extends StatefulWidget {
  const ReminderConfigScreen({required this.relationshipId, super.key});

  final String relationshipId;

  @override
  State<ReminderConfigScreen> createState() => _ReminderConfigScreenState();
}

class _ReminderConfigScreenState extends State<ReminderConfigScreen> {
  bool _loading = true;
  String? _error;
  List<ReminderConfig> _configs = [];
  Partner? _partner;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final configs = await LocalReminderService.getConfigs(widget.relationshipId);
      final partner = await PartnerService.getById(widget.relationshipId);
      if (mounted) {
        setState(() {
          _configs = configs;
          _partner = partner;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '加载提醒配置失败');
      }
    }
  }

  Future<void> _toggleEnabled(int index) async {
    final config = _configs[index];
    final newEnabled = !config.enabled;

    // 乐观更新
    setState(() {
      _configs[index] = config.copyWith(enabled: newEnabled);
    });

    try {
      await LocalReminderService.updateConfig(config.id, enabled: newEnabled);
    } catch (e) {
      // 回滚
      if (mounted) {
        setState(() {
          _configs[index] = config.copyWith(enabled: !newEnabled);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('更新失败，请重试')),
        );
      }
    }
  }

  Future<void> _deleteConfig(int index) async {
    final config = _configs[index];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: TaRadius.borderLg),
        title: const Text('删除提醒'),
        content: const Text('确定删除这个提醒配置吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await LocalReminderService.deleteConfig(config.id);
      if (mounted) {
        setState(() => _configs.removeAt(index));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已删除')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除失败，请重试')),
        );
      }
    }
  }

  Future<void> _createConfig() async {
    final category = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: TaRadius.borderLg),
        title: const Text('选择提醒类型'),
        children: [
          _CategoryOption(
            icon: '🌦️',
            label: '天气提醒',
            subtitle: '天气变化时提醒关心Ta',
            value: 'weather',
          ),
          _CategoryOption(
            icon: '🌙',
            label: '睡觉提醒',
            subtitle: '到点提醒Ta早点休息',
            value: 'sleep',
          ),
          _CategoryOption(
            icon: '🍚',
            label: '吃饭提醒',
            subtitle: '提醒Ta按时吃饭',
            value: 'meal',
          ),
          _CategoryOption(
            icon: '💝',
            label: '自定义提醒',
            subtitle: '设置你专属的提醒',
            value: 'custom',
          ),
        ],
      ),
    );

    if (category == null) return;

    try {
      await LocalReminderService.createConfig(
        partnerId: widget.relationshipId,
        category: category,
        config: ReminderConfig.defaultConfigFor(category),
        enabled: true,
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('提醒创建成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('创建失败，请重试')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_partner != null ? '${_partner!.nickname} - 提醒' : '提醒配置'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: '新建提醒',
            onPressed: _createConfig,
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: _configs.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _createConfig,
              icon: const Icon(Icons.add_rounded),
              label: const Text('新建提醒'),
            )
          : null,
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);

    if (_loading) return const TaLoading(message: '加载提醒配置...');
    if (_error != null) {
      return TaErrorState(message: _error!, onRetry: _loadData);
    }
    if (_configs.isEmpty) {
      return TaEmptyState(
        icon: Icons.notifications_none_rounded,
        title: '还没有提醒',
        subtitle: '点击右上角 + 创建第一个提醒',
        actionText: '新建提醒',
        onAction: _createConfig,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: TaSpacing.page,
        itemCount: _configs.length,
        itemBuilder: (context, index) {
          final config = _configs[index];
          final info = _categoryInfo(config.category);

          return Padding(
            padding: const EdgeInsets.only(bottom: TaSpacing.sm),
            child: Dismissible(
              key: ValueKey(config.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: TaSpacing.lg),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.15),
                  borderRadius: TaRadius.borderMd,
                ),
                child: Icon(Icons.delete_rounded,
                    color: theme.colorScheme.error),
              ),
              confirmDismiss: (_) async {
                _deleteConfig(index);
                return false; // 不自动移除，由 _deleteConfig 控制
              },
              child: TaCard(
                padding: TaSpacing.cardInner,
                child: Row(
                  children: [
                    // 类型图标
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: info.color.withValues(alpha: 0.15),
                        borderRadius: TaRadius.borderSm,
                      ),
                      child: Center(
                        child: Text(info.emoji,
                            style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                    const SizedBox(width: TaSpacing.sm),
                    // 内容
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            config.categoryLabel,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: TaSpacing.xxs),
                          Text(
                            _configSummary(config),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // 开关
                    Switch(
                      value: config.enabled,
                      activeTrackColor: theme.colorScheme.primary,
                      onChanged: (_) => _toggleEnabled(index),
                    ),
                    // 历史按钮
                    IconButton(
                      icon: Icon(Icons.history_rounded,
                          color: theme.colorScheme.onSurfaceVariant),
                      tooltip: '提醒历史',
                      onPressed: () => context.push(
                        Routes.reminderHistory
                            .replaceAll(':id', config.id),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ).animate().fadeIn(delay: (index * 80).ms);
        },
      ),
    );
  }

  _CategoryInfo _categoryInfo(String category) {
    return switch (category) {
      'weather' => const _CategoryInfo('🌦️', '天气提醒', TaLightColors.tertiary),
      'sleep' => const _CategoryInfo('🌙', '睡觉提醒', Color(0xFF7E57C2)),
      'meal' => const _CategoryInfo('🍚', '吃饭提醒', TaLightColors.secondary),
      _ => const _CategoryInfo('💝', '自定义提醒', TaLightColors.primary),
    };
  }

  String _configSummary(ReminderConfig config) {
    final c = config.config;
    if (c.isEmpty) return '已配置';
    return switch (config.category) {
      'weather' => '触发条件: ${(c['notify_conditions'] as List?)?.length ?? 0} 种天气',
      'sleep' => '睡觉时间 ${c['target_sleep_time'] ?? c['sleep_time'] ?? '23:00'}',
      'meal' => '${(c['meals'] as List?)?.length ?? 0} 个餐次提醒',
      _ => c['message']?.toString() ?? '自定义提醒',
    };
  }
}

class _CategoryInfo {
  const _CategoryInfo(this.emoji, this.label, this.color);
  final String emoji;
  final String label;
  final Color color;
}

class _CategoryOption extends StatelessWidget {
  const _CategoryOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
  });

  final String icon;
  final String label;
  final String subtitle;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SimpleDialogOption(
      onPressed: () => Navigator.of(context).pop(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: TaSpacing.xs),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: TaSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
