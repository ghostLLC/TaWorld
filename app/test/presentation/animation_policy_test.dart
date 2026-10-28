import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/app/design_tokens.dart';

void main() {
  test('staggered entrance delays are bounded', () {
    expect(TaAnimation.stagger(0, stepMilliseconds: 80), Duration.zero);
    expect(
      TaAnimation.stagger(2, stepMilliseconds: 80),
      const Duration(milliseconds: 160),
    );
    expect(
      TaAnimation.stagger(50, stepMilliseconds: 80),
      const Duration(milliseconds: 300),
    );
  });
}
