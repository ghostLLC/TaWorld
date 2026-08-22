import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/design_tokens.dart';
import '../../../data/models/partner.dart';

class CareGraphSharePoster extends StatelessWidget {
  const CareGraphSharePoster({
    super.key,
    required this.partners,
    required this.reminderCount,
  });

  final List<Partner> partners;
  final int reminderCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visiblePartners = partners.take(6).toList(growable: false);
    return Container(
      width: 360,
      height: 520,
      padding: const EdgeInsets.all(TaSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.surface,
            theme.colorScheme.primaryContainer.withValues(alpha: 0.58),
            theme.colorScheme.tertiaryContainer.withValues(alpha: 0.42),
          ],
        ),
        borderRadius: TaRadius.borderLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '我的关心图谱',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: TaSpacing.xxs),
          Text(
            '看见彼此，也记得每一份牵挂',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: TaSpacing.lg),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(TaSpacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.72),
                borderRadius: TaRadius.borderLg,
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.55,
                  ),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: TaGradients.primary(theme.brightness),
                      boxShadow: TaShadows.md,
                    ),
                    child: Text(
                      '我',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: TaSpacing.md),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: TaSpacing.sm,
                    runSpacing: TaSpacing.sm,
                    children: [
                      for (
                        var index = 0;
                        index < visiblePartners.length;
                        index++
                      )
                        _PosterPersonNode(
                          partner: visiblePartners[index],
                          color: switch (index % 3) {
                            1 => theme.colorScheme.tertiaryContainer,
                            2 => theme.colorScheme.primaryContainer,
                            _ => theme.colorScheme.secondaryContainer,
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: TaSpacing.md),
                  Text(
                    '${partners.length} 位关心的人 · $reminderCount 个有效提醒',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: TaSpacing.md),
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(TaRadius.sm),
                ),
                child: QrImageView(
                  data: 'https://github.com/ghostLLC/TaWorld',
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: TaSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TaWorld',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '让每一次关心，都被温柔记住',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PosterPersonNode extends StatelessWidget {
  const _PosterPersonNode({required this.partner, required this.color});

  final Partner partner;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 78,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Text(
              partner.nickname.characters.take(3).toString(),
              maxLines: 1,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${partner.typeLabel}${partner.city == null ? '' : ' · ${partner.city}'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
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

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary =
          _posterKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('海报尚未准备好');
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('海报生成失败');
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/taworld_care_graph.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await Share.shareXFiles([XFile(file.path)], text: '我的 TaWorld 关心图谱');
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
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: TaSpacing.sm),
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
                label: Text(_sharing ? '正在生成' : '分享海报'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
