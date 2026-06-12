/// TaWorld 首页（AI-First 三屏架构）
///
/// 底部导航 3 Tab：AI 助手（主屏）、关心的人（管理）、我的（个人）
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../widgets/widgets.dart';
import '../ai_home/ai_home_screen.dart';
import '../../../services/local/local_user_service.dart';
import '../../../services/local/partner_service.dart';
import '../../../services/local/local_reminder_service.dart';
import '../../../services/reminder_scheduler.dart';
import '../../../services/weather_service.dart';
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
    AiHomeScreen(),
    _PartnersTab(),
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
            icon: Icon(Icons.smart_toy_outlined),
            selectedIcon: Icon(Icons.smart_toy_rounded),
            label: 'AI 助手',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: '关心的人',
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
// Tab 2: 关心的人（合并原"关心的人" + "提醒"）
// ============================================================

class _PartnersTab extends StatefulWidget {
  const _PartnersTab();

  @override
  State<_PartnersTab> createState() => _PartnersTabState();
}

class _PartnersTabState extends State<_PartnersTab> {
  bool _loading = true;
  List<Partner> _partners = [];
  Map<String, List<ReminderConfig>> _configsByPartner = {};
  Map<String, WeatherResult?> _weatherByPartner = {};
  final Set<String> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final partners = await PartnerService.getAll();

      // 获取所有配置（包括未启用的），按 partnerId 分组
      final allConfigs = <String, List<ReminderConfig>>{};
      for (final p in partners) {
        final pConfigs = await LocalReminderService.getConfigs(p.id);
        allConfigs[p.id] = pConfigs;
      }

      // 获取天气
      final weatherMap = <String, WeatherResult?>{};
      for (final p in partners) {
        try {
          WeatherResult? w;
          if (p.latitude != null && p.longitude != null) {
            w = await WeatherService.getCurrentWeather(p.longitude!, p.latitude!);
          } else if (p.city != null && p.city!.isNotEmpty) {
            w = await WeatherService.getCurrentWeatherByCity(p.city!);
          }
          weatherMap[p.id] = w;
        } catch (_) {
          weatherMap[p.id] = null;
        }
      }

      if (!mounted) return;
      setState(() {
        _partners = partners;
        _configsByPartner = allConfigs;
        _weatherByPartner = weatherMap;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addPartner() async {
    final result = await context.push<bool>(Routes.addPartner);
    if (result == true) _loadAll();
  }

  void _toggleExpand(String partnerId) {
    setState(() {
      if (_expandedIds.contains(partnerId)) {
        _expandedIds.remove(partnerId);
      } else {
        _expandedIds.add(partnerId);
      }
    });
  }

  Future<void> _toggleConfig(ReminderConfig config) async {
    await LocalReminderService.updateConfig(
      config.id,
      enabled: !config.enabled,
    );
    await ReminderScheduler.scheduleAll();
    _loadAll();
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
        onRefresh: _loadAll,
        child: ListView.builder(
          padding: TaSpacing.page,
          itemCount: _partners.length + 1,
          itemBuilder: (context, index) {
            // 添加按钮放在列表底部，不抢注意力
            if (index == _partners.length) {
              return Padding(
                padding: const EdgeInsets.only(top: TaSpacing.sm),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _addPartner,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('添加关心的人'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.onSurfaceVariant,
                      side: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: TaSpacing.sm,
                      ),
                    ),
                  ),
                ),
              );
            }

            final partner = _partners[index];
            final isExpanded = _expandedIds.contains(partner.id);
            final configs = _configsByPartner[partner.id] ?? [];
            final weather = _weatherByPartner[partner.id];
            final days = PartnerService.daysSince(partner.createdAt);

            return Padding(
              padding: const EdgeInsets.only(bottom: TaSpacing.sm),
              child: _PartnerCard(
                partner: partner,
                days: days,
                weather: weather,
                configs: configs,
                isExpanded: isExpanded,
                onToggleExpand: () => _toggleExpand(partner.id),
                onToggleConfig: _toggleConfig,
                onPartnerTap: () async {
                  final result = await context.push<bool>(
                    Routes.partnerDetail.replaceAll(':id', partner.id),
                  );
                  if (result == true) _loadAll();
                },
                onConfigTap: (config) => context.push(
                  Routes.reminderHistory.replaceAll(':id', config.id),
                ),
                onAddReminder: () => context.push(
                  Routes.reminderConfig.replaceAll(':partnerId', partner.id),
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
// 可展开的关心的人卡片
// ============================================================

class _PartnerCard extends StatelessWidget {
  const _PartnerCard({
    required this.partner,
    required this.days,
    required this.weather,
    required this.configs,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onToggleConfig,
    required this.onPartnerTap,
    required this.onConfigTap,
    required this.onAddReminder,
  });

  final Partner partner;
  final int days;
  final WeatherResult? weather;
  final List<ReminderConfig> configs;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final ValueChanged<ReminderConfig> onToggleConfig;
  final VoidCallback onPartnerTap;
  final ValueChanged<ReminderConfig> onConfigTap;
  final VoidCallback onAddReminder;

  /// 根据经度估算当地时间（每15° ≈ 1小时时区偏移）
  String _localTimeStr() {
    final lng = partner.longitude;
    if (lng == null) return '';
    final utcNow = DateTime.now().toUtc();
    final offsetHours = (lng / 15).round();
    final local = utcNow.add(Duration(hours: offsetHours));
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  /// 天气描述 → emoji
  static String _weatherEmoji(String text) {
    if (text.contains('晴')) return '\u2600\uFE0F';
    if (text.contains('雪')) return '\u{1F328}\uFE0F';
    if (text.contains('雷')) return '\u{1F329}\uFE0F';
    if (text.contains('雨')) return '\u{1F327}\uFE0F';
    if (text.contains('雾') || text.contains('霾')) return '\u{1F32B}\uFE0F';
    if (text.contains('阴')) return '\u2601\uFE0F';
    if (text.contains('云')) return '\u{1F325}\uFE0F';
    return '\u{1F324}\uFE0F';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabledCount = configs.where((c) => c.enabled).length;
    final timeStr = _localTimeStr();
    final hasCity = partner.city != null && partner.city!.isNotEmpty;

    // 构建副标题：城市 · 关系 · 天数
    final subtitleParts = <String>[];
    if (hasCity) subtitleParts.add(partner.city!);
    subtitleParts.add(partner.typeLabel);
    subtitleParts.add('已陪伴 $days 天');

    // 构建天气时间条
    final infoParts = <String>[];
    if (timeStr.isNotEmpty) infoParts.add(timeStr);
    if (weather != null) {
      infoParts.add('${_weatherEmoji(weather!.text)} ${weather!.text} ${weather!.temp}\u00B0C');
    }

    return TaCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // ---- 头部（始终显示） ----
          InkWell(
            borderRadius: isExpanded
                ? const BorderRadius.vertical(top: Radius.circular(TaRadius.md))
                : TaRadius.borderMd,
            onTap: onToggleExpand,
            child: Padding(
              padding: const EdgeInsets.all(TaSpacing.md),
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
                          subtitleParts.join(' \u00B7 '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (infoParts.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            infoParts.join('  \u00B7  '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.tertiary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: TaSpacing.xs),
                  // 提醒数量
                  if (configs.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: TaRadius.borderXs,
                      ),
                      child: Text(
                        '$enabledCount 提醒',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  const SizedBox(width: TaSpacing.xs),
                  // 展开箭头
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: TaAnimation.fast,
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ---- 展开区域：提醒配置列表 ----
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: _buildExpandedContent(theme),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: TaAnimation.normal,
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedContent(ThemeData theme) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(TaRadius.md),
        ),
      ),
      child: Column(
        children: [
          const Divider(height: 1),
          if (configs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(TaSpacing.md),
              child: Text(
                '暂无提醒配置',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ...configs.map((config) => _buildConfigRow(config, theme)),
          // 添加提醒按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(
              TaSpacing.md, TaSpacing.xs, TaSpacing.md, TaSpacing.md,
            ),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onAddReminder,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('添加提醒'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ),
          // 查看详情
          Padding(
            padding: const EdgeInsets.fromLTRB(
              TaSpacing.md, 0, TaSpacing.md, TaSpacing.md,
            ),
            child: SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: onPartnerTap,
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('查看详情'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigRow(ReminderConfig config, ThemeData theme) {
    return InkWell(
      onTap: () => onConfigTap(config),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TaSpacing.md,
          vertical: TaSpacing.xs,
        ),
        child: Row(
          children: [
            Text(config.categoryEmoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: TaSpacing.xs),
            Expanded(
              child: Text(
                config.categoryLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Switch.adaptive(
              value: config.enabled,
              onChanged: (_) => onToggleConfig(config),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Tab 3: 我的
// ============================================================

class _ProfileTab extends StatefulWidget {
  const _ProfileTab();

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  bool _loading = true;
  String? _error;
  LocalUser? _user;
  Map<String, dynamic> _userStats = {};
  Map<String, dynamic> _reminderStats = {};

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
        LocalReminderService.getStats(),
      ]);
      if (!mounted) return;
      setState(() {
        _user = results[0] as LocalUser?;
        _userStats = results[1] as Map<String, dynamic>;
        _reminderStats = results[2] as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
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
      return const SafeArea(child: TaLoading(message: '加载中...'));
    }
    if (_error != null) {
      return SafeArea(
        child: TaErrorState(message: _error!, onRetry: _loadAll),
      );
    }

    final totalReminders = _reminderStats['totalCount'] as int? ?? 0;
    final streakDays = _reminderStats['streakDays'] as int? ?? 0;
    final byCategory =
        _reminderStats['byCategory'] as Map<String, int>? ?? {};
    final partnerCount = _userStats['partnerCount'] as int? ?? 0;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadAll,
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
              ],
            ).animate().fadeIn(duration: TaAnimation.normal),

            const SizedBox(height: TaSpacing.lg),

            // ---- 数据统计卡片 ----
            TaCard.gradient(
              padding: TaSpacing.cardInnerLarge,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '我的数据',
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
                        value: '$partnerCount',
                        label: '关心的人',
                      ),
                      const SizedBox(width: TaSpacing.md),
                      _StatItem(
                        icon: Icons.check_circle_outline_rounded,
                        value: '$totalReminders',
                        label: '关怀次数',
                      ),
                      const SizedBox(width: TaSpacing.md),
                      _StatItem(
                        icon: Icons.local_fire_department_rounded,
                        value: '$streakDays',
                        label: '连续天数',
                      ),
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 100.ms, duration: TaAnimation.normal),

            const SizedBox(height: TaSpacing.md),

            // ---- 分类统计 ----
            if (byCategory.isNotEmpty)
              TaCard(
                padding: TaSpacing.cardInner,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '分类统计',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: TaSpacing.sm),
                    ...byCategory.entries.map((entry) {
                      final label = switch (entry.key) {
                        'weather' => '天气提醒',
                        'sleep' => '睡觉提醒',
                        'meal' => '吃饭提醒',
                        'custom' => '自定义提醒',
                        _ => entry.key,
                      };
                      final emoji = switch (entry.key) {
                        'weather' => '\u{1F326}\u{FE0F}',
                        'sleep' => '\u{1F319}',
                        'meal' => '\u{1F35A}',
                        'custom' => '\u{1F49D}',
                        _ => '\u{1F49D}',
                      };
                      final pct = totalReminders > 0
                          ? (entry.value / totalReminders * 100).round()
                          : 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: TaSpacing.sm),
                        child: Row(
                          children: [
                            Text(emoji, style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: TaSpacing.xs),
                            Expanded(
                              child: Text(label,
                                  style: theme.textTheme.bodyMedium),
                            ),
                            Text(
                              '${entry.value}次',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: TaSpacing.xs),
                            Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: theme
                                    .colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: pct / 100,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: TaSpacing.xxs),
                            SizedBox(
                              width: 36,
                              child: Text(
                                '$pct%',
                                style:
                                    theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ).animate().fadeIn(delay: 200.ms, duration: TaAnimation.normal),

            const SizedBox(height: TaSpacing.lg),

            // ---- 菜单 ----
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
            ).animate().fadeIn(delay: 300.ms, duration: TaAnimation.normal),

            const SizedBox(height: TaSpacing.xxl),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 共享小组件
// ============================================================

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
