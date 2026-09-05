import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taworld/data/local/database_helper.dart';
import 'package:taworld/services/ai_service.dart';
import '../helpers/test_database.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final Future<Map<String, Object?>> Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancelFuture,
  ) async {
    final result = await handler(options);
    return ResponseBody.fromString(
      jsonEncode({
        'choices': [
          {'message': result},
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _tool(String name, String args) => {
  'role': 'assistant',
  'content': null,
  'tool_calls': [
    {
      'id': 'call-$name',
      'type': 'function',
      'function': {'name': name, 'arguments': args},
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'deepseek_api_key': 'synthetic-test-key',
    });
    await openTestDatabase();
  });
  tearDown(() async {
    await AiService.stopAndWait();
    AiService.chatClientFactoryForTesting = null;
    await closeTestDatabase();
  });
  void respond(Future<Map<String, Object?>> Function(RequestOptions) handler) {
    AiService.chatClientFactoryForTesting = (options) =>
        Dio(options)..httpClientAdapter = _Adapter(handler);
  }

  test(
    'dependent tool rounds return the final response and verified receipts',
    () async {
      var requests = 0;
      final tools = <String>[];
      respond((options) async {
        requests++;
        final payload = options.data as Map;
        expect(payload['stream'], false);
        if (requests == 1) return _tool('create_partner', '{"nickname":"妈妈"}');
        final messages = payload['messages'] as List;
        expect(
          messages.where((m) => m['role'] == 'tool'),
          hasLength(requests - 1),
        );
        if (requests == 2) {
          return _tool(
            'create_reminder',
            '{"partner_id":"p1","category":"custom"}',
          );
        }
        return {'role': 'assistant', 'content': '已添加妈妈，并安排明天的提醒。'};
      });
      final result = await AiService.chatWithTools(
        '添加妈妈并安排提醒',
        onToken: (_) {},
        onToolCall: (name, args) async {
          tools.add(name);
          return jsonEncode({
            'status': 'success',
            'verified': true,
            'entity_id': 'p1',
            'message': '已完成',
          });
        },
      );
      expect(requests, 3);
      expect(tools, ['create_partner', 'create_reminder']);
      expect(result, '已添加妈妈，并安排明天的提醒。');
      expect((await AiService.getChatHistory()).last['content'], result);
    },
  );
  test(
    'malformed tool arguments are returned for repair and never executed',
    () async {
      var requests = 0, executions = 0;
      respond((options) async {
        if (++requests == 1) return _tool('create_partner', '{broken');
        final messages = (options.data as Map)['messages'] as List;
        final receipt = jsonDecode(messages.last['content'] as String);
        expect(receipt['status'], 'failure');
        return {'role': 'assistant', 'content': '参数未完成，本次没有新增人物。'};
      });
      await AiService.chatWithTools(
        '添加妈妈',
        onToken: (_) {},
        onToolCall: (_, args) async {
          executions++;
          return '{}';
        },
      );
      expect(executions, 0);
    },
  );
  test(
    'replaying the same request preserves exactly one mutation and conversation pair',
    () async {
      var requests = 0, executions = 0;
      respond(
        (_) async => ++requests % 2 == 1
            ? _tool('create_partner', '{"nickname":"妈妈"}')
            : {'role': 'assistant', 'content': '已添加妈妈'},
      );
      for (var i = 0; i < 2; i++) {
        await AiService.chatWithTools(
          '添加妈妈',
          requestId: 'same-request',
          onToken: (_) {},
          onToolCall: (_, args) async {
            executions++;
            return '{"status":"success","verified":true,"message":"已添加妈妈"}';
          },
        );
      }
      expect(executions, 1);
      expect(await AiService.getChatHistory(), hasLength(2));
      expect(
        await (await DatabaseHelper.database).query('tool_operations'),
        hasLength(1),
      );
    },
  );
  test(
    'cancelling an in-flight request releases the chat and preserves the user message',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      respond((_) async {
        entered.complete();
        await release.future;
        return {'role': 'assistant', 'content': 'late'};
      });
      final request = AiService.chatWithTools(
        '测试停止',
        onToken: (_) => fail('late content must not be published'),
        onToolCall: (_, args) async => '{}',
      );
      final assertion = expectLater(request, throwsA(isA<AiChatException>()));
      await entered.future;
      AiService.cancelCurrentChat();
      release.complete();
      await assertion;
      await AiService.stopAndWait();
      expect(await AiService.getChatHistory(), hasLength(1));
    },
  );
}
