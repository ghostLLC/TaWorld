/// TaWorld 首页（单机版）
///
/// 底部导航 4 Tab：关怀概览、关心的人、提醒、我的
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../widgets/widgets.dart';
import '../../../services/local/local_user_service.dart';
import '../../../services/local/partner_service.dart';
import '../../../services/local/local_reminder_service.dart';
import '../../../services/local/local_achievement_service.dart';
import '../../../data/models/user.dart';
import '../../../data/models/partner.dart';
import '../../../data/models/reminder_config.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  static const _tabs = [
    _HomeTab(),
    _PartnersTab(),
    _RemindersTab(),
    _ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.favorite_border_rounded),
            selectedIcon: Icon(Icons.favorite_rounded),
            label: '关怀',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: '关心的人',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none_rounded),
            selectedIcon: Icon(Icons.notifications_rounded),
            label: '提醒',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Tab 1: 关怀概览
// ============================================================

class _HomeTab extends StatefulWidget {
  const _HomeTab();

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  bool _loading = true;
  String? _error;
  LocalUser? _user;
  Map<String, dynamic> _stats = {};
  List<dynamic> _achievements = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        LocalUserService.getUser(),
        LocalUserService.getStats(),
        LocalAchievementService.getAllWithProgress(),
      ]);
      setState(() {
        _user = results[0] as LocalUser?;
        _stats = results[1] as Map<String, dynamic>;
        _achievements = results[2] as List;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '加载失败';
        _loading = false;
      });
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了';
    if (hour < 12) return '早上好';
    if (hour < 14) return '中午好';
    if (hour < 18) return '下午好';
    if (hour < 22) return '晚上好';
    return '夜深了';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const SafeArea(child: TaLoading(message: '加载中...'));
    }
    if (_error != null) {
      return SafeArea(
        child: TaErrorState(message: _error!, onRetry: _loadAll),
      );
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: TaSpacing.page,
          children: [
            const SizedBox(height: TaSpacing.md),

            // 问候
            Row(
              children: [
                TaAvatar(
                  name: _user?.nickname ?? '我',
                  imageUrl: _user?.avatarPath,
                  size: TaSizes.avatarMd,
                ),
                const SizedBox(width: TaSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _user?.nickname ?? '我',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ).animate().fadeIn(duration: TaAnimation.normal),

            const SizedBox(height: TaSpacing.lg),

            // 关怀概览卡片
            TaCard.gradient(
              padding: TaSpacing.cardInnerLarge,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '关怀概览',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: TaSpacing.md),
                  Row(
                    children: [
                      _StatItem(
                        icon: Icons.people_rounded,
                        value: '${_stats['partnerCount'] ?? 0}',
                        label: '关心的人',
                      ),
                      const SizedBox(width: TaSpacing.lg),
                      _StatItem(
                        icon: Icons.check_circle_outline_rounded,
                        value: '${_stats['reminderCount'] ?? 0}',
                        label: '已发送',
                      ),
                      const SizedBox(width: TaSpacing.lg),
                      _StatItem(
                        icon: Icons.local_fire_department_rounded,
                        value: '${_stats['streakDays'] ?? 0}',
                        label: '连续天数',
                      ),
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 200.ms, duration: TaAnimation.normal),

            const SizedBox(height: TaSpacing.lg),

            // 成就进度
            if (_achievements.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '成就进度',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push(Routes.achievements),
                    child: const Text('查看全部'),
                  ),
                ],
              ),
              const SizedBox(height: TaSpacing.xs),
              SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: min(_achievements.length, 6),
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: TaSpacing.sm),
                  itemBuilder: (_, i) {
                    final ua = _achievements[i];
                    final icon = ua.achievementIcon ?? '🏆';
                    final name = ua.achievementName ?? '';
                    final unlocked = ua.unlocked;
                    final progress = ua.progress;
                    final target = _getTarget(i);
                    return SizedBox(
                      width: 80,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(icon, style: const TextStyle(fontSize: 28)),
                          const SizedBox(height: 4),
                          Text(
                            name,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            unlocked ? '已解锁' : '$progress/$target',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: unlocked
                                  ? TaLightColors.success
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: TaSpacing.xxl),
          ],
        ),
      ),
    );
  }

  int _getTarget(int index) {
    const targets = [1, 7, 30, 30, 100, 5, 10];
    return index < targets.length ? targets[index] : 1;
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: theme.colorScheme.secondary, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Tab 2: 关心的人
// ============================================================

class _PartnersTab extends StatefulWidget {
  const _PartnersTab();

  @override
  State<_PartnersTab> createState() => _PartnersTabState();
}

class _PartnersTabState extends State<_PartnersTab> {
  bool _loading = true;
  List<Partner> _partners = [];

  @override
  void initState() {
    super.initState();
    _loadPartners();
  }

  Future<void> _loadPartners() async {
    setState(() => _loading = true);
    try {
      final partners = await PartnerService.getAll();
      setState(() {
        _partners = partners;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _addPartner() async {
    final result = await context.push<bool>(Routes.addPartner);
    if (result == true) _loadPartners();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const SafeArea(child: TaLoading(message: '加载中...'));
    }

    if (_partners.isEmpty) {
      return SafeArea(
        child: TaEmptyState(
          icon: Icons.people_outline_rounded,
          title: '还没有关心的人',
          subtitle: '添加一个你在意的人，开始你的关怀之旅',
          actionText: '添加',
          onAction: _addPartner,
        ),
      );
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadPartners,
        child: ListView.builder(
          padding: TaSpacing.page,
          itemCount: _partners.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: TaSpacing.md),
                child: SizedBox(
                  width: double.infinity,
                  child: TaButton(
                    onPressed: _addPartner,
                    text: '添加关心的人',
                    icon: Icons.add_rounded,
                  ),
                ),
              ).animate().fadeIn(duration: TaAnimation.normal);
            }

            final partner = _partners[index - 1];
            final days = PartnerService.daysSince(partner.createdAt);
            return Padding(
              padding: const EdgeInsets.only(bottom: TaSpacing.sm),
              child: TaCard(
                onTap: () async {
                  final result = await context.push<bool>(
                    Routes.partnerDetail
                        .replaceAll(':id', partner.id),
                  );
                  if (result == true) _loadPartners();
                },
                child: Row(
                  children: [
                    TaAvatar(
                      name: partner.nickname,
                      size: TaSizes.avatarMd,
                    ),
                    const SizedBox(width: TaSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            partner.nickname,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${partner.typeLabel} · 已陪伴 $days 天',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: TaRadius.borderXs,
                      ),
                      child: Text(
                        partner.typeLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ).animate()
                .fadeIn(
                  delay: Duration(milliseconds: 100 * index),
                  duration: TaAnimation.normal,
                )
                .slideX(begin: 0.05, end: 0);
          },
        ),
      ),
    );
  }
}

// ============================================================
// Tab 3: 提醒
// ============================================================

class _RemindersTab extends StatefulWidget {
  const _RemindersTab();

  @override
  State<_RemindersTab> createState() => _RemindersTabState();
}

class _RemindersTabState extends State<_RemindersTab> {
  bool _loading = true;
  String? _error;
  List<Partner> _partners = [];
  Map<String, List<ReminderConfig>> _configsByPartner = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final partners = await PartnerService.getAll();
      final configs = await LocalReminderService.getAllEnabledConfigs();
      setState(() {
        _partners = partners;
        _configsByPartner = configs;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '加载失败';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const SafeArea(child: TaLoading(message: '加载提醒...'));
    }

    if (_error != null) {
      return SafeArea(
        child: TaErrorState(message: _error!, onRetry: _loadAll),
      );
    }

    final totalConfigs =
        _configsByPartner.values.fold<int>(0, (s, l) => s + l.length);

    if (_partners.isEmpty || totalConfigs == 0) {
      return SafeArea(
        child: TaEmptyState(
          icon: Icons.notifications_none_rounded,
          title: _partners.isEmpty ? '请先添加关心的人' : '暂无提醒',
          subtitle: _partners.isEmpty
              ? '在"关心的人"页面添加'
              : '进入对应页面设置提醒',
        ),
      );
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView.builder(
          padding: TaSpacing.page,
          itemCount: _partners.length,
          itemBuilder: (context, index) {
            final partner = _partners[index];
            final configs = _configsByPartner[partner.id] ?? [];

            return Padding(
              padding: const EdgeInsets.only(bottom: TaSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: TaSpacing.xs),
                    child: Row(
                      children: [
                        TaAvatar(
                          name: partner.nickname,
                          size: TaSizes.avatarSm,
                        ),
                        const SizedBox(width: TaSpacing.xs),
                        Text(
                          '${partner.nickname} 的提醒',
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                  if (configs.isEmpty)
                    TaCard.outlined(
                      padding: TaSpacing.cardInner,
                      child: Center(
                        child: Text(
                          '暂无提醒配置',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    ...configs.map((config) {
                      return TaCard(
                        padding: TaSpacing.cardInner,
                        margin: const EdgeInsets.only(bottom: TaSpacing.xs),
                        onTap: () => context.push(
                          Routes.reminderHistory
                              .replaceAll(':id', config.id),
                        ),
                        child: Row(
                          children: [
                            Text(config.categoryEmoji,
                                style: const TextStyle(fontSize: 24)),
                            const SizedBox(width: TaSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    config.categoryLabel,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    config.enabled ? '已启用' : '已停用',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: config.enabled
                                          ? TaLightColors.success
                                          : theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: config.enabled
                                    ? TaLightColors.success
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================
// Tab 4: 我的
// ============================================================

class _ProfileTab extends StatefulWidget {
  const _ProfileTab();

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  LocalUser? _user;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await LocalUserService.getUser();
    setState(() => _user = user);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: TaSpacing.page,
        children: [
          const SizedBox(height: TaSpacing.xl),

          Column(
            children: [
              TaAvatar(
                name: _user?.nickname ?? '我',
                imageUrl: _user?.avatarPath,
                size: TaSizes.avatarXl,
              ),
              const SizedBox(height: TaSpacing.sm),
              Text(
                _user?.nickname ?? '我',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_user?.phone != null) ...[
                const SizedBox(height: 4),
                Text(
                  _user!.phone!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ).animate().fadeIn(duration: TaAnimation.normal),

          const SizedBox(height: TaSpacing.xxl),

          TaCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _MenuItem(
                  icon: Icons.emoji_events_rounded,
                  label: '成就',
                  onTap: () => context.push(Routes.achievements),
                ),
                const Divider(height: 1),
                _MenuItem(
                  icon: Icons.psychology_rounded,
                  label: 'AI 助手',
                  onTap: () => context.push(Routes.aiChat),
                ),
                const Divider(height: 1),
                _MenuItem(
                  icon: Icons.key_rounded,
                  label: 'API Key 管理',
                  onTap: () => context.push(Routes.apiKeys),
                ),
                const Divider(height: 1),
                _MenuItem(
                  icon: Icons.settings_rounded,
                  label: '设置',
                  onTap: () => context.push(Routes.settings),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 200.ms, duration: TaAnimation.normal),

          const SizedBox(height: TaSpacing.xxl),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary, size: 24),
      title: Text(label, style: theme.textTheme.bodyLarge),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}
