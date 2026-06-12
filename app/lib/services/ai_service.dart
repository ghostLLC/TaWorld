/// TaWorld AI 服务 — 直连 DeepSeek API
///
/// 兼容 OpenAI Chat Completions 接口。API Key 由用户在设置中配置。
library;

import 'dart:convert';
import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/local/database_helper.dart';
import 'ai_memory_service.dart';

/// AI 关怀建议结果
class AiSuggestion {
  final String suggestion;
  final List<String> alternatives;
  const AiSuggestion({required this.suggestion, required this.alternatives});
}

/// DeepSeek 上下文缓存统计
class CacheStats {
  final int hitTokens;
  final int missTokens;

  const CacheStats({required this.hitTokens, required this.missTokens});

  int get totalTokens => hitTokens + missTokens;

  double get hitRate =>
      totalTokens == 0 ? 0.0 : hitTokens / totalTokens;

  String get hitRatePercent =>
      totalTokens == 0 ? '-' : '${(hitRate * 100).toStringAsFixed(1)}%';
}

abstract final class AiService {
  static const _defaultBaseUrl = 'https://api.deepseek.com';
  static const _defaultModel = 'deepseek-v4-flash';
  static const _proModel = 'deepseek-v4-pro';

  // ==================== Prompt 模板 ====================

  static const _suggestPrompts = {
    'weather': '''你是一个温暖的关怀助手。用户想提醒Ta关心的人注意天气变化。
场景信息：{context}
请生成一条温暖、简短的关怀消息（不超过50字），以及2条备选消息。
要求：语气温暖自然，像朋友发微信，不使用emoji和markdown。
输出格式（JSON）：
{"suggestion": "主要建议", "alternatives": ["备选1", "备选2"]}''',
    'sleep': '''你是一个温暖的关怀助手。用户想提醒Ta关心的人早点休息。
场景信息：{context}
请生成一条温暖的晚安提醒消息（不超过50字），以及2条备选消息。
要求：语气温暖自然，像朋友发微信，不使用emoji和markdown。
输出格式（JSON）：
{"suggestion": "主要建议", "alternatives": ["备选1", "备选2"]}''',
    'meal': '''你是一个温暖的关怀助手。用户想提醒Ta关心的人按时吃饭。
场景信息：{context}
请生成一条温暖的吃饭提醒消息（不超过50字），以及2条备选消息。
要求：语气温暖自然，像朋友发微信，不使用emoji和markdown。
输出格式（JSON）：
{"suggestion": "主要建议", "alternatives": ["备选1", "备选2"]}''',
    'custom': '''你是一个温暖的关怀助手。用户想给Ta关心的人发送一条关怀消息。
场景信息：{context}
请生成一条温暖的关怀消息（不超过50字），以及2条备选消息。
要求：语气温暖自然，像朋友发微信，不使用emoji和markdown。
输出格式（JSON）：
{"suggestion": "主要建议", "alternatives": ["备选1", "备选2"]}''',
  };

  // ==================== 工具定义（Function Calling）====================

  static const _toolDefinitions = [
    {
      'type': 'function',
      'function': {
        'name': 'create_reminder',
        'description': '为关心的人创建定时提醒（如睡觉提醒、吃饭提醒、天气提醒）',
        'parameters': {
          'type': 'object',
          'properties': {
            'partner_name': {'type': 'string', 'description': '关心的人的名字'},
            'category': {
              'type': 'string',
              'enum': ['sleep', 'meal', 'weather'],
              'description': '提醒类别：sleep睡觉、meal吃饭、weather天气',
            },
            'time': {'type': 'string', 'description': '提醒时间，格式HH:mm（如22:00）'},
            'message': {'type': 'string', 'description': '可选的自定义提醒消息'},
          },
          'required': ['partner_name', 'category', 'time'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'delete_reminder',
        'description': '删除某人的某个类别的提醒',
        'parameters': {
          'type': 'object',
          'properties': {
            'partner_name': {'type': 'string', 'description': '关心的人的名字'},
            'category': {'type': 'string', 'description': '提醒类别（sleep/meal/weather/custom）'},
          },
          'required': ['partner_name', 'category'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_partner_weather',
        'description': '查询某人所在地的当前天气情况',
        'parameters': {
          'type': 'object',
          'properties': {
            'partner_name': {'type': 'string', 'description': '关心的人的名字'},
          },
          'required': ['partner_name'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_all_partners',
        'description': '获取用户关心的所有人的列表和基本',
        'parameters': {
          'type': 'object',
          'properties': {},
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_reminder_stats',
        'description': '获取提醒相关的统计数据（总次数、连续天数等）',
        'parameters': {
          'type': 'object',
          'properties': {},
        },
      },
    },
  ];

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

  // ==================== DeepSeek 缓存统计 ====================

  /// 获取 DeepSeek 上下文缓存统计（累计命中/未命中 token 数）
  static Future<CacheStats> getCacheStats() async {
    final prefs = await SharedPreferences.getInstance();
    return CacheStats(
      hitTokens: prefs.getInt('cache_hit_tokens') ?? 0,
      missTokens: prefs.getInt('cache_miss_tokens') ?? 0,
    );
  }

  /// 重置缓存统计计数器
  static Future<void> resetCacheStats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('cache_hit_tokens', 0);
    await prefs.setInt('cache_miss_tokens', 0);
  }

  /// 从 API 响应的 usage 字段中提取缓存统计并累加
  static void _trackCacheUsage(Map<String, dynamic>? usage) {
    if (usage == null) return;
    final hit = usage['prompt_cache_hit_tokens'] as int? ?? 0;
    final miss = usage['prompt_cache_miss_tokens'] as int? ?? 0;
    if (hit == 0 && miss == 0) return;

    SharedPreferences.getInstance().then((prefs) {
      final totalHit = (prefs.getInt('cache_hit_tokens') ?? 0) + hit;
      final totalMiss = (prefs.getInt('cache_miss_tokens') ?? 0) + miss;
      prefs.setInt('cache_hit_tokens', totalHit);
      prefs.setInt('cache_miss_tokens', totalMiss);
    });

    final total = hit + miss;
    if (total > 0) {
      dev.log(
        'DeepSeek cache: hit=$hit miss=$miss rate=${(hit / total * 100).toStringAsFixed(1)}%',
        name: 'AiService',
      );
    }
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
      return '我是Ta世界的AI关怀助手\n目前AI服务尚未配置，请先在设置中填入 DeepSeek API Key。';
    }

    // 1. 读取最近 10 条对话历史
    final db = await DatabaseHelper.database;
    final historyRows = await db.query(
      'chat_history',
      orderBy: 'created_at DESC',
      limit: 10,
    );

    // 2. 构建消息列表（动态 system prompt + history + 当前消息）
    final dynamicPrompt = await AiMemoryService.buildSystemPrompt(userMessage: userMessage);
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': dynamicPrompt},
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

      // 跟踪 DeepSeek 缓存命中情况
      _trackCacheUsage(response.data['usage'] as Map<String, dynamic>?);

      // 5. 保存助手回复
      await db.insert('chat_history', {
        'id': DatabaseHelper.newId(),
        'role': 'assistant',
        'content': reply,
        'created_at': DateTime.now().toIso8601String(),
      });

      return reply;
    } catch (_) {
      return '抱歉，我暂时无法回应。请检查网络和 API Key 配置';
    }
  }

  /// AI 流式对话（逐 token 回调 + 历史上下文）
  ///
  /// [onToken] 每收到一个 content token 时调用。
  /// 返回完整回复文本。
  static Future<String> streamChat(
    String userMessage, {
    required void Function(String accumulated) onToken,
  }) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      onToken('AI 服务未配置，请先在设置中填入 DeepSeek API Key');
      return 'AI 服务未配置';
    }

    // 1. 读取最近 10 条历史
    final db = await DatabaseHelper.database;
    final historyRows = await db.query(
      'chat_history',
      orderBy: 'created_at DESC',
      limit: 10,
    );

    // 2. 构建消息列表（动态 prompt）
    final dynamicPrompt = await AiMemoryService.buildSystemPrompt(userMessage: userMessage);
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': dynamicPrompt},
    ];
    for (final row in historyRows.reversed) {
      messages.add({
        'role': row['role'] as String,
        'content': row['content'] as String,
      });
    }
    messages.add({'role': 'user', 'content': userMessage});

    // 3. 保存用户消息
    await db.insert('chat_history', {
      'id': DatabaseHelper.newId(),
      'role': 'user',
      'content': userMessage,
      'created_at': DateTime.now().toIso8601String(),
    });

    try {
      // 4. 流式调用 API
      final dio = Dio();
      final response = await dio.post(
        '$_defaultBaseUrl/v1/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.stream,
        ),
        data: {
          'model': _defaultModel,
          'temperature': 0.7,
          'max_tokens': 500,
          'stream': true,
          'stream_options': {'include_usage': true},
          'messages': messages,
        },
      );

      final buffer = StringBuffer();

      await for (final chunk in response.data.stream) {
        final text = utf8.decode(chunk);
        for (final line in text.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || !trimmed.startsWith('data: ')) continue;
          final json = trimmed.substring(6);
          if (json == '[DONE]') continue;
          try {
            final parsed = jsonDecode(json) as Map<String, dynamic>;

            // 提取缓存统计（DeepSeek 在最后一个 chunk 中返回 usage）
            _trackCacheUsage(parsed['usage'] as Map<String, dynamic>?);

            final delta =
                parsed['choices']?[0]?['delta']?['content'] as String?;
            if (delta != null && delta.isNotEmpty) {
              buffer.write(delta);
              onToken(buffer.toString());
            }
          } catch (_) {}
        }
      }

      final reply = buffer.toString();

      // 5. 保存完整回复
      await db.insert('chat_history', {
        'id': DatabaseHelper.newId(),
        'role': 'assistant',
        'content': reply,
        'created_at': DateTime.now().toIso8601String(),
      });

      return reply;
    } catch (_) {
      onToken('抱歉，网络好像出了点问题，请检查网络连接');
      return '';
    }
  }

  /// AI 带工具调用的对话
  ///
  /// 先调用 API 检查是否需要执行工具，如果需要则执行工具，
  /// 然后将结果回传 AI 生成最终回复（流式）。
  ///
  /// [onToken] 每收到一个 content token 时调用。
  /// [onToolCall] 当 AI 请求执行工具时调用，返回工具执行结果。
  /// 返回完整回复文本。
  static Future<String> chatWithTools(
    String userMessage, {
    required void Function(String accumulated) onToken,
    required Future<String> Function(String name, Map<String, dynamic> args)
        onToolCall,
  }) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      onToken('AI 服务未配置，请先在设置中填入 DeepSeek API Key');
      return 'AI 服务未配置';
    }

    // 1. 读取最近 10 条历史
    final db = await DatabaseHelper.database;
    final historyRows = await db.query(
      'chat_history',
      orderBy: 'created_at DESC',
      limit: 10,
    );

    // 2. 构建消息列表（动态 prompt + 历史）
    final dynamicPrompt = await AiMemoryService.buildSystemPrompt(userMessage: userMessage);
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': dynamicPrompt},
    ];
    for (final row in historyRows.reversed) {
      messages.add({
        'role': row['role'] as String,
        'content': row['content'] as String,
      });
    }
    messages.add({'role': 'user', 'content': userMessage});

    // 3. 保存用户消息
    await db.insert('chat_history', {
      'id': DatabaseHelper.newId(),
      'role': 'user',
      'content': userMessage,
      'created_at': DateTime.now().toIso8601String(),
    });

    final dio = Dio();

    try {
      // 4. 第一轮调用（非流式），检查工具调用
      final firstResponse = await dio.post(
        '$_defaultBaseUrl/v1/chat/completions',
        options: Options(headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': _defaultModel,
          'temperature': 0.7,
          'max_tokens': 500,
          'stream': false,
          'messages': messages,
          'tools': _toolDefinitions,
        },
      );

      final choice = firstResponse.data['choices']?[0];
      final assistantMessage = choice?['message'];
      var currentToolCalls = assistantMessage?['tool_calls'] as List?;

      // 跟踪 DeepSeek 缓存命中情况
      _trackCacheUsage(firstResponse.data['usage'] as Map<String, dynamic>?);

      // 5. 如果有工具调用，执行工具并回传结果
      if (currentToolCalls != null && currentToolCalls.isNotEmpty) {
        // 添加 assistant 消息（含 tool_calls）到上下文
        messages.add(Map<String, dynamic>.from(assistantMessage as Map));

        int toolRounds = 0;
        const maxToolRounds = 5;

        while (currentToolCalls != null &&
            currentToolCalls.isNotEmpty &&
            toolRounds < maxToolRounds) {
          // 执行所有工具调用
          for (final toolCall in currentToolCalls) {
            final funcName =
                toolCall['function']?['name'] as String? ?? '';
            final argsStr =
                toolCall['function']?['arguments'] as String? ?? '{}';
            final callId = toolCall['id'] as String? ?? '';

            Map<String, dynamic> args = {};
            try {
              args = jsonDecode(argsStr) as Map<String, dynamic>;
            } catch (_) {}

            // 执行工具
            final result = await onToolCall(funcName, args);

            // 添加工具结果到上下文
            messages.add({
              'role': 'tool',
              'tool_call_id': callId,
              'content': result,
            });
          }

          // 再次调用 API（非流式）检查是否有更多工具调用
          final nextResponse = await dio.post(
            '$_defaultBaseUrl/v1/chat/completions',
            options: Options(headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
            }),
            data: {
              'model': _defaultModel,
              'temperature': 0.7,
              'max_tokens': 500,
              'stream': false,
              'messages': messages,
              'tools': _toolDefinitions,
            },
          );

          final nextChoice = nextResponse.data['choices']?[0];
          final nextMsg = nextChoice?['message'];
          currentToolCalls = nextMsg?['tool_calls'] as List?;

          // 跟踪 DeepSeek 缓存命中情况
          _trackCacheUsage(nextResponse.data['usage'] as Map<String, dynamic>?);

          if (currentToolCalls != null && currentToolCalls.isNotEmpty) {
            messages.add(Map<String, dynamic>.from(nextMsg as Map));
            toolRounds++;
            continue; // 继续执行下一轮工具
          }

          // 没有更多工具调用，取最终文本回复
          final finalContent = nextMsg?['content'] as String? ?? '';
          if (finalContent.isNotEmpty) {
            onToken(finalContent);

            await db.insert('chat_history', {
              'id': DatabaseHelper.newId(),
              'role': 'assistant',
              'content': finalContent,
              'created_at': DateTime.now().toIso8601String(),
            });
            return finalContent;
          }
          break;
        }
      }

      // 6. 无工具调用（或工具链结束无文本），直接取文本
      final directContent = assistantMessage?['content'] as String?;
      if (directContent != null && directContent.isNotEmpty) {
        onToken(directContent);

        await db.insert('chat_history', {
          'id': DatabaseHelper.newId(),
          'role': 'assistant',
          'content': directContent,
          'created_at': DateTime.now().toIso8601String(),
        });
        return directContent;
      }

      // 7. 如果第一轮有文本但需要流式输出，重新调用（流式）
      final streamResponse = await dio.post(
        '$_defaultBaseUrl/v1/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.stream,
        ),
        data: {
          'model': _defaultModel,
          'temperature': 0.7,
          'max_tokens': 500,
          'stream': true,
          'messages': messages,
        },
      );

      final buffer = StringBuffer();
      await for (final chunk in streamResponse.data.stream) {
        final text = utf8.decode(chunk);
        for (final line in text.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || !trimmed.startsWith('data: ')) continue;
          final json = trimmed.substring(6);
          if (json == '[DONE]') continue;
          try {
            final parsed = jsonDecode(json) as Map<String, dynamic>;
            final delta =
                parsed['choices']?[0]?['delta']?['content'] as String?;
            if (delta != null && delta.isNotEmpty) {
              buffer.write(delta);
              onToken(buffer.toString());
            }
          } catch (_) {}
        }
      }

      final reply = buffer.toString();
      if (reply.isNotEmpty) {
        await db.insert('chat_history', {
          'id': DatabaseHelper.newId(),
          'role': 'assistant',
          'content': reply,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      return reply;
    } catch (_) {
      onToken('抱歉，网络好像出了点问题，请检查网络连接');
      return '';
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

  /// 调用 Pro 模型（用于异步任务：记忆提取、摘要、Dreaming 整合）
  ///
  /// 使用 deepseek-v4-pro 模型，逻辑能力更强，适合复杂推理任务。
  /// 非流式调用，直接返回完整文本。
  ///
  /// [systemPrompt] 可选的 system message，用于缓存优化：
  /// 将不变指令放在 system 里，可变数据放在 [prompt] 里，
  /// DeepSeek 会自动缓存 system 部分的 KV 状态供后续调用复用。
  static Future<String?> callProModel({
    required String prompt,
    String? systemPrompt,
    double temperature = 0.3,
    int maxTokens = 2000,
  }) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) return null;

    try {
      final dio = Dio();
      final messages = <Map<String, String>>[
        if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': prompt},
      ];

      final response = await dio.post(
        '$_defaultBaseUrl/v1/chat/completions',
        options: Options(headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': _proModel,
          'temperature': temperature,
          'max_tokens': maxTokens,
          'messages': messages,
        },
      );

      return response.data['choices']?[0]?['message']?['content'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// 清空对话历史
  static Future<void> clearChatHistory() async {
    final db = await DatabaseHelper.database;
    await db.delete('chat_history');
  }

  /// 清空所有记忆数据（Wiki 事实 + 摘要 + chunks）
  static Future<void> clearAllMemory() async {
    final db = await DatabaseHelper.database;
    await db.delete('ai_wiki_facts');
    await db.delete('ai_conversation_summaries');
    await db.delete('conversation_chunks');
  }

  /// 降级方案
  static AiSuggestion _fallbackSuggestion(String category) {
    return switch (category) {
      'weather' => const AiSuggestion(
        suggestion: '外面天气变化了，记得提醒Ta注意哦',
        alternatives: ['天气变了，关心一下Ta吧', '提醒Ta注意天气变化'],
      ),
      'sleep' => const AiSuggestion(
        suggestion: '夜深了，提醒Ta早点休息吧',
        alternatives: ['该睡觉啦，提醒Ta放下手机', '晚安时间到，关心一下Ta吧'],
      ),
      'meal' => const AiSuggestion(
        suggestion: '到饭点啦，提醒Ta按时吃饭',
        alternatives: ['别让Ta饿肚子，提醒Ta吃饭吧', '吃饭时间到，关心一下Ta'],
      ),
      _ => const AiSuggestion(
        suggestion: '想Ta了就告诉Ta吧',
        alternatives: ['简单的关心，也是最好的温暖', '发条消息，让Ta知道你在想Ta'],
      ),
    };
  }
}
