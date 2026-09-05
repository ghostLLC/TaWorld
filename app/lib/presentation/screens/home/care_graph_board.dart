import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import '../../../data/local/database_helper.dart';
import 'care_graph_layout.dart';
import 'care_graph_scene.dart';

class CareGraphBoard extends StatefulWidget {
  const CareGraphBoard({
    super.key,
    required this.nodes,
    required this.allIds,
    required this.onSelect,
    this.selectedId,
    this.immersive = false,
  });
  final List<CareGraphNodeData> nodes;
  final List<String> allIds;
  final ValueChanged<String> onSelect;
  final String? selectedId;
  final bool immersive;
  @override
  State<CareGraphBoard> createState() => CareGraphBoardState();
}

class CareGraphBoardState extends State<CareGraphBoard> {
  final _transform = TransformationController();
  Map<String, Offset> _positions = {};
  Size? _viewport;
  String? _dragging;
  Offset? _dragStart, _dragOrigin;
  Size? _dragExtent;
  @override
  void initState() {
    super.initState();
    _positions = CareGraphLayout.arrange(widget.allIds, {});
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await DatabaseHelper.database;
      final rows = await db.query('graph_positions');
      final saved = {
        for (final row in rows)
          row['person_id'] as String: Offset(
            (row['x'] as num).toDouble(),
            (row['y'] as num).toDouble(),
          ),
      };
      if (!mounted) return;
      setState(
        () => _positions = CareGraphLayout.arrange(widget.allIds, saved),
      );
      fit();
      await _save();
    } catch (_) {
      /* The graph remains usable if position storage is unavailable. */
    }
  }

  Future<void> _save() async {
    final db = await DatabaseHelper.database;
    await db.transaction((tx) async {
      for (final entry in _positions.entries) {
        // A person can be removed while the graph is open.
        if ((await tx.query(
          'partners',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [entry.key],
        )).isEmpty) {
          continue;
        }
        await tx.insert('graph_positions', {
          'person_id': entry.key,
          'x': entry.value.dx,
          'y': entry.value.dy,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  @override
  void didUpdateWidget(CareGraphBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.allIds.join('|') != oldWidget.allIds.join('|')) {
      _positions = CareGraphLayout.arrange(widget.allIds, _positions);
      _save().catchError((_) {});
    }
  }

  Size get _size => _dragExtent ?? CareGraphLayout.extent(_positions.values);
  void fit() {
    final viewport = _viewport;
    if (viewport == null) return;
    final size = _size;
    final scale =
        math.min(viewport.width / size.width, viewport.height / size.height) *
        0.96;
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        (viewport.width - size.width * scale) / 2,
        (viewport.height - size.height * scale) / 2,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
  }

  void focus(String id) {
    final position = _positions[id], viewport = _viewport;
    if (position == null || viewport == null) return;
    final center = Offset(_size.width / 2, _size.height / 2) + position;
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        viewport.width / 2 - center.dx,
        viewport.height / 2 - center.dy,
        0,
        1,
      );
  }

  void _start(String id, Offset point) {
    HapticFeedback.selectionClick();
    setState(() {
      _dragExtent = _size;
      _dragging = id;
      _dragStart = point;
      _dragOrigin = _positions[id];
    });
  }

  void _move(String id, Offset point) {
    if (_dragging != id || _dragOrigin == null) return;
    final scale = _transform.value.getMaxScaleOnAxis();
    final moved = _dragOrigin! + (point - _dragStart!) / scale;
    setState(
      () => _positions[id] = Offset(
        moved.dx.clamp(-_size.width / 2 + 70, _size.width / 2 - 70),
        moved.dy.clamp(-_size.height / 2 + 70, _size.height / 2 - 100),
      ),
    );
  }

  Future<void> _end(String id) async {
    final others = _positions.entries
        .where((e) => e.key != id)
        .map((e) => e.value);
    setState(() {
      _positions[id] = CareGraphLayout.settle(_positions[id]!, others);
      _dragging = null;
      _dragExtent = null;
    });
    try {
      await _save();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('位置暂未保存，可稍后重试')));
      }
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = Size(constraints.maxWidth, constraints.maxHeight);
      if (_viewport != viewport) {
        _viewport = viewport;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) fit();
        });
      }
      final size = _size;
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.immersive ? 0 : 24),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.28),
                      Theme.of(context).colorScheme.surface,
                      Theme.of(
                        context,
                      ).colorScheme.tertiaryContainer.withValues(alpha: 0.25),
                    ],
                  ),
                ),
              ),
            ),
            InteractiveViewer(
              key: Key(
                widget.immersive
                    ? 'care-graph-fullscreen-interactive'
                    : 'care-graph-interactive',
              ),
              transformationController: _transform,
              constrained: false,
              minScale: 0.08,
              maxScale: 2.5,
              panEnabled: _dragging == null,
              scaleEnabled: _dragging == null,
              boundaryMargin: const EdgeInsets.all(2000),
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: CareGraphScene(
                  nodes: widget.nodes,
                  selectedNodeId: widget.selectedId,
                  showBackground: false,
                  positions: {
                    for (final e in _positions.entries)
                      e.key: e.value + Offset(size.width / 2, size.height / 2),
                  },
                  onNodeTap: (node) => widget.onSelect(node.id),
                  onDragStart: (node, p) => _start(node.id, p),
                  onDragMove: (node, p) => _move(node.id, p),
                  onDragEnd: (node) => _end(node.id),
                ),
              ),
            ),
            if (!widget.immersive)
              Positioned(
                right: 8,
                bottom: 8,
                child: IconButton.filledTonal(
                  tooltip: '适应全部人物',
                  onPressed: fit,
                  icon: const Icon(Icons.center_focus_strong_rounded),
                ),
              ),
          ],
        ),
      );
    },
  );
}
