/// TaWorld 设置页面（单机版）— 中心辐射式两级导航
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../widgets/widgets.dart';
import '../../widgets/background_readiness_card.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/models/user.dart';
import '../../../services/theme_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/ai_proactive_service.dart';
import '../../../services/ai_memory_service.dart';
import '../../../services/ai_memory_dreamer.dart';
import '../../../services/ai_service.dart';
import '../../../services/data_backup_service.dart';
import '../../../services/backup/backup_importer.dart';
import '../../../services/background_execution_service.dart';
import '../../../services/local/local_user_service.dart';

// ============================================================
// 设置子页面路由
// ============================================================

/// 设置子页面路由常量
abstract final class SettingsRoutes {
  static const notifications = '/settings/notifications';
  static const appearance = '/settings/appearance';
  static const aiData = '/settings/ai-data';
  static const account = '/settings/account';
}

// ============================================================
// 主设置页面（Hub）
// ============================================================

/// 设置页面 — 中心辐射入口
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// 子页面构建器，供路由配置引用
  static Widget buildNotificationsPage() => const _NotificationsSettings();
  static Widget buildAppearancePage() => const _AppearanceSettings();
  static Widget buildAiDataPage() => const _AiDataSettings();
  static Widget buildAccountPage() => const _AccountSettings();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: ListView(
        padding: TaSpacing.page,
        children: [
          const SizedBox(height: TaSpacing.sm),
          TaCard(
            padding: EdgeInsets.zero,
            onTap: () => context.push(SettingsRoutes.notifications),
            child: ListTile(
              leading: Icon(
                Icons.notifications_rounded,
                color: theme.colorScheme.primary,
              ),
              title: const Text('通知与关怀'),
              subtitle: Text(
                '推送通知、AI 主动关怀',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: TaSpacing.sm),
          TaCard(
            padding: EdgeInsets.zero,
            onTap: () => context.push(SettingsRoutes.appearance),
            child: ListTile(
              leading: Icon(
                Icons.palette_rounded,
                color: theme.colorScheme.primary,
              ),
              title: const Text('外观'),
              subtitle: Text(
                '主题模式、配色方案',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: TaSpacing.sm),
          TaCard(
            padding: EdgeInsets.zero,
            onTap: () => context.push(SettingsRoutes.aiData),
            child: ListTile(
              leading: Icon(
                Icons.memory_rounded,
                color: theme.colorScheme.primary,
              ),
              title: const Text('AI 与数据'),
              subtitle: Text(
                'API Key、AI 记忆、数据备份',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: TaSpacing.sm),
          TaCard(
            padding: EdgeInsets.zero,
            onTap: () => context.push(SettingsRoutes.account),
            child: ListTile(
              leading: Icon(
                Icons.person_rounded,
                color: theme.colorScheme.primary,
              ),
              title: const Text('账户'),
              subtitle: Text(
                '头像、昵称、版本、法律条款',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: TaSpacing.xxl),
        ],
      ),
    );
  }
}

// ============================================================
// 通知与关怀 子页面
// ============================================================

class _NotificationsSettings extends StatefulWidget {
  const _NotificationsSettings();

  @override
  State<_NotificationsSettings> createState() => _NotificationsSettingsState();
}

class _NotificationsSettingsState extends State<_NotificationsSettings>
    with WidgetsBindingObserver {
  bool _pushEnabled = true;
  bool _notificationsEnabled = true;
  bool _exactAlarmsAllowed = true;
  bool _aiProactiveEnabled = true;
  BackgroundExecutionReadiness? _backgroundReadiness;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pushEnabled = ThemeService.instance.pushEnabled;
    ThemeService.instance.addListener(_onThemeChanged);
    _checkPermissions();
    _loadAiProactiveSetting();
    _loadBackgroundReadiness();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ThemeService.instance.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _checkPermissions();
    _loadBackgroundReadiness();
  }

  void _onThemeChanged() {
    if (!mounted) return;
    setState(() {
      _pushEnabled = ThemeService.instance.pushEnabled;
    });
  }

  Future<void> _checkPermissions() async {
    final (enabled, canSchedule) = await NotificationService.checkPermission();
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = enabled;
      _exactAlarmsAllowed = canSchedule;
    });
  }

  Future<void> _loadAiProactiveSetting() async {
    final enabled = await AiProactiveService.isEnabled();
    if (mounted) setState(() => _aiProactiveEnabled = enabled);
  }

  Future<void> _loadBackgroundReadiness() async {
    if (!Platform.isAndroid) return;
    final readiness = await BackgroundExecutionService.getReadiness();
    if (mounted) setState(() => _backgroundReadiness = readiness);
  }

  Future<void> _openBackgroundSetting(Future<bool> Function() open) async {
    await open();
    // Some OEM settings return without a lifecycle callback.
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _loadBackgroundReadiness();
    });
  }

  Future<void> _onPushChanged(bool v) async {
    if (v) {
      final granted = await NotificationService.requestPermission();
      if (!granted) return;
    }
    await ThemeService.instance.setPushEnabled(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('通知与关怀'), centerTitle: true),
      body: ListView(
        padding: TaSpacing.page,
        children: [
          const SizedBox(height: TaSpacing.sm),
          TaCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('推送通知'),
                  subtitle: Text(
                    '允许 APP 发送提醒通知',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: _pushEnabled,
                  activeTrackColor: theme.colorScheme.primary,
                  onChanged: _onPushChanged,
                ),
                if (!_notificationsEnabled || !_exactAlarmsAllowed) ...[
                  Divider(
                    height: 1,
                    color: theme.colorScheme.error.withValues(alpha: 0.3),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.warning_amber_rounded,
                      color: theme.colorScheme.error,
                      size: 22,
                    ),
                    title: Text(
                      !_notificationsEnabled ? '通知权限未开启' : '精确定时权限未开启',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    subtitle: Text(
                      !_notificationsEnabled
                          ? '提醒通知和天气预警无法送达，请在系统设置中开启'
                          : '定时提醒可能无法准时送达，请在系统设置中开启',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: () async {
                        if (!_notificationsEnabled) {
                          await BackgroundExecutionService.openNotificationSettings();
                        } else {
                          await BackgroundExecutionService.openExactAlarmSettings();
                        }
                        // 从系统设置返回后重新检查权限
                        Future.delayed(
                          const Duration(milliseconds: 500),
                          _checkPermissions,
                        );
                      },
                      child: const Text('去开启'),
                    ),
                  ),
                ],
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                ),
                SwitchListTile(
                  title: const Text('AI 主动关怀'),
                  subtitle: Text(
                    'AI 根据上下文主动发送关怀消息',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: _aiProactiveEnabled,
                  activeTrackColor: theme.colorScheme.primary,
                  onChanged: (v) async {
                    await AiProactiveService.setEnabled(v);
                    if (mounted) {
                      setState(() => _aiProactiveEnabled = v);
                    }
                  },
                ),
              ],
            ),
          ),
          if (Platform.isAndroid && _backgroundReadiness != null) ...[
            const SizedBox(height: TaSpacing.md),
            BackgroundReadinessCard(
              readiness: _backgroundReadiness!,
              onOpenNotifications: () => _openBackgroundSetting(
                BackgroundExecutionService.openNotificationSettings,
              ),
              onOpenExactAlarms: () => _openBackgroundSetting(
                BackgroundExecutionService.openExactAlarmSettings,
              ),
              onOpenBattery: () => _openBackgroundSetting(
                BackgroundExecutionService.openBatteryOptimizationSettings,
              ),
              onOpenAutoStart: () => _openBackgroundSetting(
                BackgroundExecutionService.openAutoStartSettings,
              ),
            ),
          ],
          const SizedBox(height: TaSpacing.xxl),
        ],
      ),
    );
  }
}

// ============================================================
// 外观 子页面
// ============================================================

class _AppearanceSettings extends StatefulWidget {
  const _AppearanceSettings();

  @override
  State<_AppearanceSettings> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<_AppearanceSettings> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _themeMode = ThemeService.instance.mode;
    ThemeService.instance.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    ThemeService.instance.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (!mounted) return;
    setState(() {
      _themeMode = ThemeService.instance.mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('外观'), centerTitle: true),
      body: ListView(
        padding: TaSpacing.page,
        children: [
          const SizedBox(height: TaSpacing.sm),
          TaCard(
            padding: const EdgeInsets.all(TaSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '主题模式',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: TaSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('浅色'),
                        icon: Icon(Icons.light_mode_rounded),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('跟随系统'),
                        icon: Icon(Icons.brightness_auto_rounded),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('深色'),
                        icon: Icon(Icons.dark_mode_rounded),
                      ),
                    ],
                    selected: {_themeMode},
                    onSelectionChanged: (set) {
                      ThemeService.instance.setThemeMode(set.first);
                    },
                  ),
                ),
                const SizedBox(height: TaSpacing.md),
                Text(
                  '配色方案',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: TaSpacing.sm),
                Wrap(
                  spacing: TaSpacing.sm,
                  runSpacing: TaSpacing.sm,
                  children: kTaPalettes.map((palette) {
                    final isSelected =
                        ThemeService.instance.paletteId == palette.id;
                    return GestureDetector(
                      onTap: () => ThemeService.instance.setPalette(palette.id),
                      child: AnimatedContainer(
                        duration: TaAnimation.fast,
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: palette.preview,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.outlineVariant,
                            width: isSelected ? 3 : 1.5,
                          ),
                        ),
                        child: isSelected
                            ? Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 22,
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: TaSpacing.xs),
                Text(
                  kTaPalettes
                          .where((p) => p.id == ThemeService.instance.paletteId)
                          .map((p) => p.label)
                          .firstOrNull ??
                      '',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: TaSpacing.xxl),
        ],
      ),
    );
  }
}

// ============================================================
// AI 与数据 子页面
// ============================================================

class _AiDataSettings extends StatefulWidget {
  const _AiDataSettings();

  @override
  State<_AiDataSettings> createState() => _AiDataSettingsState();
}

class _AiDataSettingsState extends State<_AiDataSettings> {
  MemoryStats? _memoryStats;
  CacheStats? _cacheStats;
  bool _dreaming = false;
  DateTime? _lastBackupTime;
  bool _exporting = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _loadMemoryStats();
    _loadLastBackupTime();
  }

  Future<void> _loadLastBackupTime() async {
    final time = await DataBackupService.getLastBackupTime();
    if (mounted) setState(() => _lastBackupTime = time);
  }

  Future<void> _loadMemoryStats() async {
    final stats = await AiMemoryDreamer.getStats();
    final cache = await AiService.getCacheStats();
    if (mounted) {
      setState(() {
        _memoryStats = stats;
        _cacheStats = cache;
      });
    }
  }

  Future<void> _runDreamNow() async {
    if (_dreaming) return;
    setState(() => _dreaming = true);
    try {
      await AiMemoryDreamer.dream();
      await _loadMemoryStats();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('记忆整合完成')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('整合失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _dreaming = false);
    }
  }

  Future<void> _clearAiMemory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: TaRadius.borderLg),
        title: const Text('清除 AI 记忆'),
        content: const Text('将清除 AI 记住的所有信息（事实、对话摘要、历史片段），但不会删除对话记录本身。确定吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('确认清除'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await AiMemoryService.clearAllMemory();
      await AiService.resetCacheStats();
      await _loadMemoryStats();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('AI 记忆已清除')));
      }
    }
  }

  /// 导出备份文件
  Future<void> _exportBackup() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await DataBackupService.exportAndShare();
      await _loadLastBackupTime();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('备份已保存，可分享到微信文件传输助手等渠道')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// 导入备份文件
  Future<void> _importBackup() async {
    if (_importing) return;
    try {
      // 1. 让用户选择文件
      final filePath = await DataBackupService.pickBackupFile();
      if (filePath == null) return; // 用户取消

      setState(() => _importing = true);

      // 2. 验证备份文件
      final info = await DataBackupService.validateBackup(filePath);

      if (!mounted) return;

      // 3. 显示确认对话框
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: TaRadius.borderLg),
          title: const Text('导入备份'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(info.summary),
              const SizedBox(height: 12),
              Text(
                '导入将覆盖当前所有数据（用户信息、AI 记忆、对话记录等）。API Key 仅保留在本机，不会从备份导入。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('确认导入'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // 4. 执行导入
      await DataBackupService.importBackup(filePath);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('数据导入成功，请重启 APP')));
        // 刷新页面状态
        _loadMemoryStats();
        _loadLastBackupTime();
      }
    } on BackupImportException catch (e, stackTrace) {
      debugPrint('Backup import failed: ${e.cause}');
      debugPrintStack(stackTrace: e.causeStackTrace);
      if (e.rollbackCause != null) {
        debugPrint('Backup rollback failed: ${e.rollbackCause}');
        debugPrintStack(stackTrace: e.rollbackStackTrace ?? stackTrace);
      }
      if (mounted) {
        final message = e.rollbackSucceeded
            ? '导入失败，原数据已恢复'
            : '导入和自动恢复均失败，请勿继续编辑数据，并保留导入前备份文件';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e, stackTrace) {
      debugPrint('Backup validation/import failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('导入失败，备份文件未通过安全检查')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('AI 与数据'), centerTitle: true),
      body: ListView(
        padding: TaSpacing.page,
        children: [
          const SizedBox(height: TaSpacing.sm),

          // 服务配置
          _SectionTitle(title: '服务配置'),
          const SizedBox(height: TaSpacing.xs),
          TaCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.key_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  title: const Text('API Key 管理'),
                  subtitle: Text(
                    '配置 DeepSeek AI 密钥',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onTap: () => context.push(Routes.apiKeys),
                ),
              ],
            ),
          ),

          const SizedBox(height: TaSpacing.lg),

          // AI 记忆管理
          _SectionTitle(title: 'AI 记忆'),
          const SizedBox(height: TaSpacing.xs),
          TaCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.psychology_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  title: const Text('记忆统计'),
                  subtitle: Text(
                    _memoryStats != null
                        ? '事实 ${_memoryStats!.totalFacts} 条 · 摘要 ${_memoryStats!.totalSummaries} 条 · 片段 ${_memoryStats!.totalChunks} 条'
                        : '加载中...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                ),
                ListTile(
                  leading: Icon(
                    Icons.cached_rounded,
                    color: theme.colorScheme.tertiary,
                  ),
                  title: const Text('DeepSeek 缓存命中率'),
                  subtitle: Text(
                    _cacheStats != null
                        ? '${_cacheStats!.hitRatePercent}（命中 ${_cacheStats!.hitTokens} / 共 ${_cacheStats!.totalTokens} token）'
                        : '加载中...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await AiService.resetCacheStats();
                      await _loadMemoryStats();
                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('缓存统计已重置')),
                        );
                      }
                    },
                    child: const Text('重置'),
                  ),
                ),
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                ),
                ListTile(
                  leading: Icon(
                    Icons.auto_fix_high_rounded,
                    color: theme.colorScheme.secondary,
                  ),
                  title: const Text('立即整合记忆'),
                  subtitle: Text(
                    '去重、合并、衰减，提升记忆质量',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: _dreaming
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : Icon(
                          Icons.play_arrow_rounded,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                  onTap: _dreaming ? null : _runDreamNow,
                ),
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                ),
                ListTile(
                  leading: Icon(
                    Icons.memory_rounded,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    '清除 AI 记忆',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  subtitle: Text(
                    '删除所有记忆数据，重新开始',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  onTap: _clearAiMemory,
                ),
              ],
            ),
          ),

          const SizedBox(height: TaSpacing.lg),

          // 数据管理
          _SectionTitle(title: '数据管理'),
          const SizedBox(height: TaSpacing.xs),
          TaCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.upload_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  title: const Text('导出备份'),
                  subtitle: Text(
                    _lastBackupTime != null
                        ? '上次备份: ${_lastBackupTime!.month}/${_lastBackupTime!.day} ${_lastBackupTime!.hour.toString().padLeft(2, '0')}:${_lastBackupTime!.minute.toString().padLeft(2, '0')}'
                        : '导出所有数据为备份文件，可分享到微信等',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: _exporting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : Icon(
                          Icons.chevron_right_rounded,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                  onTap: _exporting ? null : _exportBackup,
                ),
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                ),
                ListTile(
                  leading: Icon(
                    Icons.download_rounded,
                    color: theme.colorScheme.secondary,
                  ),
                  title: const Text('导入备份'),
                  subtitle: Text(
                    '从备份文件恢复数据（支持微信/QQ接收的文件）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: _importing
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.secondary,
                          ),
                        )
                      : Icon(
                          Icons.chevron_right_rounded,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                  onTap: _importing ? null : _importBackup,
                ),
              ],
            ),
          ),

          const SizedBox(height: TaSpacing.xxl),
        ],
      ),
    );
  }
}

// ============================================================
// 账户与关于 子页面
// ============================================================

class _AccountSettings extends StatefulWidget {
  const _AccountSettings();

  @override
  State<_AccountSettings> createState() => _AccountSettingsState();
}

class _AccountSettingsState extends State<_AccountSettings> {
  LocalUser? _user;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await LocalUserService.getUser();
    if (!mounted) return;
    setState(() => _user = user);
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (image == null) return;

    // 复制到 App 私有目录
    final appDir = await getApplicationDocumentsDirectory();
    final avatarDir = Directory('${appDir.path}/avatars');
    if (!await avatarDir.exists()) {
      await avatarDir.create(recursive: true);
    }
    final ext = p.extension(image.path);
    final destPath = '${avatarDir.path}/user_avatar$ext';
    await File(image.path).copy(destPath);

    await LocalUserService.updateAvatar(destPath);
    _loadUser();
  }

  Future<void> _showNicknameDialog() async {
    final user = await LocalUserService.getUser();
    if (!mounted) return;

    final controller = TextEditingController(text: user?.nickname ?? '');
    final newNickname = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: TaRadius.borderLg),
        title: const Text('修改昵称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '请输入新昵称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('确认'),
          ),
        ],
      ),
    );

    if (newNickname != null && newNickname.trim().isNotEmpty) {
      await LocalUserService.updateNickname(newNickname.trim());
      _loadUser();
    }
  }

  /// 显示用户协议
  void _showTermsOfService() {
    showDialog(
      context: context,
      builder: (context) =>
          _LegalDocumentDialog(title: '用户协议', content: _termsOfServiceText),
    );
  }

  /// 显示隐私政策
  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (context) =>
          _LegalDocumentDialog(title: '隐私政策', content: _privacyPolicyText),
    );
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: TaRadius.borderLg),
        title: const Text('确认重置'),
        content: const Text('这将清除所有本地数据（用户信息、关心的人、提醒记录等），操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('确认重置'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final db = await DatabaseHelper.database;
      // 清除所有业务数据表
      for (final table in [
        'user_achievements',
        'reminder_logs',
        'reminder_configs',
        'chat_history',
        'ai_pending_messages',
        'partners',
        'users',
        'ai_wiki_facts',
        'ai_conversation_summaries',
        'conversation_chunks',
      ]) {
        await db.delete(table);
      }
      // 重新创建默认用户
      await LocalUserService.createUser(nickname: '');
      if (mounted) context.go(Routes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('账户'), centerTitle: true),
      body: ListView(
        padding: TaSpacing.page,
        children: [
          const SizedBox(height: TaSpacing.sm),

          // 头像区域
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  TaAvatar(
                    name: _user?.nickname ?? '我',
                    imageUrl: _user?.avatarPath,
                    size: TaSizes.avatarXl,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.camera_alt_rounded,
                        color: theme.colorScheme.onPrimary,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: TaSpacing.xs),
          Center(
            child: Text(
              '点击更换头像',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          const SizedBox(height: TaSpacing.lg),

          // 账户设置
          _SectionTitle(title: '账户'),
          const SizedBox(height: TaSpacing.xs),
          TaCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.edit_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  title: const Text('修改昵称'),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onTap: _showNicknameDialog,
                ),
              ],
            ),
          ),

          const SizedBox(height: TaSpacing.lg),

          // 关于
          _SectionTitle(title: '关于'),
          const SizedBox(height: TaSpacing.xs),
          TaCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.info_outline_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  title: const Text('版本'),
                  trailing: Text(
                    'v0.1.1',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(
                    Icons.description_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  title: const Text('用户协议'),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onTap: _showTermsOfService,
                ),
                ListTile(
                  leading: Icon(
                    Icons.privacy_tip_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  title: const Text('隐私政策'),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onTap: _showPrivacyPolicy,
                ),
              ],
            ),
          ),

          const SizedBox(height: TaSpacing.xl),

          // 重置数据按钮
          TaButton(
            onPressed: _confirmReset,
            text: '重置所有数据',
            icon: Icons.delete_forever_rounded,
          ),

          const SizedBox(height: TaSpacing.xxl),
        ],
      ),
    );
  }

  // ==================== 法律文本 ====================

  static const _termsOfServiceText = '''
Ta的世界 用户服务协议

更新日期：2024年12月
生效日期：2024年12月

一、总则

欢迎您使用「Ta的世界」应用（以下简称"本应用"）。本应用是一款以关怀为核心的本地化情感连接工具，帮助您记录和提醒关心身边的人。请您在使用前仔细阅读本协议。使用本应用即表示您同意接受本协议的全部条款。

二、服务内容

1. 本应用提供以下功能：联系人管理、提醒配置与调度、AI 关怀建议（需自行配置 DeepSeek API）、天气查询（使用免费开源服务，无需配置）、成就系统、本地数据存储等。
2. 本应用为纯本地应用，所有用户数据（包括但不限于联系人信息、提醒记录、对话历史等）均存储在您的设备本地，不会上传至任何服务器。
3. 小念智能助手功能需要您自行申请并配置 DeepSeek API 密钥，相关服务由第三方提供，本应用不对第三方服务的可用性、准确性承担责任。天气查询功能使用开源 Open-Meteo 服务，无需额外配置。

三、用户行为规范

1. 您应当合法使用本应用，不得利用本应用从事任何违反法律法规的活动。
2. 您应当妥善保管自行配置的 API 密钥，因密钥泄露导致的损失由您自行承担。
3. 本应用提供的 AI 关怀建议仅供参考，不构成任何专业建议。

四、知识产权

本应用的所有内容，包括但不限于软件代码、界面设计、图标、文案等，均受知识产权法律保护。未经授权不得复制、修改、反向工程或用于商业目的。

五、免责声明

1. 本应用按"现状"提供，不对功能的持续可用性、无错误运行作出任何保证。
2. 因不可抗力、第三方服务中断、设备故障等原因导致的服务中断或数据丢失，本应用不承担责任。
3. 建议您定期备份重要数据。

六、协议变更

本应用有权在必要时修改本协议条款。修改后的协议将在应用内公布。您在协议修改后继续使用本应用，即视为接受修改后的协议。

七、其他

1. 本协议的解释和执行适用中华人民共和国法律。
2. 因本协议引起的任何争议，双方应友好协商解决。
''';

  static const _privacyPolicyText = '''
Ta的世界 隐私政策

更新日期：2024年12月
生效日期：2024年12月

「Ta的世界」（以下简称"本应用"）尊重并保护您的隐私。本隐私政策旨在向您说明我们如何收集、使用和保护您的个人信息。

一、核心承诺：数据本地化

本应用是一款纯本地化应用。您在使用过程中产生的所有数据均存储在您的设备本地，不会通过网络上传至任何外部服务器。

二、我们收集的信息

1. 您主动提供的信息：
   - 您的昵称（仅用于应用内展示）
   - 您添加的联系人信息（昵称、关系类型、备注、位置信息）
   - 提醒配置和对话记录
   以上信息全部存储在设备本地数据库中。

2. 设备权限信息（仅在您授权后获取）：
   - 位置信息：用于天气查询功能，仅在您主动操作时获取，不做后台持续定位
   - 相册权限：用于选择头像图片
   - 通知权限：用于发送提醒通知

3. 第三方 API 调用信息：
   当您主动使用 AI 助手功能时，本应用会向您自行配置的 DeepSeek API 发送请求；天气查询功能使用开源 Open-Meteo 服务，无需配置密钥。DeepSeek API 的调用内容受其隐私政策约束，建议您查阅相关第三方的隐私政策。

三、我们如何使用信息

1. 您提供的所有本地信息仅用于实现本应用的核心功能（提醒调度、关怀建议、成就统计等）。
2. 我们不会将您的任何信息出售、出租或以其他方式提供给第三方。

四、数据存储与安全

1. 所有数据存储在设备本地的 SQLite 数据库中，不经过任何网络传输。
2. 当您卸载本应用时，本地数据将随应用一并删除。
3. 您可在"设置"中随时选择"重置所有数据"来清除全部本地信息。
4. 请注意：第三方 API 密钥存储在 SharedPreferences 中，属于本地存储，不经过网络传输。

五、未成年人保护

本应用适合所有年龄段用户使用。如果您是未满 14 周岁的未成年人，建议在监护人的指导下使用本应用，并由监护人协助完成 API 密钥等配置操作。

六、隐私政策的变更

我们可能会适时修订本隐私政策。修订后的政策将在应用内公布。重大变更将通过应用内通知等方式告知您。

七、联系我们

如您对本隐私政策有任何疑问或建议，欢迎通过应用内的反馈渠道与我们联系。
''';
}

// ============================================================
// 共享辅助组件
// ============================================================

/// 法律文档弹窗
class _LegalDocumentDialog extends StatelessWidget {
  const _LegalDocumentDialog({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: TaRadius.borderLg),
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: SingleChildScrollView(
          child: Text(
            content.trim(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.8,
            ),
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('我知道了'),
        ),
      ],
    );
  }
}

/// 区块标题
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
