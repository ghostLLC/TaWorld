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

      expect(prompt, contains('status、verified 和 entity_id'));
      expect(prompt, contains('部分成功明确尚未完成的通知条件'));
      expect(prompt, contains('失败不能说成功'));
      expect(prompt, contains('不要以“稍等”“马上帮你”结束'));
      expect(prompt, contains('"timezone_confirmed":false'));
    },
  );

  test('compatible multi-select choices offer a concise all option', () async {
    final prompt = await AiMemoryService.buildSystemPrompt();

    expect(prompt, contains('执行所有兼容选项，不逐项确认'));
    expect(prompt, contains('都要'));
    expect(prompt, contains('关系类型、时间基准等互斥问题不提供“都要”'));
  });
}
