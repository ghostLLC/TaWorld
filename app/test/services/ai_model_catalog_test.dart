import 'package:flutter_test/flutter_test.dart';

import 'package:taworld/services/ai_model_catalog.dart';

void main() {
  test('uses the multimodal Flash model as the single primary route', () {
    expect(AiModelCatalog.primary, 'deepseek-flash');
  });
}
