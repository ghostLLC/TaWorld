/// TaWorld 成就列表页面
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../app/design_tokens.dart';
import '../../../data/models/achievement.dart';
import '../../../services/local/local_achievement_service.dart';
import '../../widgets/widgets.dart';

/// 成就列表页
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  bool _loading = true;
  String? _error;
  List<UserAchievement> _achievements = [];
  Map<String, dynamic> _stats = {};

  static const _achievementTargets = <String, int>{
    '初次守护': 1,
    '连续守护7天': 7,
    '晚安大使': 30,
    '干饭督导': 30,
    '百日陪伴': 100,
    '创意达人': 5,
    // '双向奔赴' 暂时隐藏，留作后期拓展（已在数据库查询层过滤）
  };

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
      final results = await Future.wait([
        LocalAchievementService.getAllWithProgress(),
        LocalAchievementService.getStats(),
      ]);

      setState(() {
        _achievements = results[0] as List<UserAchievement>;
        _stats = results[1] as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      setState(() => _error = '加载失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('成就'),
        centerTitle: true,
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) return const TaLoading(message: '加载成就中...');
    if (_error != null) {
      return TaErrorState(message: _error!, onRetry: _loadData);
    }
    if (_achievements.isEmpty) {
      return const TaEmptyState(
        icon: Icons.emoji_events_outlined,
        title: '暂无成就',
        subtitle: '完成更多关怀来解锁成就吧',
      );
    }

    final unlocked = _stats['unlocked'] as int? ?? 0;
    final pending = _stats['pending'] as int? ?? 0;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: CustomScrollView(
        slivers: [
          // 统计概览
          SliverToBoxAdapter(
            child: Padding(
              padding: TaSpacing.page,
              child: TaCard.gradient(
                padding: TaSpacing.cardInnerLarge,
                child: Row(
                  children: [
                    _OverviewStat(
                      icon: Icons.emoji_events_rounded,
                      value: unlocked.toString(),
                      label: '已解锁',
                    ),
                    _OverviewStat(
                      icon: Icons.lock_outline_rounded,
                      value: pending.toString(),
                      label: '待解锁',
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms),
            ),
          ),

          // 成就网格
          SliverPadding(
            padding: TaSpacing.page,
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: TaSpacing.md,
                crossAxisSpacing: TaSpacing.md,
                childAspectRatio: 0.75,
              ),
              itemCount: _achievements.length,
              itemBuilder: (context, index) {
                final ua = _achievements[index];

                // Use known target from seed data; fall back to 1 for unknown achievements.
                final target = _achievementTargets[ua.achievementName ?? ''] ?? 1;

                return TaAchievementBadge(
                  icon: ua.achievementIcon ?? '🏆',
                  name: ua.achievementName ?? '',
                  progress: ua.progress,
                  target: target,
                  unlocked: ua.unlocked,
                ).animate().fadeIn(
                      delay: (index * 80).ms,
                      duration: TaAnimation.normal,
                    );
              },
            ),
          ),

          const SliverToBoxAdapter(
            child: SizedBox(height: TaSpacing.xxl),
          ),
        ],
      ),
    );
  }
}

class _OverviewStat extends StatelessWidget {
  const _OverviewStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

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
