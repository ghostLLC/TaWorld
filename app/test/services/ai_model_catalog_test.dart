import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/services/ai_model_catalog.dart';

void main() {
  test('uses Flash for text and the dedicated experimental vision model', () {
    expect(AiModelCatalog.primary, 'deepseek-v4-flash');
    expect(AiModelCatalog.vision, 'deepseek-v4-flash-vision-exp');
    expect(AiModelCatalog.pro, 'deepseek-v4-pro');
  });
}
