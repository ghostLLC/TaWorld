/// TaWorld 首页（AI-First 三屏架构）
///
/// 底部导航 3 Tab：AI 助手（主屏）、关心的人（管理）、我的（个人）
library;

import 'dart:async';

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

class _PartnersLocalSnapshot {
  const _PartnersLocalSnapshot({
    required this.partners,
    required this.configsByPartner,
  });

  final List<Partner> partners;
  final Map<String, List<ReminderConfig>> configsByPartner;
}

Future<_PartnersLocalSnapshot> _loadPartnersLocalSnapshot() async {
  final results = await Future.wait([
    PartnerService.getAll(),
    LocalReminderService.getAllConfigs(),
  ]);
  return _PartnersLocalSnapshot(
    partners: results[0] as List<Partner>,
    configsByPartner: results[1] as Map<String, List<ReminderConfig>>,
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  late final PageController _pageController;
  late final Future<_PartnersLocalSnapshot> _partnersPreload;
  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _partnersPreload = _loadPartnersLocalSnapshot();
    _tabs = [
      const AiHomeScreen(),
      _PartnersTab(initialLoad: _partnersPreload),
      const _ProfileTab(),
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        children: _tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          setState(() => _currentIndex = i);
          _pageController.animateToPage(
            i,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        },
        destinations: [
          NavigationDestination(
            icon: Padding(
              padding: const EdgeInsets.all(2),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/onboarding_mascot.png',
                  width: 26,
                  height: 26,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            selectedIcon: Padding(
              padding: const EdgeInsets.all(2),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/onboarding_mascot.png',
                  width: 26,
                  height: 26,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            label: '小念',
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
  const _PartnersTab({required this.initialLoad});

  final Future<_PartnersLocalSnapshot> initialLoad;

  @override
  State<_PartnersTab> createState() => _PartnersTabState();
}

class _PartnersTabState extends State<_PartnersTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _loading = true;
  List<Partner> _partners = [];
  Map<String, List<ReminderConfig>> _configsByPartner = {};
  final Map<String, FullWeatherResult?> _weatherByPartner = {};
  final Set<String> _expandedIds = {};
  final Set<String> _weatherLoadingIds = {};
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadAll(initialLoad: widget.initialLoad, showLoading: true);
    PartnerService.refreshCounter.addListener(_onPartnerRefresh);
  }

  @override
  void dispose() {
    PartnerService.refreshCounter.removeListener(_onPartnerRefresh);
    super.dispose();
  }

  void _onPartnerRefresh() {
    if (mounted) _loadAll();
  }

  Future<void> _loadAll({
    Future<_PartnersLocalSnapshot>? initialLoad,
    bool showLoading = false,
    bool refreshWeather = true,
    bool forceWeatherRefresh = false,
  }) async {
    final generation = ++_loadGeneration;
    if (showLoading && _partners.isEmpty && mounted) {
      setState(() => _loading = true);
    }
    try {
      final snapshot = await (initialLoad ?? _loadPartnersLocalSnapshot());
      if (!mounted || generation != _loadGeneration) return;
      final partnerIds = snapshot.partners.map((partner) => partner.id).toSet();
      setState(() {
        _partners = snapshot.partners;
        _configsByPartner = snapshot.configsByPartner;
        _weatherByPartner.removeWhere((id, _) => !partnerIds.contains(id));
        _weatherLoadingIds.clear();
        _loading = false;
      });
      if (refreshWeather) {
        unawaited(
          _refreshWeather(
            snapshot.partners,
            generation,
            forceRefresh: forceWeatherRefresh,
          ),
        );
      }
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refreshWeather(
    List<Partner> partners,
    int generation, {
    required bool forceRefresh,
  }) async {
    final candidates = partners
        .where(
          (partner) =>
              (partner.latitude != null && partner.longitude != null) ||
              (partner.city?.isNotEmpty ?? false),
        )
        .toList(growable: false);
    if (candidates.isEmpty || !mounted || generation != _loadGeneration) {
      return;
    }

    setState(() {
      _weatherLoadingIds.addAll(candidates.map((partner) => partner.id));
    });

    await Future.wait(
      candidates.map((partner) async {
        FullWeatherResult? weather;
        try {
          if (partner.latitude != null && partner.longitude != null) {
            weather = await WeatherService.getFullWeatherByCoords(
              partner.latitude!,
              partner.longitude!,
              forceRefresh: forceRefresh,
            );
          } else {
            weather = await WeatherService.getFullWeather(
              partner.city!,
              forceRefresh: forceRefresh,
            );
          }
        } catch (_) {
          weather = null;
        }
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _weatherByPartner[partner.id] = weather;
          _weatherLoadingIds.remove(partner.id);
        });
      }),
    );
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
    _loadAll(refreshWeather: false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    if (_loading) {
      return const SafeArea(child: TaLoading(message: '加载中...'));
    }

    if (_partners.isEmpty) {
      return SafeArea(
        child: TaEmptyState(
          imageAsset: 'assets/images/empty_partners.png',
          title: '还没有关心的人',
          subtitle: '添加一个你在意的人，开始你的关怀之旅',
          actionText: '添加',
          onAction: _addPartner,
        ),
      );
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () =>
            _loadAll(refreshWeather: true, forceWeatherRefresh: true),
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
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
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
            final weatherLoading = _weatherLoadingIds.contains(partner.id);
            final days = PartnerService.daysSince(partner.createdAt);

            return Padding(
                  padding: const EdgeInsets.only(bottom: TaSpacing.sm),
                  child: _PartnerCard(
                    partner: partner,
                    days: days,
                    weather: weather,
                    weatherLoading: weatherLoading,
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
                      Routes.reminderConfig.replaceAll(
                        ':partnerId',
                        partner.id,
                      ),
                    ),
                    onEdit: () async {
                      final result = await context.push<bool>(
                        Routes.partnerDetail.replaceAll(':id', partner.id),
                      );
                      if (result == true) _loadAll();
                    },
                  ),
                )
                .animate()
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
    required this.weatherLoading,
    required this.configs,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onToggleConfig,
    required this.onPartnerTap,
    required this.onConfigTap,
    required this.onAddReminder,
    required this.onEdit,
  });

  final Partner partner;
  final int days;
  final FullWeatherResult? weather;
  final bool weatherLoading;
  final List<ReminderConfig> configs;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final ValueChanged<ReminderConfig> onToggleConfig;
  final VoidCallback onPartnerTap;
  final ValueChanged<ReminderConfig> onConfigTap;
  final VoidCallback onAddReminder;
  final VoidCallback onEdit;

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
      infoParts.add(
        '${_weatherEmoji(weather!.current.text)} ${weather!.current.text} ${weather!.current.temp}\u00B0C',
      );
    } else if (weatherLoading) {
      infoParts.add('天气加载中...');
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
                    imageUrl: partner.avatarPath,
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
                        if (partner.note != null &&
                            partner.note!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            partner.note!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.tertiary,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
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
                        horizontal: 8,
                        vertical: 4,
                      ),
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
                  // 编辑按钮
                  GestureDetector(
                    onTap: onEdit,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
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
    final activeConfigs = configs.where((c) => c.enabled).toList();
    final forecast = weather?.forecast ?? [];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(TaRadius.md),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),

          // ---- 天气预报行（3 天） ----
          if (forecast.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                TaSpacing.md,
                TaSpacing.sm,
                TaSpacing.md,
                0,
              ),
              child: Text(
                '未来天气',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TaSpacing.md,
                vertical: TaSpacing.xs,
              ),
              child: Row(
                children: forecast.take(3).map((day) {
                  final dateObj = DateTime.tryParse(day.date);
                  final dayLabel = dateObj != null
                      ? '${dateObj.month}/${dateObj.day}'
                      : day.date.substring(5);
                  // 取中午 12 点的天气描述
                  final midHour = day.hourly.firstWhere(
                    (h) => h.hour == 12,
                    orElse: () => day.hourly.first,
                  );
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(TaRadius.sm),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            dayLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _weatherEmoji(midHour.text),
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${day.minTemp}° / ${day.maxTemp}°',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          // ---- 活跃提醒摘要 ----
          if (activeConfigs.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                TaSpacing.md,
                TaSpacing.xs,
                TaSpacing.md,
                0,
              ),
              child: Text(
                '已开启的提醒',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...activeConfigs.map((config) => _buildConfigRow(config, theme)),
          ],

          // ---- 未开启的提醒 ----
          if (configs.any((c) => !c.enabled)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                TaSpacing.md,
                TaSpacing.xs,
                TaSpacing.md,
                0,
              ),
              child: Text(
                '其他提醒',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.6,
                  ),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ...configs
                .where((c) => !c.enabled)
                .map((config) => _buildConfigRow(config, theme)),
          ],

          // 无提醒时占位
          if (configs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(TaSpacing.md),
              child: Text(
                '暂无提醒配置',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),

          // 添加提醒按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(
              TaSpacing.md,
              TaSpacing.xs,
              TaSpacing.md,
              TaSpacing.md,
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
              TaSpacing.md,
              0,
              TaSpacing.md,
              TaSpacing.md,
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
            Image.asset(config.categoryIconAsset, width: 20, height: 20),
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

class _ProfileTabState extends State<_ProfileTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

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
    super.build(context);
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
    final byCategory = _reminderStats['byCategory'] as Map<String, int>? ?? {};
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
                      final iconAsset = switch (entry.key) {
                        'weather' => 'assets/images/icon_weather_category.png',
                        'sleep' => 'assets/images/icon_sleep_category.png',
                        'meal' => 'assets/images/icon_meal_category.png',
                        'custom' => 'assets/images/icon_custom_category.png',
                        _ => 'assets/images/icon_custom_category.png',
                      };
                      final pct = totalReminders > 0
                          ? (entry.value / totalReminders * 100).round()
                          : 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: TaSpacing.sm),
                        child: Row(
                          children: [
                            Image.asset(iconAsset, width: 18, height: 18),
                            const SizedBox(width: TaSpacing.xs),
                            Expanded(
                              child: Text(
                                label,
                                style: theme.textTheme.bodyMedium,
                              ),
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
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
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
                                style: theme.textTheme.labelSmall?.copyWith(
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
