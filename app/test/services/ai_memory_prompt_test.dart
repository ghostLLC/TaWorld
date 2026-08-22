import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taworld/services/ai_memory_service.dart';

import '../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await openTestDatabase();
  });

  tearDown(closeTestDatabase);

  test(
    'state-changing tool results force a deterministic final reply',
    () async {
      final prompt = await AiMemoryService.buildSystemPrompt();

      expect(prompt, contains('结构化结果里的 status 和 verified'));
      expect(prompt, contains('最终回复必须使用已完成、部分完成或未完成的结果表述'));
      expect(prompt, contains('绝不能以“稍等”“我这就弄”“马上帮你”等未来时态结束'));
    },
  );

  test('compatible multi-select choices offer a concise all option', () async {
    final prompt = await AiMemoryService.buildSystemPrompt();

    expect(prompt, contains('可以同时选择多个兼容选项'));
    expect(prompt, contains('都要'));
    expect(prompt, contains('关系类型、时间基准这类互斥问题不要添加“都要”'));
  });
}
