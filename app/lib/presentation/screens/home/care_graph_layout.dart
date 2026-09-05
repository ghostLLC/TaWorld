import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// World coordinates relative to the centre. Existing placements never depend
/// on the current number of people or on database list order.
abstract final class CareGraphLayout {
  static Map<String, Offset> arrange(
    List<String> ids,
    Map<String, Offset> saved,
  ) {
    final result = <String, Offset>{};
    for (final id in ids) {
      final position = saved[id];
      if (position != null &&
          position.dx.isFinite &&
          position.dy.isFinite &&
          position.distance < 6000 &&
          !overlaps(position, result.values)) {
        result[id] = position;
      }
    }
    var slot = 0;
    for (final id in ids.where((id) => !result.containsKey(id))) {
      Offset candidate;
      do {
        candidate = positionForSlot(slot++);
      } while (overlaps(candidate, result.values));
      result[id] = candidate;
    }
    return result;
  }

  static Offset positionForSlot(int index) {
    var ring = 1;
    while (index >= ring * 8) {
      index -= ring * 8;
      ring++;
    }
    final angle = -math.pi / 2 + 2 * math.pi * index / (ring * 8);
    final radius = ring * 190.0;
    return Offset(math.cos(angle) * radius, math.sin(angle) * radius);
  }

  static bool overlaps(Offset point, Iterable<Offset> occupied) {
    if (point.dx.abs() < 112 && point.dy.abs() < 118) return true;
    return occupied.any(
      (other) =>
          (point.dx - other.dx).abs() < 118 &&
          (point.dy - other.dy).abs() < 126,
    );
  }

  static Offset settle(Offset point, Iterable<Offset> occupied) {
    if (!overlaps(point, occupied)) return point;
    for (var distance = 16.0; distance < 2000; distance += 16) {
      for (var direction = 0; direction < 24; direction++) {
        final angle = direction * math.pi / 12;
        final candidate =
            point + Offset(math.cos(angle), math.sin(angle)) * distance;
        if (!overlaps(candidate, occupied)) return candidate;
      }
    }
    return point;
  }

  static Size extent(Iterable<Offset> points) {
    var x = 260.0, y = 280.0;
    for (final point in points) {
      x = math.max(x, point.dx.abs() + 80);
      y = math.max(y, point.dy.abs() + 105);
    }
    return Size(x * 2, y * 2);
  }
}
