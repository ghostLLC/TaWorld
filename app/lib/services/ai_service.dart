/// TaWorld AI 服务 — 直连 DeepSeek API
///
/// 兼容 OpenAI Chat Completions 接口。API Key 由用户在设置中配置。
library;

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/local/database_helper.dart';

/// AI 关怀建议结果
class AiSuggestion {
  final String suggestion;
  final List<String> alternatives;
  const AiSuggestion({required this.suggestion, required this.alternatives});
}

abstract final class AiService {
  static const _defaultBaseUrl = 'https://api.deepseek.com';
  static const _defaultModel = 'deepseek-chat';

  // ==================== Prompt 模板 ====================

  static const _suggestPrompts = {
    'weather': '''你是一个温暖的关怀助手。用户想提醒Ta关心的人注意天气变化。
场景信息：{context}
请生成一条温暖、简短的关怀消息（不超过50字），以及2条备选消息。
要求：语气温暖自然，可以加入合适的emoji。
输出格式（JSON）：
{"suggestion": "主要建议", "alternatives": ["备选1", "备选2"]}''',
    'sleep': '''你是一个温暖的关怀助手。用户想提醒Ta关心的人早点休息。
场景信息：{context}
请生成一条温暖的晚安提醒消息（不超过50字），以及2条备选消息。
要求：语气温暖自然，可以加入合适的emoji，不要过于肉麻。
输出格式（JSON）：
{"suggestion": "主要建议", "alternatives": ["备选1", "备选2"]}''',
    'meal': '''你是一个温暖的关怀助手。用户想提醒Ta关心的人按时吃饭。
场景信息：{context}
请生成一条温暖的吃饭提醒消息（不超过50字），以及2条备选消息。
要求：语气温暖自然，可以加入合适的emoji。
输出格式（JSON）：
{"suggestion": "主要建议", "alternatives": ["备选1", "备选2"]}''',
    'custom': '''你是一个温暖的关怀助手。用户想给Ta关心的人发送一条关怀消息。
场景信息：{context}
请生成一条温暖的关怀消息（不超过50字），以及2条备选消息。
要求：语气温暖自然，可以加入合适的emoji。
输出格式（JSON）：
{"suggestion": "主要建议", "alternatives": ["备选1", "备选2"]}''',
  };

  static const _chatSystemPrompt = '''你是「Ta的世界」APP的AI关怀助手。你的职责是：
1. 帮助用户更好地关心Ta在意的人
2. 提供关怀建议和温暖的表达方式
3. 回答关于APP功能的问题
4. 保持温暖、积极、有同理心的语气

注意事项：
- 回答要简洁，不超过200字
- 语气温暖自然，可以适当使用emoji
- 不要讨论与关怀无关的话题
- 保护用户隐私''';

  // ==================== API Key 管理 ====================

  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('deepseek_api_key');
  }

  static Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('deepseek_api_key', key);
  }

  static Future<bool> hasApiKey() async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty;
  }

  // ==================== API 调用 ====================

  /// 生成关怀建议
  static Future<AiSuggestion> generateSuggestion({
    required String category,
    Map<String, dynamic>? context,
  }) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      return _fallbackSuggestion(category);
    }

    try {
      final promptTemplate = _suggestPrompts[category] ?? _suggestPrompts['custom']!;
      final prompt = promptTemplate.replaceAll('{context}', context?.toString() ?? '');

      final dio = Dio();
      final response = await dio.post(
        '$_defaultBaseUrl/v1/chat/completions',
        options: Options(headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': _defaultModel,
          'temperature': 0.8,
          'max_tokens': 500,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        },
      );

      final content = response.data['choices'][0]['message']['content'] as String;
      try {
        final parsed = jsonDecode(content) as Map<String, dynamic>;
        return AiSuggestion(
          suggestion: parsed['suggestion'] as String? ?? content,
          alternatives: (parsed['alternatives'] as List?)?.cast<String>() ?? [],
        );
      } catch (_) {
        return AiSuggestion(suggestion: content.trim(), alternatives: []);
      }
    } catch (_) {
      return _fallbackSuggestion(category);
    }
  }

  /// AI 对话（带历史上下文）
  static Future<String> chat(String userMessage) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      return '我是Ta世界的AI关怀助手 💝\n目前AI服务尚未配置，请先在"设置"中填入 DeepSeek API Key。';
    }

    // 1. 读取最近 10 条对话历史
    final db = await DatabaseHelper.database;
    final historyRows = await db.query(
      'chat_history',
      orderBy: 'created_at DESC',
      limit: 10,
    );

    // 2. 构建消息列表（system + history 倒序 + 当前用户消息）
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': _chatSystemPrompt},
    ];
    for (final row in historyRows.reversed) {
      messages.add({
        'role': row['role'] as String,
        'content': row['content'] as String,
      });
    }
    messages.add({'role': 'user', 'content': userMessage});

    // 3. 保存用户消息到 DB
    await db.insert('chat_history', {
      'id': DatabaseHelper.newId(),
      'role': 'user',
      'content': userMessage,
      'created_at': DateTime.now().toIso8601String(),
    });

    try {
      // 4. 调用 API
      final dio = Dio();
      final response = await dio.post(
        '$_defaultBaseUrl/v1/chat/completions',
        options: Options(headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': _defaultModel,
          'temperature': 0.7,
          'max_tokens': 500,
          'messages': messages,
        },
      );

      final reply = response.data['choices'][0]['message']['content'] as String;

      // 5. 保存助手回复
      await db.insert('chat_history', {
        'id': DatabaseHelper.newId(),
        'role': 'assistant',
        'content': reply,
        'created_at': DateTime.now().toIso8601String(),
      });

      return reply;
    } catch (_) {
      return '抱歉，我暂时无法回应。请检查网络连接和 API Key 配置 🙏';
    }
  }

  /// 获取对话历史
  static Future<List<Map<String, dynamic>>> getChatHistory({int limit = 50}) async {
    final db = await DatabaseHelper.database;
    return db.query(
      'chat_history',
      orderBy: 'created_at ASC',
      limit: limit,
    );
  }

  /// 清空对话历史
  static Future<void> clearChatHistory() async {
    final db = await DatabaseHelper.database;
    await db.delete('chat_history');
  }

  /// 降级方案
  static AiSuggestion _fallbackSuggestion(String category) {
    return switch (category) {
      'weather' => const AiSuggestion(
        suggestion: '外面天气变化了，记得提醒Ta注意哦 ☁️',
        alternatives: ['天气变了，关心一下Ta吧 🌤️', '提醒Ta注意天气变化 🌂'],
      ),
      'sleep' => const AiSuggestion(
        suggestion: '夜深了，提醒Ta早点休息吧 🌙',
        alternatives: ['该睡觉啦，提醒Ta放下手机 💤', '晚安时间到，关心一下Ta吧 ✨'],
      ),
      'meal' => const AiSuggestion(
        suggestion: '到饭点啦，提醒Ta按时吃饭 🍚',
        alternatives: ['别让Ta饿肚子，提醒Ta吃饭吧 🥗', '吃饭时间到，关心一下Ta 🍜'],
      ),
      _ => const AiSuggestion(
        suggestion: '想Ta了就告诉Ta吧 💝',
        alternatives: ['简单的关心，也是最好的温暖 ☀️', '发条消息，让Ta知道你在想Ta 💌'],
      ),
    };
  }
}
