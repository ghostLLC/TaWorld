import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../data/models/partner.dart';
import '../../../data/models/reminder_config.dart';
import '../../../services/weather_service.dart';
import 'care_graph_scene.dart';
import 'care_graph_board.dart';
import 'care_graph_share_poster.dart';

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
    this.fullscreen = false,
  });
  final List<Partner> partners;
  final Map<String, FullWeatherResult?> weatherByPartner;
  final Set<String> weatherLoadingIds;
  final Map<String, List<ReminderConfig>> configsByPartner;
  final ValueChanged<Partner> onChatPartner, onAddReminder, onOpenProfile;
  final bool fullscreen;
  @override
  State<CareGraphView> createState() => _CareGraphViewState();
}

class _CareGraphViewState extends State<CareGraphView> {
  final _board = GlobalKey<CareGraphBoardState>();
  final _search = TextEditingController();
  String? _selectedId;
  String _group = 'all';
  bool _searching = false;
  Timer? _clock;
  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _search.dispose();
    super.dispose();
  }

  List<Partner> get _ordered => [...widget.partners]
    ..sort((a, b) {
      final created = a.createdAt.compareTo(b.createdAt);
      return created == 0 ? a.id.compareTo(b.id) : created;
    });
  Partner? get _selected =>
      widget.partners.where((p) => p.id == _selectedId).firstOrNull;
  void _select(String id) {
    HapticFeedback.selectionClick();
    setState(() => _selectedId = id);
  }

  void _share() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: CareGraphShareSheet(
        partners: _ordered,
        reminderCount: widget.configsByPartner.values
            .expand((c) => c)
            .where((c) => c.enabled)
            .length,
      ),
    ),
  );
  void _fullscreen() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        body: CareGraphView(
          partners: widget.partners,
          weatherByPartner: widget.weatherByPartner,
          weatherLoadingIds: widget.weatherLoadingIds,
          configsByPartner: widget.configsByPartner,
          fullscreen: true,
          onChatPartner: (p) {
            Navigator.of(context).pop();
            widget.onChatPartner(p);
          },
          onAddReminder: (p) {
            Navigator.of(context).pop();
            widget.onAddReminder(p);
          },
          onOpenProfile: (p) {
            Navigator.of(context).pop();
            widget.onOpenProfile(p);
          },
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final ordered = _ordered;
    final query = _search.text.trim().toLowerCase();
    final visible = ordered
        .where(
          (p) =>
              (_group == 'all' || p.type == _group) &&
              (query.isEmpty ||
                  '${p.nickname} ${p.city ?? ''} ${p.typeLabel}'
                      .toLowerCase()
                      .contains(query)),
        )
        .toList();
    final now = DateTime.now();
    final nodes = [
      for (final p in visible)
        CareGraphNodeData(
          id: p.id,
          label: p.nickname,
          relationship: p.typeLabel,
          city: p.city?.isNotEmpty == true ? p.city! : '地点待确认',
          localTime: CareGraphPartnerMeta.localTime(
            p,
            now,
          ).replaceFirst('当地 ', ''),
          weather: CareGraphPartnerMeta.weatherLabel(
            widget.weatherByPartner[p.id],
            loading: widget.weatherLoadingIds.contains(p.id),
          ),
          reminderCount:
              widget.configsByPartner[p.id]?.where((c) => c.enabled).length ??
              0,
        ),
    ];
    final selected = _selected;
    final board = CareGraphBoard(
      key: _board,
      nodes: nodes,
      allIds: ordered.map((p) => p.id).toList(),
      onSelect: _select,
      selectedId: _selectedId,
      immersive: widget.fullscreen,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.fullscreen)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '关心图谱',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${ordered.length} 位牵挂的人，在你的世界里',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '搜索人物',
                      onPressed: () => setState(() => _searching = !_searching),
                      icon: const Icon(Icons.search_rounded),
                    ),
                    IconButton(
                      tooltip: '分享关心图谱',
                      onPressed: _share,
                      icon: const Icon(Icons.ios_share_rounded),
                    ),
                    IconButton(
                      tooltip: '全屏查看图谱',
                      onPressed: _fullscreen,
                      icon: const Icon(Icons.fullscreen_rounded),
                    ),
                  ],
                ),
                if (_searching)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextField(
                      controller: _search,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: '搜索名字、关系或城市',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          tooltip: '清除搜索',
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final group in [
                        'all',
                        ...ordered.map((p) => p.type).toSet(),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text(
                              group == 'all'
                                  ? '全部'
                                  : ordered
                                        .firstWhere((p) => p.type == group)
                                        .typeLabel,
                            ),
                            selected: _group == group,
                            onSelected: (_) => setState(() => _group = group),
                          ),
                        ),
                    ],
                  ),
                ),
                if (query.isNotEmpty && visible.isNotEmpty)
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final p in visible)
                          TextButton(
                            onPressed: () {
                              _select(p.id);
                              _board.currentState?.focus(p.id);
                            },
                            child: Text(
                              '${p.nickname} · ${p.city ?? p.typeLabel}',
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.fullscreen ? 0 : 12,
                  ),
                  child: board,
                ),
              ),
              if (visible.isEmpty)
                Center(
                  child: Text('没有匹配的人物', style: theme.textTheme.bodyLarge),
                ),
              if (widget.fullscreen)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: IconButton.filledTonal(
                      key: const Key('care-graph-fullscreen-close'),
                      tooltip: '退出全屏图谱',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ),
              if (selected != null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 520,
                          maxHeight: MediaQuery.sizeOf(context).height * 0.36,
                        ),
                        child: SingleChildScrollView(
                          child: _selectionCard(selected, theme),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (!widget.fullscreen)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              '点选查看 · 双指缩放 · 长按拖动',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _selectionCard(Partner person, ThemeData theme) {
    final count =
        widget.configsByPartner[person.id]?.where((c) => c.enabled).length ?? 0;
    return Material(
      key: ValueKey('care-graph-selected-${person.id}'),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${person.nickname} · ${person.typeLabel}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '收起人物卡片',
                  onPressed: () => setState(() => _selectedId = null),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Text(
              '${person.city ?? '地点待确认'} · ${CareGraphPartnerMeta.localTime(person, DateTime.now())}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 3),
            Text(
              '${CareGraphPartnerMeta.weatherLabel(widget.weatherByPartner[person.id], loading: widget.weatherLoadingIds.contains(person.id))} · $count 个提醒',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                  ),
                  onPressed: () => widget.onChatPartner(person),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: const Text('聊聊Ta'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: () => widget.onAddReminder(person),
                  icon: const Icon(Icons.add_alert_outlined, size: 18),
                  label: const Text('提醒'),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: () => widget.onOpenProfile(person),
                  child: const Text('档案'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CareGraphPartnerMeta {
  const CareGraphPartnerMeta._();

  static String localTime(Partner partner, DateTime now) {
    final timezoneId = partner.timezoneId?.trim();
    if (partner.timezoneConfirmed && timezoneId?.isNotEmpty == true) {
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
