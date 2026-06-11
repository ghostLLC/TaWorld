/// TaWorld 设置页面（单机版）
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../widgets/widgets.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/theme_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/local/local_user_service.dart';

/// 设置页面
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _pushEnabled = true;
  bool _darkMode = false;

  @override
  void initState() {
    super.initState();
    _darkMode = ThemeService.instance.mode == ThemeMode.dark;
    _pushEnabled = ThemeService.instance.pushEnabled;
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
      _darkMode = ThemeService.instance.mode == ThemeMode.dark;
      _pushEnabled = ThemeService.instance.pushEnabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
      ),
      body: ListView(
        padding: TaSpacing.page,
        children: [
          const SizedBox(height: TaSpacing.sm),

          // 通知设置
          _SectionTitle(title: '通知'),
          const SizedBox(height: TaSpacing.xs),
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
              ],
            ),
          ),

          const SizedBox(height: TaSpacing.lg),

          // 外观设置
          _SectionTitle(title: '外观'),
          const SizedBox(height: TaSpacing.xs),
          TaCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('暗色模式'),
                  subtitle: Text(
                    '温暖的深色主题',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: _darkMode,
                  activeTrackColor: theme.colorScheme.primary,
                  onChanged: (v) => ThemeService.instance.setDarkMode(v),
                ),
              ],
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
                  leading: Icon(Icons.edit_outlined,
                      color: theme.colorScheme.primary),
                  title: const Text('修改昵称'),
                  trailing: Icon(Icons.chevron_right_rounded,
                      color: theme.colorScheme.onSurfaceVariant),
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
                  leading: Icon(Icons.info_outline_rounded,
                      color: theme.colorScheme.primary),
                  title: const Text('版本'),
                  trailing: Text(
                    'v0.1.0',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.description_outlined,
                      color: theme.colorScheme.primary),
                  title: const Text('用户协议'),
                  trailing: Icon(Icons.chevron_right_rounded,
                      color: theme.colorScheme.onSurfaceVariant),
                ),
                ListTile(
                  leading: Icon(Icons.privacy_tip_outlined,
                      color: theme.colorScheme.primary),
                  title: const Text('隐私政策'),
                  trailing: Icon(Icons.chevron_right_rounded,
                      color: theme.colorScheme.onSurfaceVariant),
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

  Future<void> _onPushChanged(bool v) async {
    if (v) {
      final granted = await NotificationService.requestPermission();
      if (!granted) return;
    }
    await ThemeService.instance.setPushEnabled(v);
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
        'user_achievements', 'reminder_logs', 'reminder_configs',
        'chat_history', 'partners', 'users',
      ]) {
        await db.delete(table);
      }
      // 重新创建默认用户
      await LocalUserService.createUser(nickname: '');
      if (mounted) context.go(Routes.home);
    }
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
          decoration: const InputDecoration(
            hintText: '请输入新昵称',
          ),
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
    }
  }
}

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
