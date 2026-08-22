import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../app/design_tokens.dart';
import '../../../data/models/partner.dart';
import '../../../data/models/reminder_config.dart';
import '../../../services/weather_service.dart';
import 'care_graph_share_poster.dart';

/// 以用户为中心、以同尺寸节点呈现所有关心的人。
class CareGraphView extends StatefulWidget {
  const CareGraphView({
    super.key,
    required this.partners,
    required this.weatherByPartner,
    required this.weatherLoadingIds,
    required this.configsByPartner,
    required this.onChatPartner,
    required this.onAddReminder,
    required this.onOpenProfile,
  });

  final List<Partner> partners;
  final Map<String, FullWeatherResult?> weatherByPartner;
  final Set<String> weatherLoadingIds;
  final Map<String, List<ReminderConfig>> configsByPartner;
  final ValueChanged<Partner> onChatPartner;
  final ValueChanged<Partner> onAddReminder;
  final ValueChanged<Partner> onOpenProfile;

  @override
  State<CareGraphView> createState() => _CareGraphViewState();
}

class _CareGraphViewState extends State<CareGraphView> {
  String? _selectedPartnerId;

  Partner? get _selectedPartner {
    final selectedId = _selectedPartnerId;
    if (selectedId == null) return null;
    for (final partner in widget.partners) {
      if (partner.id == selectedId) return partner;
    }
    return null;
  }

  @override
  void didUpdateWidget(covariant CareGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedPartnerId != null && _selectedPartner == null) {
      _selectedPartnerId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedPartner;
    return AnimatedSwitcher(
      duration: TaAnimation.fast,
      switchInCurve: TaAnimation.curveOut,
      switchOutCurve: TaAnimation.curveIn,
      child: selected == null
          ? _buildOverview(context)
          : _buildSelected(context, selected),
    );
  }

  Widget _buildOverview(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const ValueKey('care-graph-overview'),
      padding: const EdgeInsets.fromLTRB(
        TaSpacing.pagePadding,
        TaSpacing.sm,
        TaSpacing.pagePadding,
        TaSpacing.xl,
      ),
      children: [
        Text(
          '关心图谱',
          style: theme.textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: TaSpacing.xxs),
        Text(
          '轻点一个人，看看你们之间积累的关心。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: TaSpacing.md),
        Stack(
          children: [
            _GraphCanvas(
              partners: widget.partners,
              weatherByPartner: widget.weatherByPartner,
              weatherLoadingIds: widget.weatherLoadingIds,
              configsByPartner: widget.configsByPartner,
              onPartnerTap: (partner) {
                setState(() => _selectedPartnerId = partner.id);
              },
            ),
            Positioned(
              top: TaSpacing.xs,
              right: TaSpacing.xs,
              child: Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: '分享关心图谱',
                    onPressed: _openSharePreview,
                    icon: const Icon(Icons.ios_share_rounded),
                  ),
                  const SizedBox(width: TaSpacing.xxs),
                  IconButton.filledTonal(
                    tooltip: '全屏查看图谱',
                    onPressed: _openFullscreen,
                    icon: const Icon(Icons.fullscreen_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openFullscreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('关心图谱'),
            actions: [
              IconButton(
                tooltip: '分享关心图谱',
                onPressed: _openSharePreview,
                icon: const Icon(Icons.ios_share_rounded),
              ),
            ],
          ),
          body: InteractiveViewer(
            minScale: 0.65,
            maxScale: 2.6,
            boundaryMargin: const EdgeInsets.all(180),
            child: SizedBox(
              width: 760,
              height: 760,
              child: Center(
                child: SizedBox(
                  width: 680,
                  child: _GraphCanvas(
                    height: 680,
                    partners: widget.partners,
                    weatherByPartner: widget.weatherByPartner,
                    weatherLoadingIds: widget.weatherLoadingIds,
                    configsByPartner: widget.configsByPartner,
                    onPartnerTap: (partner) {
                      Navigator.of(context).pop();
                      setState(() => _selectedPartnerId = partner.id);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openSharePreview() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.92,
        child: CareGraphShareSheet(
          partners: widget.partners,
          reminderCount: widget.configsByPartner.values
              .expand((configs) => configs)
              .where((config) => config.enabled)
              .length,
        ),
      ),
    );
  }

  Widget _buildSelected(BuildContext context, Partner partner) {
    final theme = Theme.of(context);
    final weather = widget.weatherByPartner[partner.id];
    final weatherLabel = CareGraphPartnerMeta.weatherLabel(
      weather,
      loading: widget.weatherLoadingIds.contains(partner.id),
    );
    final localTime = CareGraphPartnerMeta.localTime(partner, DateTime.now());
    final activeReminders =
        widget.configsByPartner[partner.id]
            ?.where((item) => item.enabled)
            .length ??
        0;

    return ListView(
      key: ValueKey('care-graph-selected-${partner.id}'),
      padding: const EdgeInsets.fromLTRB(
        TaSpacing.pagePadding,
        TaSpacing.sm,
        TaSpacing.pagePadding,
        TaSpacing.xl,
      ),
      children: [
        Row(
          children: [
            IconButton.filledTonal(
              tooltip: '返回图谱总览',
              onPressed: () => setState(() => _selectedPartnerId = null),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: TaSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '选中${partner.nickname}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '天气、提醒和小念记住的信息都汇总在这里',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: TaSpacing.md),
        _SelectedPartnerHero(
          partner: partner,
          localTime: localTime,
          weatherLabel: weatherLabel,
          reminderCount: activeReminders,
        ),
        const SizedBox(height: TaSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => widget.onChatPartner(partner),
            icon: const Icon(Icons.chat_bubble_rounded),
            label: const Text('聊聊 Ta'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              textStyle: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(TaRadius.md),
              ),
            ),
          ),
        ),
        const SizedBox(height: TaSpacing.md),
        Container(
          padding: TaSpacing.cardInnerLarge,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: TaRadius.borderLg,
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
            boxShadow: theme.brightness == Brightness.light
                ? TaShadows.sm
                : const <BoxShadow>[],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _DetailRow(
                      icon: Icons.link_rounded,
                      label: '关系',
                      value: partner.typeLabel,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  IconButton(
                    tooltip: '编辑关系',
                    onPressed: () => widget.onOpenProfile(partner),
                    icon: const Icon(Icons.edit_outlined, size: 19),
                  ),
                ],
              ),
              const SizedBox(height: TaSpacing.sm),
              _DetailRow(
                icon: Icons.place_outlined,
                label: '所在地区',
                value: partner.city?.trim().isNotEmpty == true
                    ? partner.city!.trim()
                    : '还没有记录',
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(height: TaSpacing.sm),
              _DetailRow(
                icon: Icons.schedule_rounded,
                label: '当地时间',
                value: localTime,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(height: TaSpacing.sm),
              _DetailRow(
                icon: Icons.cloud_outlined,
                label: '当前天气',
                value: weatherLabel,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(height: TaSpacing.sm),
              _DetailRow(
                icon: Icons.notifications_active_outlined,
                label: '有效提醒',
                value: '$activeReminders 个',
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(height: TaSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => widget.onAddReminder(partner),
                      icon: const Icon(Icons.add_alert_outlined, size: 18),
                      label: const Text('添加提醒'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                  const SizedBox(width: TaSpacing.sm),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => widget.onOpenProfile(partner),
                      icon: const Icon(Icons.person_outline_rounded, size: 18),
                      label: const Text('查看档案'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class CareGraphPartnerMeta {
  const CareGraphPartnerMeta._();

  static String localTime(Partner partner, DateTime now) {
    final timezoneId = partner.timezoneId?.trim();
    if (timezoneId?.isNotEmpty == true) {
      try {
        final location = tz.getLocation(timezoneId!);
        final local = tz.TZDateTime.from(now.toUtc(), location);
        return _formatClock(local.hour, local.minute);
      } on tz.LocationNotFoundException {
        // Fall through to the location approximation used by legacy data.
      } on StateError {
        // The timezone database may not yet be ready during early rendering.
      }
    }

    final longitude = partner.longitude;
    if (longitude != null) {
      final local = now.toUtc().add(Duration(hours: (longitude / 15).round()));
      return _formatClock(local.hour, local.minute);
    }
    return '时间待确认';
  }

  static String weatherLabel(
    FullWeatherResult? weather, {
    required bool loading,
  }) {
    if (weather != null) {
      return '${weather.current.text} · ${weather.current.temp}°C';
    }
    return loading ? '天气更新中' : '天气待更新';
  }

  static String _formatClock(int hour, int minute) {
    return '当地 ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }
}

class _GraphCanvas extends StatelessWidget {
  const _GraphCanvas({
    required this.partners,
    required this.weatherByPartner,
    required this.weatherLoadingIds,
    required this.configsByPartner,
    required this.onPartnerTap,
    this.height = 430,
  });

  final List<Partner> partners;
  final Map<String, FullWeatherResult?> weatherByPartner;
  final Set<String> weatherLoadingIds;
  final Map<String, List<ReminderConfig>> configsByPartner;
  final ValueChanged<Partner> onPartnerTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.42),
            theme.colorScheme.surface,
            theme.colorScheme.tertiaryContainer.withValues(alpha: 0.32),
          ],
          stops: const [0, 0.58, 1],
        ),
        borderRadius: TaRadius.borderLg,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final center = Offset(size.width / 2, size.height / 2 - 8);
          final positions = _nodePositions(size, partners.length);

          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _CareGraphLinePainter(
                    center: center,
                    partnerCenters: positions
                        .map((position) => position + const Offset(56, 34))
                        .toList(growable: false),
                    relationships: partners
                        .map((partner) => partner.typeLabel)
                        .toList(growable: false),
                    color: theme.colorScheme.outline.withValues(alpha: 0.38),
                  ),
                ),
              ),
              Positioned(
                left: center.dx - 36,
                top: center.dy - 36,
                child: Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.primary.withValues(alpha: 0.78),
                      ],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.24,
                        ),
                        blurRadius: 22,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Text(
                    '我',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              for (var index = 0; index < partners.length; index++)
                Positioned(
                  left: positions[index].dx,
                  top: positions[index].dy,
                  child: _PartnerGraphNode(
                    partner: partners[index],
                    weather: weatherByPartner[partners[index].id],
                    weatherLoading: weatherLoadingIds.contains(
                      partners[index].id,
                    ),
                    colorIndex: index,
                    reminderCount:
                        configsByPartner[partners[index].id]
                            ?.where((config) => config.enabled)
                            .length ??
                        0,
                    onTap: () => onPartnerTap(partners[index]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  List<Offset> _nodePositions(Size size, int count) {
    if (count == 0) return const [];
    final center = Offset(size.width / 2, size.height / 2 - 8);
    final horizontalRadius = math.min(size.width * 0.34, 128.0);
    final verticalRadius = math.min(size.height * 0.31, 126.0);
    return List.generate(count, (index) {
      final angle = -math.pi / 2 + (2 * math.pi * index / count);
      final ringMultiplier = count > 6 && index.isOdd ? 0.72 : 1.0;
      final nodeCenter = Offset(
        center.dx + math.cos(angle) * horizontalRadius * ringMultiplier,
        center.dy + math.sin(angle) * verticalRadius * ringMultiplier,
      );
      return Offset(
        (nodeCenter.dx - 56).clamp(4.0, size.width - 116),
        (nodeCenter.dy - 34).clamp(8.0, size.height - 126),
      );
    });
  }
}

class _PartnerGraphNode extends StatelessWidget {
  const _PartnerGraphNode({
    required this.partner,
    required this.weather,
    required this.weatherLoading,
    required this.colorIndex,
    required this.reminderCount,
    required this.onTap,
  });

  final Partner partner;
  final FullWeatherResult? weather;
  final bool weatherLoading;
  final int colorIndex;
  final int reminderCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = [
      theme.colorScheme.secondaryContainer,
      theme.colorScheme.tertiaryContainer,
      theme.colorScheme.primaryContainer,
    ];
    final paletteIndex = colorIndex % palette.length;
    final nodeColor = palette[paletteIndex];
    final onNodeColor = switch (paletteIndex) {
      1 => theme.colorScheme.onTertiaryContainer,
      2 => theme.colorScheme.onPrimaryContainer,
      _ => theme.colorScheme.onSecondaryContainer,
    };
    final city = partner.city?.trim().isNotEmpty == true
        ? partner.city!.trim()
        : '地点待确认';
    final time = CareGraphPartnerMeta.localTime(partner, DateTime.now());
    final weatherText = CareGraphPartnerMeta.weatherLabel(
      weather,
      loading: weatherLoading,
    );
    final informationScore =
        <Object?>[partner.city, partner.timezoneId, partner.note]
            .where(
              (value) => value != null && value.toString().trim().isNotEmpty,
            )
            .length;
    final nodeSize =
        (64.0 + math.min(18, informationScore * 3 + reminderCount * 3));

    return Semantics(
      button: true,
      label: '查看${partner.nickname}的关心信息',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 112,
          height: 138,
          child: Column(
            children: [
              AnimatedContainer(
                duration: TaAnimation.fast,
                width: nodeSize,
                height: nodeSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: nodeColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surface.withValues(alpha: 0.9),
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: nodeColor.withValues(alpha: 0.34),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Text(
                  partner.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: onNodeColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '$city · ${time.replaceFirst('当地 ', '')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.78,
                  ),
                  letterSpacing: 0,
                ),
              ),
              Text(
                weatherText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.72,
                  ),
                  letterSpacing: 0,
                ),
              ),
              Text(
                '${partner.typeLabel} · $reminderCount 个提醒',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.68,
                  ),
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedPartnerHero extends StatelessWidget {
  const _SelectedPartnerHero({
    required this.partner,
    required this.localTime,
    required this.weatherLabel,
    required this.reminderCount,
  });

  final Partner partner;
  final String localTime;
  final String weatherLabel;
  final int reminderCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TaSpacing.lg,
        vertical: TaSpacing.xl,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.secondaryContainer.withValues(alpha: 0.78),
            theme.colorScheme.primaryContainer.withValues(alpha: 0.52),
            theme.colorScheme.tertiaryContainer.withValues(alpha: 0.46),
          ],
        ),
        borderRadius: TaRadius.borderLg,
      ),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondary,
              shape: BoxShape.circle,
              border: Border.all(color: theme.colorScheme.surface, width: 4),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.28),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Text(
              partner.nickname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: TaSpacing.md),
          Text(
            '${partner.nickname} · ${partner.typeLabel} · $reminderCount 个提醒',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: TaSpacing.xs),
          Text(
            '${partner.city ?? '地点待确认'} · $localTime\n$weatherLabel',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(TaRadius.sm),
          ),
          child: Icon(icon, color: color, size: TaSizes.iconSm),
        ),
        const SizedBox(width: TaSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CareGraphLinePainter extends CustomPainter {
  const _CareGraphLinePainter({
    required this.center,
    required this.partnerCenters,
    required this.color,
    required this.relationships,
  });

  final Offset center;
  final List<Offset> partnerCenters;
  final Color color;
  final List<String> relationships;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < partnerCenters.length; index++) {
      final partnerCenter = partnerCenters[index];
      canvas.drawLine(center, partnerCenter, paint);
      if (index >= relationships.length) continue;
      final labelPosition = Offset.lerp(center, partnerCenter, 0.48)!;
      final painter = TextPainter(
        text: TextSpan(
          text: relationships[index],
          style: TextStyle(color: color, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        labelPosition - Offset(painter.width / 2, painter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CareGraphLinePainter oldDelegate) {
    if (oldDelegate.center != center ||
        oldDelegate.color != color ||
        oldDelegate.relationships.length != relationships.length) {
      return true;
    }
    if (oldDelegate.partnerCenters.length != partnerCenters.length) return true;
    for (var index = 0; index < partnerCenters.length; index++) {
      if (oldDelegate.partnerCenters[index] != partnerCenters[index]) {
        return true;
      }
    }
    return false;
  }
}
