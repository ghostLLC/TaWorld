/// TaWorld 首页
///
/// 参考页面实现 — 展示底部导航、卡片列表、提醒通知等。
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../widgets/widgets.dart';

/// 首页（含底部导航栏）
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          _HomeTab(),
          _RelationshipsTab(),
          _RemindersTab(),
          _ProfileTab(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              activeIcon: Icon(Icons.home_rounded),
              label: '首页',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline_rounded),
              activeIcon: Icon(Icons.people_rounded),
              label: '关系',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.notifications_none_rounded),
              activeIcon: Icon(Icons.notifications_rounded),
              label: '提醒',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 首页 Tab
// ============================================================

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // ---- 顶部问候 ----
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                TaSpacing.pagePadding,
                TaSpacing.lg,
                TaSpacing.pagePadding,
                TaSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greetingText,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: TaSpacing.xxs),
                        Text(
                          'Ta的世界 🫶',
                          style: theme.textTheme.displaySmall,
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 500.ms),
                  TaAvatar(
                    name: '我',
                    size: TaSizes.avatarLg,
                  ).animate().scale(delay: 200.ms, duration: 400.ms),
                ],
              ),
            ),
          ),

          // ---- 今日概览卡片 ----
          SliverToBoxAdapter(
            child: Padding(
              padding: TaSpacing.page,
              child: TaCard.gradient(
                padding: TaSpacing.cardInnerLarge,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.dashboard_rounded,
                          color: theme.colorScheme.primary,
                          size: TaSizes.iconMd,
                        ),
                        const SizedBox(width: TaSpacing.xs),
                        Text('今日概览', style: theme.textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: TaSpacing.md),
                    Row(
                      children: [
                        _StatItem(value: '0', label: '已发送', icon: Icons.send_rounded),
                        _StatItem(value: '0', label: '已确认', icon: Icons.check_circle_outline_rounded),
                        _StatItem(value: '0', label: '连续天数', icon: Icons.local_fire_department_rounded),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.05),
            ),
          ),

          // ---- 最近提醒 ----
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                TaSpacing.pagePadding,
                TaSpacing.md,
                TaSpacing.pagePadding,
                TaSpacing.xs,
              ),
              child: Row(
                children: [
                  Text('最近提醒', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: () {},
                    child: const Text('查看全部'),
                  ),
                ],
              ),
            ),
          ),

          // ---- 提醒卡片列表（示例数据） ----
          SliverPadding(
            padding: TaSpacing.page,
            sliver: SliverList.list(
              children: const [
                TaNotificationCard(
                  type: ReminderCardType.weather,
                  message: 'Ta那边要下雨了，提醒Ta带伞吧 🌂',
                  time: '2小时前',
                  confirmed: true,
                ),
                TaNotificationCard(
                  type: ReminderCardType.sleep,
                  message: 'Ta快到睡觉时间了，提醒Ta早点休息 🌙',
                  time: '刚刚',
                ),
                TaNotificationCard(
                  type: ReminderCardType.meal,
                  message: '快到午餐时间了，提醒Ta按时吃饭 🍚',
                  time: '5小时前',
                  confirmed: true,
                ),
              ],
            ),
          ),

          // ---- 成就进度 ----
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                TaSpacing.pagePadding,
                TaSpacing.md,
                TaSpacing.pagePadding,
                TaSpacing.xs,
              ),
              child: Row(
                children: [
                  Text('成就进度', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: () => context.push(Routes.achievements),
                    child: const Text('查看全部'),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: SizedBox(
              height: 120,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: TaSpacing.page,
                children: const [
                  Padding(
                    padding: EdgeInsets.only(right: TaSpacing.md),
                    child: TaAchievementBadge(
                      icon: '🌂',
                      name: '初次守护',
                      progress: 0,
                      target: 1,
                      points: 10,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(right: TaSpacing.md),
                    child: TaAchievementBadge(
                      icon: '🔥',
                      name: '连续7天',
                      progress: 3,
                      target: 7,
                      points: 50,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(right: TaSpacing.md),
                    child: TaAchievementBadge(
                      icon: '🌙',
                      name: '晚安大使',
                      progress: 12,
                      target: 30,
                      points: 100,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(right: TaSpacing.md),
                    child: TaAchievementBadge(
                      icon: '❤️',
                      name: '双向奔赴',
                      progress: 4,
                      target: 10,
                      points: 150,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 500.ms),
          ),

          // 底部安全间距
          const SliverToBoxAdapter(
            child: SizedBox(height: TaSpacing.xxl),
          ),
        ],
      ),
    );
  }

  String get _greetingText {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了 🌙';
    if (hour < 12) return '早上好 ☀️';
    if (hour < 14) return '中午好 🌤️';
    if (hour < 18) return '下午好 🌅';
    return '晚上好 🌙';
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: TaSizes.iconMd),
          const SizedBox(height: TaSpacing.xxs),
          Text(value, style: theme.textTheme.titleLarge),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 其他 Tab 占位（其他 AI 实现）
// ============================================================

class _RelationshipsTab extends StatelessWidget {
  const _RelationshipsTab();

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: TaEmptyState(
        icon: Icons.people_outline_rounded,
        title: '还没有关系',
        subtitle: '邀请你关心的人加入吧',
        actionText: '创建邀请',
      ),
    );
  }
}

class _RemindersTab extends StatelessWidget {
  const _RemindersTab();

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: TaEmptyState(
        icon: Icons.notifications_none_rounded,
        title: '暂无提醒',
        subtitle: '建立关系后就可以设置提醒了',
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: TaSpacing.page,
        child: Column(
          children: [
            const SizedBox(height: TaSpacing.xl),
            const TaAvatar.xl(name: '我'),
            const SizedBox(height: TaSpacing.md),
            Text('用户昵称', style: theme.textTheme.headlineMedium),
            const SizedBox(height: TaSpacing.xxs),
            Text(
              '138****1234',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: TaSpacing.xl),
            _ProfileMenuItem(
              icon: Icons.emoji_events_rounded,
              label: '我的成就',
              onTap: () => context.push(Routes.achievements),
            ),
            _ProfileMenuItem(
              icon: Icons.smart_toy_rounded,
              label: 'AI 关怀助手',
              onTap: () => context.push(Routes.aiChat),
            ),
            _ProfileMenuItem(
              icon: Icons.settings_rounded,
              label: '设置',
              onTap: () => context.push(Routes.settings),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileMenuItem extends StatelessWidget {
  const _ProfileMenuItem({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TaCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: TaSpacing.md,
        vertical: TaSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: TaSpacing.sm),
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          Icon(
            Icons.chevron_right_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
