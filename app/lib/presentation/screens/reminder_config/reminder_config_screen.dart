/// TaWorld 提醒配置页面
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../services/local/local_reminder_service.dart';
import '../../../services/local/partner_service.dart';
import '../../../services/reminder_scheduler.dart';
import '../../../data/models/reminder_config.dart';
import '../../../data/models/partner.dart';
import '../../widgets/widgets.dart';

/// 提醒配置页面 — 管理某段关系下的所有提醒配置
class ReminderConfigScreen extends StatefulWidget {
  const ReminderConfigScreen({required this.partnerId, super.key});

  final String partnerId;

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
      final configs = await LocalReminderService.getConfigs(widget.partnerId);
      final partner = await PartnerService.getById(widget.partnerId);
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
      await ReminderScheduler.rescheduleConfig(config.id);
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
      await ReminderScheduler.rescheduleConfig(config.id);
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

  // ==================== 编辑配置 ====================

  Future<void> _editConfig(int index) async {
    final config = _configs[index];
    Map<String, dynamic>? newConfig;

    switch (config.category) {
      case 'sleep':
        newConfig = await _showSleepEditDialog(config.config);
      case 'meal':
        newConfig = await _showMealEditDialog(config.config);
      case 'weather':
        newConfig = await _showWeatherEditDialog(config.config);
      case 'custom':
        newConfig = await _showCustomEditDialog(config.config);
    }

    if (newConfig == null || !mounted) return;

    try {
      await LocalReminderService.updateConfig(config.id, config: newConfig);
      await ReminderScheduler.rescheduleConfig(config.id);
      setState(() {
        _configs[index] = config.copyWith(config: newConfig);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('配置已更新')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('更新失败，请重试')),
        );
      }
    }
  }

  /// 睡觉提醒编辑
  Future<Map<String, dynamic>?> _showSleepEditDialog(
    Map<String, dynamic> current,
  ) async {
    final targetTime = current['target_sleep_time'] as String? ?? '23:00';
    final advanceMinutes = current['advance_minutes'] as int? ?? 30;

    final parts = targetTime.split(':');
    var selectedHour = int.tryParse(parts[0]) ?? 23;
    var selectedMinute = int.tryParse(parts[1]) ?? 0;
    var selectedAdvance = advanceMinutes;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: TaRadius.borderLg),
          title: const Text('编辑睡觉提醒'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.bedtime_rounded),
                title: const Text('睡觉时间'),
                subtitle: Text(
                  '${selectedHour.toString().padLeft(2, '0')}:${selectedMinute.toString().padLeft(2, '0')}',
                ),
                onTap: () async {
                  final time = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay(hour: selectedHour, minute: selectedMinute),
                  );
                  if (time != null) {
                    setDialogState(() {
                      selectedHour = time.hour;
                      selectedMinute = time.minute;
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.alarm_rounded),
                title: const Text('提前提醒'),
                subtitle: Text('$selectedAdvance 分钟前'),
                trailing: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 15, label: Text('15')),
                    ButtonSegment(value: 30, label: Text('30')),
                    ButtonSegment(value: 60, label: Text('60')),
                  ],
                  selected: {selectedAdvance},
                  onSelectionChanged: (v) =>
                      setDialogState(() => selectedAdvance = v.first),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop({
                'target_sleep_time':
                    '${selectedHour.toString().padLeft(2, '0')}:${selectedMinute.toString().padLeft(2, '0')}',
                'advance_minutes': selectedAdvance,
              }),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  /// 吃饭提醒编辑
  Future<Map<String, dynamic>?> _showMealEditDialog(
    Map<String, dynamic> current,
  ) async {
    final meals = (current['meals'] as List?)
            ?.map((m) => Map<String, dynamic>.from(m as Map))
            .toList() ??
        [
          {'name': '早餐', 'target_time': '08:00', 'advance_minutes': 15},
          {'name': '午餐', 'target_time': '12:00', 'advance_minutes': 15},
          {'name': '晚餐', 'target_time': '18:00', 'advance_minutes': 15},
        ];

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: TaRadius.borderLg),
          title: const Text('编辑吃饭提醒'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...List.generate(meals.length, (i) {
                  final meal = meals[i];
                  final timeParts = (meal['target_time'] as String? ?? '12:00').split(':');
                  final hour = int.tryParse(timeParts[0]) ?? 12;
                  final minute = int.tryParse(timeParts[1]) ?? 0;
                  final advance = meal['advance_minutes'] as int? ?? 15;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Text(meal['name'] as String? ?? '',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final time = await showTimePicker(
                                  context: ctx,
                                  initialTime: TimeOfDay(hour: hour, minute: minute),
                                );
                                if (time != null) {
                                  setDialogState(() {
                                    meal['target_time'] =
                                        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                                  });
                                }
                              },
                              child: Text(
                                meal['target_time'] as String? ?? '',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          DropdownButton<int>(
                            value: advance,
                            items: const [
                              DropdownMenuItem(value: 10, child: Text('10分钟前')),
                              DropdownMenuItem(value: 15, child: Text('15分钟前')),
                              DropdownMenuItem(value: 30, child: Text('30分钟前')),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() => meal['advance_minutes'] = v);
                              }
                            },
                            isDense: true,
                            underline: const SizedBox(),
                          ),
                          if (meals.length > 1)
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, size: 20),
                              onPressed: () =>
                                  setDialogState(() => meals.removeAt(i)),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
                TextButton.icon(
                  onPressed: () {
                    setDialogState(() {
                      meals.add({
                        'name': '加餐',
                        'target_time': '15:00',
                        'advance_minutes': 15,
                      });
                    });
                  },
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('添加餐次'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop({'meals': meals}),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  /// 天气提醒编辑
  Future<Map<String, dynamic>?> _showWeatherEditDialog(
    Map<String, dynamic> current,
  ) async {
    final conditions = (current['notify_conditions'] as List?)
            ?.cast<String>()
            .toList() ??
        ['rain', 'snow', 'extreme_cold', 'extreme_heat'];

    final conditionOptions = {
      'rain': ('🌧️', '下雨'),
      'snow': ('❄️', '下雪'),
      'extreme_cold': ('🥶', '极寒 (≤0°C)'),
      'extreme_heat': ('🥵', '酷热 (≥35°C)'),
    };

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: TaRadius.borderLg),
          title: const Text('编辑天气提醒'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: conditionOptions.entries.map((entry) {
              final isSelected = conditions.contains(entry.key);
              final emoji = entry.value.$1;
              final label = entry.value.$2;
              return CheckboxListTile(
                value: isSelected,
                onChanged: (v) {
                  setDialogState(() {
                    if (v == true) {
                      conditions.add(entry.key);
                    } else {
                      conditions.remove(entry.key);
                    }
                  });
                },
                title: Text('$emoji $label'),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                contentPadding: EdgeInsets.zero,
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop({
                'notify_conditions': conditions,
                'custom_messages': current['custom_messages'] ?? {},
              }),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  /// 自定义提醒编辑
  Future<Map<String, dynamic>?> _showCustomEditDialog(
    Map<String, dynamic> current,
  ) async {
    final messageCtrl = TextEditingController(
      text: current['message'] as String? ?? '',
    );
    final timeParts = (current['target_time'] as String? ?? '09:00').split(':');
    var selectedHour = int.tryParse(timeParts[0]) ?? 9;
    var selectedMinute = int.tryParse(timeParts[1]) ?? 0;
    var repeatDaily = current['repeat_daily'] as bool? ?? true;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: TaRadius.borderLg),
          title: const Text('编辑自定义提醒'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: messageCtrl,
                decoration: const InputDecoration(
                  labelText: '提醒消息',
                  hintText: '写一句想对Ta说的话',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                maxLength: 100,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.access_time_rounded),
                title: const Text('提醒时间'),
                subtitle: Text(
                  '${selectedHour.toString().padLeft(2, '0')}:${selectedMinute.toString().padLeft(2, '0')}',
                ),
                onTap: () async {
                  final time = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay(hour: selectedHour, minute: selectedMinute),
                  );
                  if (time != null) {
                    setDialogState(() {
                      selectedHour = time.hour;
                      selectedMinute = time.minute;
                    });
                  }
                },
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                value: repeatDaily,
                onChanged: (v) => setDialogState(() => repeatDaily = v),
                title: const Text('每天重复'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (messageCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('请填写提醒消息')),
                  );
                  return;
                }
                Navigator.of(ctx).pop({
                  'message': messageCtrl.text.trim(),
                  'target_time':
                      '${selectedHour.toString().padLeft(2, '0')}:${selectedMinute.toString().padLeft(2, '0')}',
                  'repeat_daily': repeatDaily,
                });
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 创建 ====================

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
            iconAsset: 'assets/images/icon_weather_category.png',
          ),
          _CategoryOption(
            icon: '🌙',
            label: '睡觉提醒',
            subtitle: '到点提醒Ta早点休息',
            value: 'sleep',
            iconAsset: 'assets/images/icon_sleep_category.png',
          ),
          _CategoryOption(
            icon: '🍚',
            label: '吃饭提醒',
            subtitle: '提醒Ta按时吃饭',
            value: 'meal',
            iconAsset: 'assets/images/icon_meal_category.png',
          ),
          _CategoryOption(
            icon: '💝',
            label: '自定义提醒',
            subtitle: '设置你专属的提醒',
            value: 'custom',
            iconAsset: 'assets/images/icon_custom_category.png',
          ),
        ],
      ),
    );

    if (category == null) return;

    Map<String, dynamic> config = ReminderConfig.defaultConfigFor(category);

    // 自定义提醒需要用户配置具体内容
    if (category == 'custom') {
      final customConfig = await _showCustomEditDialog(config);
      if (customConfig == null) return;
      config = customConfig;
    }

    try {
      await LocalReminderService.createConfig(
        partnerId: widget.partnerId,
        category: category,
        config: config,
        enabled: true,
      );
      await ReminderScheduler.scheduleAll();
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
        imageAsset: 'assets/images/empty_reminder_config.png',
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
                        child: Image.asset(info.iconAsset,
                            width: 24, height: 24),
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
                    // 编辑按钮
                    IconButton(
                      icon: Icon(Icons.edit_rounded,
                          color: theme.colorScheme.onSurfaceVariant, size: 20),
                      tooltip: '编辑',
                      onPressed: () => _editConfig(index),
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
      'weather' => _CategoryInfo('🌦️', '天气提醒', TaLightColors.tertiary, 'assets/images/icon_weather_category.png'),
      'sleep' => const _CategoryInfo('🌙', '睡觉提醒', Color(0xFF7E57C2), 'assets/images/icon_sleep_category.png'),
      'meal' => _CategoryInfo('🍚', '吃饭提醒', TaLightColors.secondary, 'assets/images/icon_meal_category.png'),
      _ => _CategoryInfo('💝', '自定义提醒', TaLightColors.primary, 'assets/images/icon_custom_category.png'),
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
  const _CategoryInfo(this.emoji, this.label, this.color, this.iconAsset);
  final String emoji;
  final String label;
  final Color color;
  final String iconAsset;
}

class _CategoryOption extends StatelessWidget {
  const _CategoryOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.iconAsset,
  });

  final String icon;
  final String label;
  final String subtitle;
  final String value;
  final String iconAsset;

  @override
  Widget build(BuildContext context) {
    return SimpleDialogOption(
      onPressed: () => Navigator.of(context).pop(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: TaSpacing.xs),
        child: Row(
          children: [
            Image.asset(iconAsset, width: 28, height: 28),
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
