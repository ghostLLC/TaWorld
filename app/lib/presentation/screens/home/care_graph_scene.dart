import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';

/// 关心图谱的统一节点数据。
///
/// App 内图谱与分享海报都使用同一份几何布局和连线绘制，避免两个出口
/// 分别维护后出现「只有节点、没有连线」的视觉差异。
class CareGraphNodeData {
  const CareGraphNodeData({
    required this.id,
    required this.label,
    required this.relationship,
    required this.city,
    required this.localTime,
    required this.weather,
    required this.reminderCount,
    this.informationScore = 0,
  });

  final String id;
  final String label;
  final String relationship;
  final String city;
  final String localTime;
  final String weather;
  final int reminderCount;
  final int informationScore;
}

enum CareGraphSceneDensity { regular, immersive, poster }

class CareGraphScene extends StatelessWidget {
  const CareGraphScene({
    super.key,
    required this.nodes,
    this.selectedNodeId,
    this.onNodeTap,
    this.density = CareGraphSceneDensity.regular,
    this.showBackground = true,
    this.positions,
    this.onDragStart,
    this.onDragMove,
    this.onDragEnd,
  });

  final List<CareGraphNodeData> nodes;
  final String? selectedNodeId;
  final ValueChanged<CareGraphNodeData>? onNodeTap;
  final CareGraphSceneDensity density;
  final bool showBackground;
  final Map<String, Offset>? positions;
  final void Function(CareGraphNodeData node, Offset global)? onDragStart,
      onDragMove;
  final ValueChanged<CareGraphNodeData>? onDragEnd;

  bool get _isImmersive => density == CareGraphSceneDensity.immersive;
  bool get _isPoster => density == CareGraphSceneDensity.poster;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = switch (density) {
      CareGraphSceneDensity.regular => TaRadius.borderLg,
      CareGraphSceneDensity.immersive => BorderRadius.zero,
      CareGraphSceneDensity.poster => TaRadius.borderLg,
    };

    final scene = LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final center = Offset(size.width / 2, size.height / 2);
        final defaults = _nodeCenters(size, nodes.length);
        final centers = [
          for (var i = 0; i < nodes.length; i++)
            positions?[nodes[i].id] ?? defaults[i],
        ];
        final lineColor = _isPoster
            ? scheme.onSurface.withValues(alpha: 0.42)
            : scheme.outline.withValues(alpha: _isImmersive ? 0.48 : 0.34);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                key: const Key('care-graph-edges'),
                painter: CareGraphEdgePainter(
                  center: center,
                  nodeCenters: centers,
                  relationships: nodes
                      .map((node) => node.relationship)
                      .toList(growable: false),
                  lineColor: lineColor,
                  labelColor: _isPoster
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                  labelBackground: showBackground
                      ? scheme.surface.withValues(alpha: 0.82)
                      : scheme.surface.withValues(alpha: 0.62),
                  labelFontSize: _isPoster ? 11 : 10,
                ),
              ),
            ),
            Positioned(
              left: center.dx - _centerNodeSize / 2,
              top: center.dy - _centerNodeSize / 2,
              child: _CenterNode(size: _centerNodeSize, poster: _isPoster),
            ),
            for (var index = 0; index < nodes.length; index++)
              Positioned(
                left: centers[index].dx - _nodeBoxWidth / 2,
                top: centers[index].dy - _nodeTopOffset(nodes[index]),
                child: GestureDetector(
                  onLongPressStart: onDragStart == null
                      ? null
                      : (details) =>
                            onDragStart!(nodes[index], details.globalPosition),
                  onLongPressMoveUpdate: onDragMove == null
                      ? null
                      : (details) =>
                            onDragMove!(nodes[index], details.globalPosition),
                  onLongPressEnd: onDragEnd == null
                      ? null
                      : (_) => onDragEnd!(nodes[index]),
                  child: _CareGraphNode(
                    data: nodes[index],
                    colorIndex: nodes[index].id.codeUnits.fold<int>(
                      0,
                      (a, b) => a + b,
                    ),
                    selected: selectedNodeId == nodes[index].id,
                    density: density,
                    onTap: onNodeTap == null
                        ? null
                        : () => onNodeTap!(nodes[index]),
                  ),
                ),
              ),
          ],
        );
      },
    );

    if (!showBackground) return scene;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _isPoster
              ? [
                  scheme.surface,
                  scheme.surfaceContainerHighest.withValues(alpha: 0.72),
                ]
              : [
                  scheme.primaryContainer.withValues(alpha: 0.24),
                  scheme.surface.withValues(alpha: 0.92),
                  scheme.tertiaryContainer.withValues(alpha: 0.18),
                ],
          stops: _isPoster ? null : const [0, 0.56, 1],
        ),
        borderRadius: radius,
        border: _isImmersive
            ? null
            : Border.all(color: scheme.outlineVariant.withValues(alpha: 0.38)),
      ),
      child: ClipRRect(borderRadius: radius, child: scene),
    );
  }

  double get _centerNodeSize => switch (density) {
    CareGraphSceneDensity.regular => 72,
    CareGraphSceneDensity.immersive => 82,
    CareGraphSceneDensity.poster => 68,
  };

  double get _nodeBoxWidth => switch (density) {
    CareGraphSceneDensity.regular => 112,
    CareGraphSceneDensity.immersive => 126,
    CareGraphSceneDensity.poster => 92,
  };

  double _nodeTopOffset(CareGraphNodeData node) {
    final size = _nodeDiameter(node);
    return size / 2;
  }

  double _nodeDiameter(CareGraphNodeData node) {
    final base = switch (density) {
      CareGraphSceneDensity.regular => 64.0,
      CareGraphSceneDensity.immersive => 68.0,
      CareGraphSceneDensity.poster => 54.0,
    };
    return base + (_isPoster ? 0 : 12);
  }

  List<Offset> _nodeCenters(Size size, int count) {
    if (count == 0) return const [];
    final center = Offset(size.width / 2, size.height / 2);
    final horizontalPadding = _nodeBoxWidth / 2 + 8;
    final verticalPadding = _isPoster ? 52.0 : 78.0;
    final horizontalRadius = math.max(
      0,
      math.min(
        size.width * (_isImmersive ? 0.36 : 0.34),
        size.width / 2 - horizontalPadding,
      ),
    );
    final verticalRadius = math.max(
      0,
      math.min(
        size.height * (_isImmersive ? 0.35 : 0.31),
        size.height / 2 - verticalPadding,
      ),
    );

    return List.generate(count, (index) {
      final angle = -math.pi / 2 + (2 * math.pi * index / count);
      final ringMultiplier = count > 6 && index.isOdd ? 0.72 : 1.0;
      return Offset(
        center.dx + math.cos(angle) * horizontalRadius * ringMultiplier,
        center.dy + math.sin(angle) * verticalRadius * ringMultiplier,
      );
    });
  }
}

class _CenterNode extends StatelessWidget {
  const _CenterNode({required this.size, required this.poster});

  final double size;
  final bool poster;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        shape: BoxShape.circle,
        border: Border.all(
          color: theme.colorScheme.surface.withValues(alpha: 0.88),
          width: poster ? 2 : 3,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
            blurRadius: poster ? 12 : 22,
            spreadRadius: poster ? 0 : 2,
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
    );
  }
}

class _CareGraphNode extends StatelessWidget {
  const _CareGraphNode({
    required this.data,
    required this.colorIndex,
    required this.selected,
    required this.density,
    required this.onTap,
  });

  final CareGraphNodeData data;
  final int colorIndex;
  final bool selected;
  final CareGraphSceneDensity density;
  final VoidCallback? onTap;

  bool get _isPoster => density == CareGraphSceneDensity.poster;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = [
      theme.colorScheme.secondaryContainer,
      theme.colorScheme.tertiaryContainer,
      theme.colorScheme.primaryContainer,
    ];
    final paletteIndex = colorIndex % palette.length;
    final nodeColor = _isPoster
        ? theme.colorScheme.surface
        : palette[paletteIndex];
    final onNodeColor = _isPoster
        ? theme.colorScheme.onSurface
        : switch (paletteIndex) {
            1 => theme.colorScheme.onTertiaryContainer,
            2 => theme.colorScheme.onPrimaryContainer,
            _ => theme.colorScheme.onSecondaryContainer,
          };
    final base = switch (density) {
      CareGraphSceneDensity.regular => 64.0,
      CareGraphSceneDensity.immersive => 68.0,
      CareGraphSceneDensity.poster => 54.0,
    };
    final diameter = base + (_isPoster ? 0 : 12);
    final boxWidth = switch (density) {
      CareGraphSceneDensity.regular => 112.0,
      CareGraphSceneDensity.immersive => 126.0,
      CareGraphSceneDensity.poster => 92.0,
    };

    final node = SizedBox(
      width: boxWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: TaAnimation.fast,
            width: diameter,
            height: diameter,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: nodeColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surface.withValues(alpha: 0.88),
                width: selected ? 3 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: (selected ? theme.colorScheme.primary : nodeColor)
                      .withValues(alpha: selected ? 0.3 : 0.18),
                  blurRadius: selected ? 20 : 12,
                  spreadRadius: selected ? 2 : 0,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                data.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: onNodeColor,
                  fontWeight: FontWeight.w700,
                  fontSize: _isPoster ? 12 : null,
                ),
              ),
            ),
          ),
          SizedBox(height: _isPoster ? 3 : 5),
          Text(
            _isPoster
                ? '${data.city} · ${data.relationship}'
                : '${data.city} · ${data.localTime}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 1),
              letterSpacing: 0,
              fontSize: _isPoster ? 9 : null,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return node;
    return Semantics(
      button: true,
      label:
          '查看${data.label}的关心信息，${data.relationship}，${data.city}，${data.localTime}，${data.reminderCount}个提醒',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: node,
      ),
    );
  }
}

class CareGraphEdgePainter extends CustomPainter {
  const CareGraphEdgePainter({
    required this.center,
    required this.nodeCenters,
    required this.relationships,
    required this.lineColor,
    required this.labelColor,
    required this.labelBackground,
    required this.labelFontSize,
  });

  final Offset center;
  final List<Offset> nodeCenters;
  final List<String> relationships;
  final Color lineColor;
  final Color labelColor;
  final Color labelBackground;
  final double labelFontSize;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < nodeCenters.length; index++) {
      final nodeCenter = nodeCenters[index];
      canvas.drawLine(center, nodeCenter, paint);
      if (index >= relationships.length) continue;
      final labelPosition = Offset.lerp(center, nodeCenter, 0.5)!;
      final textPainter = TextPainter(
        text: TextSpan(
          text: relationships[index],
          style: TextStyle(
            color: labelColor,
            fontSize: labelFontSize,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final rect = Rect.fromCenter(
        center: labelPosition,
        width: textPainter.width + 10,
        height: textPainter.height + 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(99)),
        Paint()..color = labelBackground,
      );
      textPainter.paint(canvas, rect.topLeft + const Offset(5, 2));
    }
  }

  @override
  bool shouldRepaint(covariant CareGraphEdgePainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.nodeCenters != nodeCenters ||
        oldDelegate.relationships != relationships ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.labelBackground != labelBackground;
  }
}
