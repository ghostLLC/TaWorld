import 'package:flutter_test/flutter_test.dart';
import 'package:taworld/data/local/database_helper.dart';
import 'package:taworld/services/chat_history_service.dart';

import '../helpers/test_database.dart';

void main() {
  setUp(openTestDatabase);
  tearDown(closeTestDatabase);

  test('appendOnce keeps onboarding events idempotent', () async {
    final first = await ChatHistoryService.appendOnce(
      requestId: 'onboarding:intro:hello',
      role: 'assistant',
      content: '你好呀，我是小念',
    );
    final second = await ChatHistoryService.appendOnce(
      requestId: 'onboarding:intro:hello',
      role: 'assistant',
      content: '你好呀，我是小念',
    );

    expect(first.inserted, isTrue);
    expect(second.inserted, isFalse);
    expect(second.id, first.id);
    expect(await ChatHistoryService.getVisible(), hasLength(1));
  });

  test(
    'hiding a presentation keeps the record available to AI context',
    () async {
      final result = await ChatHistoryService.append(
        role: 'assistant',
        content: '已添加关心的人：小乐',
        messageType: 'milestone',
        metadata: const {'status': 'success'},
      );

      await ChatHistoryService.hide(result.id);

      expect(await ChatHistoryService.getVisible(), isEmpty);
      final all = await ChatHistoryService.getAll(includeHidden: true);
      expect(all, hasLength(1));
      expect(all.single['content'], '已添加关心的人：小乐');
      expect(all.single['hidden_at'], isNotNull);
    },
  );

  test(
    'hidden launch prompts never appear in the visible conversation',
    () async {
      await ChatHistoryService.appendOnce(
        requestId: 'graph:chat:partner-1',
        role: 'user',
        content: '主动聊聊小乐',
        hidden: true,
      );

      expect(await ChatHistoryService.getVisible(), isEmpty);
      expect(
        await ChatHistoryService.getAll(includeHidden: true),
        hasLength(1),
      );
    },
  );

  test('loads typed image attachment by chat message id', () async {
    final message = await ChatHistoryService.append(
      role: 'user',
      content: '雨天街道',
      messageType: 'image',
    );
    final db = await DatabaseHelper.database;
    await db.insert('chat_attachments', {
      'id': 'attachment-1',
      'chat_message_id': message.id,
      'local_path': 'chat_images/one.png',
      'mime_type': 'image/png',
      'sha256': 'digest',
      'extracted_facts_json': '[]',
      'status': 'local',
      'created_at': '2026-08-22T12:00:00.000',
    });

    final attachments = await ChatHistoryService.getAttachmentsByMessageIds([
      message.id,
    ]);
    expect(attachments[message.id]?['local_path'], 'chat_images/one.png');
  });
}
