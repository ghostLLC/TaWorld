import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:taworld/data/local/database_helper.dart';
import 'package:taworld/services/ai_model_catalog.dart';
import 'package:taworld/services/image_understanding_service.dart';

void main() {
  sqfliteFfiInit();
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('taworld_image_test_');
    await DatabaseHelper.configureForTesting(
      factory: databaseFactoryFfi,
      path: p.join(root.path, 'test.db'),
    );
    await DatabaseHelper.database;
  });

  tearDown(() async {
    await DatabaseHelper.resetForTesting();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('builds the official OpenAI-compatible inline vision payload', () {
    final payload = ImageUnderstandingService.buildInlinePayload(
      bytes: Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
      mimeType: 'image/jpeg',
    );

    expect(payload['model'], AiModelCatalog.vision);
    final messages = payload['messages']! as List;
    final content = (messages.single as Map)['content'] as List;
    expect((content.last as Map)['type'], 'image_url');
    expect(
      ((content.last as Map)['image_url'] as Map)['url'],
      startsWith('data:image/jpeg;base64,'),
    );
  });

  test('parses fenced JSON and keeps concise durable facts', () {
    final result = ImageUnderstandingService.parseResponse({
      'choices': [
        {
          'message': {
            'content': '''```json
{"summary":"一张广州暴雨预警截图","facts":["小乐可能在广州","广州有暴雨预警",""]}
```''',
          },
        },
      ],
    });

    expect(result.summary, '一张广州暴雨预警截图');
    expect(result.facts, ['小乐可能在广州', '广州有暴雨预警']);
  });

  test('builds a concise memory receipt only when facts were saved', () {
    expect(
      ImageUnderstandingService.memoryReceipt(
        const ImageUnderstanding(summary: '雨天街道', facts: ['地面湿滑', '正在下雨']),
      ),
      const ImageMemoryReceipt(title: '已记住图片里的信息', detail: '已保存 2 条可用于后续关怀的事实'),
    );
    expect(
      ImageUnderstandingService.memoryReceipt(
        const ImageUnderstanding(summary: '普通风景', facts: []),
      ),
      isNull,
    );
  });

  test(
    'copies image locally and persists attachment plus long-term facts',
    () async {
      final source = File(p.join(root.path, 'picked.bin'));
      await source.writeAsBytes(<int>[
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
        1,
        2,
        3,
      ]);

      final stored = await ImageUnderstandingService.storeLocalCopy(
        source,
        documentsDirectory: root,
      );
      final messageId = await ImageUnderstandingService.persistUnderstanding(
        attachment: stored,
        understanding: const ImageUnderstanding(
          summary: '雨天街道照片',
          facts: ['小乐所在地正在下雨'],
        ),
      );

      expect(stored.mimeType, 'image/png');
      expect(stored.localPath, endsWith('.png'));
      expect(await File(stored.localPath).exists(), isTrue);

      final db = await DatabaseHelper.database;
      final messages = await db.query(
        'chat_history',
        where: 'id = ?',
        whereArgs: [messageId],
      );
      expect(messages.single['message_type'], 'image');

      final attachments = await db.query(
        'chat_attachments',
        where: 'chat_message_id = ?',
        whereArgs: [messageId],
      );
      expect(attachments.single['model_summary'], '雨天街道照片');

      final facts = await db.query('ai_wiki_facts', where: "source = 'image'");
      expect(facts.single['content'], '小乐所在地正在下雨');
    },
  );
}
