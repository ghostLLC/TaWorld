import 'package:flutter_test/flutter_test.dart';
import 'package:taworld/presentation/screens/home/care_graph_layout.dart';

void main() {
  test(
    '1 to 64 people stay separated and additions preserve existing coordinates',
    () {
      var positions = <String, Offset>{};
      for (var count = 1; count <= 64; count++) {
        final next = CareGraphLayout.arrange([
          for (var i = 0; i < count; i++) 'p$i',
        ], positions);
        for (final entry in positions.entries) {
          expect(next[entry.key], entry.value);
        }
        for (final entry in next.entries) {
          expect(
            CareGraphLayout.overlaps(
              entry.value,
              next.entries.where((e) => e.key != entry.key).map((e) => e.value),
            ),
            isFalse,
          );
        }
        positions = next;
      }
      final reversed = CareGraphLayout.arrange(
        positions.keys.toList().reversed.toList(),
        positions,
      );
      expect(reversed, positions);
    },
  );
  test('dragging onto another person settles into a free position', () {
    final occupied = [const Offset(190, 0), const Offset(190, 150)];
    final settled = CareGraphLayout.settle(const Offset(190, 0), occupied);
    expect(CareGraphLayout.overlaps(settled, occupied), isFalse);
  });
}
