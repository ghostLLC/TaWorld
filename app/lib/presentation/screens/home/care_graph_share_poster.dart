import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/design_tokens.dart';
import '../../../data/models/partner.dart';
import 'care_graph_scene.dart';

class CareGraphSharePoster extends StatelessWidget {
  const CareGraphSharePoster({
    super.key,
    required this.partners,
    required this.reminderCount,
    this.pageIndex = 0,
  });

  final List<Partner> partners;
  final int reminderCount;
  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visiblePartners = partners
        .skip(pageIndex * 6)
        .take(6)
        .toList(growable: false);
    final graphNodes = [
      for (final partner in visiblePartners)
        CareGraphNodeData(
          id: partner.id,
          label: partner.nickname,
          relationship: partner.typeLabel,
          city: partner.city?.trim().isNotEmpty == true
              ? partner.city!.trim()
              : '地点待确认',
          localTime: '',
          weather: '',
          reminderCount: 0,
          informationScore:
              <Object?>[partner.city, partner.timezoneId, partner.note]
                  .where((value) => value?.toString().trim().isNotEmpty == true)
                  .length,
        ),
    ];
    return Container(
      width: 360,
      height: 480,
      padding: const EdgeInsets.all(TaSpacing.sm),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.surface,
            theme.colorScheme.primaryContainer.withValues(alpha: 0.34),
            theme.colorScheme.surface,
          ],
        ),
        borderRadius: TaRadius.borderLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'TaWorld  ',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(
                  text: '让每一次关心，都被温柔记住',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            maxLines: 1,
          ),
          const SizedBox(height: TaSpacing.xs),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: CareGraphScene(
                    nodes: graphNodes,
                    density: CareGraphSceneDensity.poster,
                  ),
                ),
                Positioned(
                  left: TaSpacing.sm,
                  right: TaSpacing.sm,
                  bottom: TaSpacing.xs,
                  child: Text(
                    partners.length > 6
                        ? '共 ${partners.length} 人 · 第 ${pageIndex + 1}/${(partners.length / 6).ceil()} 页 · 本页 ${visiblePartners.length} 人'
                        : '${partners.length} 位关心的人 · $reminderCount 个有效提醒',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: TaSpacing.xs),
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(TaRadius.xs),
                ),
                child: QrImageView(
                  data: 'https://github.com/ghostLLC/TaWorld',
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: TaSpacing.xs),
              Expanded(
                child: Text(
                  '看见彼此，也记得每一份牵挂',
                  maxLines: 1,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CareGraphShareSheet extends StatefulWidget {
  const CareGraphShareSheet({
    super.key,
    required this.partners,
    required this.reminderCount,
  });

  final List<Partner> partners;
  final int reminderCount;

  @override
  State<CareGraphShareSheet> createState() => _CareGraphShareSheetState();
}

class _CareGraphShareSheetState extends State<CareGraphShareSheet> {
  final _posterKey = GlobalKey();
  bool _sharing = false;
  int _page = 0;
  int get _pages => ((widget.partners.length + 5) ~/ 6).clamp(1, 10000);

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final files = <XFile>[];
      final directory = await getTemporaryDirectory();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      for (var page = 0; page < _pages; page++) {
        if (!mounted) return;
        setState(() => _page = page);
        await WidgetsBinding.instance.endOfFrame;
        final boundary =
            _posterKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
        if (boundary == null) throw StateError('海报尚未准备好');
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('海报生成失败');
        final file = File(
          '${directory.path}/taworld_care_graph_${stamp}_$page.png',
        );
        await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
        image.dispose();
        files.add(XFile(file.path));
      }
      await Share.shareXFiles(files, text: '我的 TaWorld 关心图谱');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('海报生成失败，请稍后再试')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          TaSpacing.pagePadding,
          0,
          TaSpacing.pagePadding,
          TaSpacing.pagePadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: FittedBox(
                  child: RepaintBoundary(
                    key: _posterKey,
                    child: CareGraphSharePoster(
                      partners: widget.partners,
                      reminderCount: widget.reminderCount,
                      pageIndex: _page,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: TaSpacing.sm),
            if (_pages > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: '上一页',
                    onPressed: _sharing || _page == 0
                        ? null
                        : () => setState(() => _page--),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    '第 ${_page + 1}/$_pages 页 · 共 ${widget.partners.length} 人',
                  ),
                  IconButton(
                    tooltip: '下一页',
                    onPressed: _sharing || _page == _pages - 1
                        ? null
                        : () => setState(() => _page++),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _sharing ? null : _share,
                icon: _sharing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share_rounded),
                label: Text(
                  _sharing
                      ? '正在生成'
                      : _pages > 1
                      ? '分享全部 $_pages 页'
                      : '分享海报',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
