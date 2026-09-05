/// TaWorld AI 服务 — 直连 DeepSeek API
///
/// 兼容 OpenAI Chat Completions 接口。API Key 由用户在设置中配置。
library;

import 'dart:convert';
import 'dart:async';
import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../data/local/database_helper.dart';
import 'ai_model_catalog.dart';
import 'ai_memory_service.dart';
import 'chat_history_service.dart';
import 'tool_operation_journal.dart';
import 'api_key_store.dart';

class AiChatException implements Exception {
  const AiChatException(this.message);

  final String message;

  @override
  String toString() => message;
}

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

  double get hitRate => totalTokens == 0 ? 0.0 : hitTokens / totalTokens;

  String get hitRatePercent =>
      totalTokens == 0 ? '-' : '${(hitRate * 100).toStringAsFixed(1)}%';
}

abstract final class AiService {
  static const _defaultBaseUrl = 'https://api.deepseek.com';
  static const _defaultModel = AiModelCatalog.primary;

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

  static final _toolDefinitions = _buildToolDefinitions();
  static const _baseToolDefinitions = [
    {
      'type': 'function',
      'function': {
        'name': 'create_reminder',
        'description':
            '为用户自己或关心的人创建睡觉、吃饭或天气提醒。天气提醒分为每日简报和天气突变监测；必须明确时间按用户还是对方的当地时间理解。',
        'parameters': {
          'type': 'object',
          'properties': {
            'subject': {
              'type': 'string',
              'enum': ['partner', 'self'],
              'description': '提醒对象：partner 为关心的人；self 为用户自己',
            },
            'partner_name': {'type': 'string', 'description': '关心的人的名字'},
            'category': {
              'type': 'string',
              'enum': ['sleep', 'meal', 'weather'],
              'description': '提醒类别：sleep睡觉、meal吃饭、weather天气',
            },
            'weather_mode': {
              'type': 'string',
              'enum': ['daily_digest', 'weather_change'],
              'description':
                  '仅天气提醒使用：daily_digest 为每天固定时间查看天气；weather_change 为在监测时段内发现未来天气突变时提醒',
            },
            'time': {
              'type': 'string',
              'description': 'HH:mm 当地钟表时间。睡觉、吃饭、每日天气简报必须提供；天气突变监测不需要',
            },
            'message': {'type': 'string', 'description': '可选的自定义提醒消息'},
            'time_basis': {
              'type': 'string',
              'enum': ['user', 'partner'],
              'description': '时间按谁的当地钟表理解：user 是用户所在时区；partner 是关心的人所在时区',
            },
            'timezone_id': {
              'type': 'string',
              'description':
                  '可选 IANA 时区，如 Asia/Singapore。选择 partner 且人物档案没有可靠时区时必须先向用户确认',
            },
            'advance_minutes': {
              'type': 'integer',
              'description': '睡觉或吃饭提醒可选提前分钟数',
            },
            'monitor_start': {
              'type': 'string',
              'description': '天气突变监测开始时间 HH:mm，默认 07:00',
            },
            'monitor_end': {
              'type': 'string',
              'description': '天气突变监测结束时间 HH:mm，默认 23:00',
            },
            'lead_minutes': {
              'type': 'integer',
              'description': '天气突变向前观察分钟数，默认 180',
            },
            'cooldown_minutes': {
              'type': 'integer',
              'description': '同类天气事件的通知冷却时间，默认 240 分钟',
            },
            'notify_conditions': {
              'type': 'array',
              'items': {
                'type': 'string',
                'enum': [
                  'rain',
                  'snow',
                  'temperature_drop',
                  'temperature_rise',
                  'extreme_cold',
                  'extreme_heat',
                ],
              },
              'description': '天气突变监测条件',
            },
          },
          'required': ['category'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'delete_reminder',
        'description': '删除某人的某个类别的提醒。两种天气提醒并存时必须明确 weather_mode。',
        'parameters': {
          'type': 'object',
          'properties': {
            'subject': {
              'type': 'string',
              'enum': ['partner', 'self'],
              'description': '删除关心的人的提醒或用户自己的提醒',
            },
            'partner_name': {'type': 'string', 'description': '关心的人的名字'},
            'category': {
              'type': 'string',
              'description': '提醒类别（sleep/meal/weather/custom）',
            },
            'weather_mode': {
              'type': 'string',
              'enum': ['daily_digest', 'weather_change'],
              'description': '删除天气提醒时指定：每日天气简报或天气突变监测',
            },
          },
          'required': ['category'],
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
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_reminder_stats',
        'description': '获取提醒相关的统计数据（总次数、连续天数等）',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'create_partner',
        'description': '帮用户添加一个新的关心的人。如果用户提到了城市，一定要同时传入city参数。',
        'parameters': {
          'type': 'object',
          'properties': {
            'nickname': {'type': 'string', 'description': '关心的人的名字或昵称'},
            'relationship': {
              'type': 'string',
              'enum': ['couple', 'partner', 'family', 'friend'],
              'description': '关系类型：couple情侣、partner伴侣、family家人、friend朋友',
            },
            'city': {
              'type': 'string',
              'description': '对方所在城市（如用户提到则填写，用简洁城市名如"上海"不要加"市"）',
            },
            'timezone_id': {
              'type': 'string',
              'description': '用户明确确认的 IANA 时区（如 Asia/Singapore）。不能只凭不唯一的城市名猜测',
            },
            'note': {'type': 'string', 'description': '一句话描述（可选）'},
          },
          'required': ['nickname', 'relationship'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_partner_detail',
        'description': '查看某个关心的人的详细信息，包括城市、提醒配置等。在声称操作成功之前，用这个工具验证数据。',
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
        'name': 'update_partner',
        'description':
            '修改某个关心的人的信息（城市、关系类型、备注等）。用户说"把XX的城市改成北京"或"XX不是朋友是家人"时使用。',
        'parameters': {
          'type': 'object',
          'properties': {
            'partner_name': {'type': 'string', 'description': '要修改的人的当前名字'},
            'new_nickname': {
              'type': 'string',
              'description': '新的名字/昵称（可选，不改则不传）',
            },
            'relationship': {
              'type': 'string',
              'enum': ['couple', 'partner', 'family', 'friend'],
              'description': '新的关系类型（可选，不改则不传）',
            },
            'city': {
              'type': 'string',
              'description': '新的城市（可选，用简洁城市名如"上海"不要加"市"，不改则不传）',
            },
            'timezone_id': {
              'type': 'string',
              'description': '用户确认后的新 IANA 时区（可选，如 Asia/Singapore）',
            },
            'note': {'type': 'string', 'description': '新的一句话描述（可选，不改则不传）'},
          },
          'required': ['partner_name'],
        },
      },
    },
  ];

  static List<Map<String, dynamic>> _buildToolDefinitions() {
    final definitions = (jsonDecode(jsonEncode(_baseToolDefinitions)) as List)
        .map((x) => Map<String, dynamic>.from(x as Map))
        .toList();
    for (final tool in definitions) {
      final function = tool['function'] as Map<String, dynamic>;
      final parameters = function['parameters'] as Map<String, dynamic>;
      final properties = parameters['properties'] as Map<String, dynamic>;
      if (properties.containsKey('partner_name')) {
        properties['partner_id'] = {
          'type': 'string',
          'description': '优先使用数据快照中的人物ID，避免重名误操作',
        };
        (parameters['required'] as List?)?.remove('partner_name');
      }
      if (properties.containsKey('relationship')) {
        properties['relationship']['enum'] = [
          'couple',
          'partner',
          'family',
          'friend',
          'colleague',
          'classmate',
          'other',
        ];
      }
      if (function['name'] == 'create_reminder') {
        function['description'] =
            '创建固定、单次、自定义或天气监测提醒；已有同一提醒要修改时使用 update_reminder。';
        properties['category']['enum'] = ['sleep', 'meal', 'weather', 'custom'];
        properties.addAll({
          'scheduled_at': {
            'type': 'string',
            'description': 'custom 单次日期，ISO8601，必须带时区偏移或Z',
          },
          'relative_minutes': {
            'type': 'integer',
            'description': 'custom 相对现在多少分钟后，仅一次',
          },
          'repeat_daily': {
            'type': 'boolean',
            'description': '是否重复，单次必须提供日期或相对分钟',
          },
          'weekdays': {
            'type': 'array',
            'items': {'type': 'integer', 'minimum': 1, 'maximum': 7},
            'description': '指定星期，1周一到7周日',
          },
        });
      }
    }
    final create =
        definitions.first['function']['parameters']['properties']
            as Map<String, dynamic>;
    definitions.add({
      'type': 'function',
      'function': {
        'name': 'update_reminder',
        'description':
            '按 reminder_id 修改现有提醒时间、内容或 enabled 开关。仅提供要变更的字段，未提供的保留。',
        'parameters': {
          'type': 'object',
          'properties': {
            ...create,
            'reminder_id': {'type': 'string', 'description': '已有提醒的ID'},
            'enabled': {'type': 'boolean', 'description': 'false暂停，true恢复'},
            'meal_name': {'type': 'string', 'description': '多餐次时指定要改的餐次名称'},
          },
          'required': ['reminder_id'],
        },
      },
    });
    definitions.add({
      'type': 'function',
      'function': {
        'name': 'get_reminders',
        'description': '读取全部已保存提醒（包括暂停、自己的提醒），返回ID及配置',
        'parameters': {'type': 'object', 'properties': {}},
      },
    });
    definitions.add({
      'type': 'function',
      'function': {
        'name': 'get_capabilities',
        'description': '检查当前可用能力和提醒通知状态',
        'parameters': {'type': 'object', 'properties': {}},
      },
    });
    return definitions;
  }

  // ==================== Token 估算与动态上下文 ====================

  /// 估算文本的 token 数量（中英文混合场景）
  /// 中文每字约 2 token，英文每词约 1.3 token
  static int _estimateTokens(String text) {
    int tokens = 0;
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code >= 0x4e00 && code <= 0x9fff) {
        tokens += 2; // CJK 字符
      } else if (code < 128) {
        tokens += 1; // ASCII
      } else {
        tokens += 2; // 其他 unicode
      }
    }
    return tokens;
  }

  /// 动态加载历史消息：在 token 预算内尽可能多加载
  ///
  /// [tokenBudget] 历史消息的 token 上限（默认 200K，DeepSeek-v4 支持 1M 上下文）
  /// [maxMessages] 最大消息条数（默认 2000）
  static Future<List<Map<String, String>>> _loadDynamicHistory({
    int tokenBudget = 200000,
    int maxMessages = 2000,
    String? excludeRequestId,
  }) async {
    final db = await DatabaseHelper.database;

    // 如果已有对话摘要，只加载摘要之后的消息（旧消息已被摘要覆盖）
    final prefs = await SharedPreferences.getInstance();
    final cutoff = prefs.getString('summarized_up_to');

    final whereParts = <String>[];
    final whereArgs = <Object?>[];
    whereParts.add('message_type NOT IN (?, ?)');
    whereArgs.addAll(['launch_prompt', 'image_context']);
    if (cutoff != null) {
      whereParts.add('created_at > ?');
      whereArgs.add(cutoff);
    }
    if (excludeRequestId != null) {
      whereParts.add('(request_id IS NULL OR request_id != ?)');
      whereArgs.add(excludeRequestId);
    }
    final historyRows = await db.query(
      'chat_history',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'created_at DESC',
      limit: maxMessages,
    );

    final messages = <Map<String, String>>[];
    int usedTokens = 0;

    for (final row in historyRows) {
      final content = row['content'] as String;
      final msgTokens = _estimateTokens(content);
      if (usedTokens + msgTokens > tokenBudget) break;
      usedTokens += msgTokens;
      messages.add({'role': row['role'] as String, 'content': content});
    }

    return messages.reversed.toList(); // 恢复时间正序
  }

  /// 构建完整消息列表（system prompt + 动态历史 + 当前消息）
  static Future<List<Map<String, String>>> _buildMessages(
    String userMessage, {
    int historyTokenBudget = 200000,
    String? excludeRequestId,
  }) async {
    final dynamicPrompt = await AiMemoryService.buildSystemPrompt(
      userMessage: userMessage,
    );
    final history = await _loadDynamicHistory(
      tokenBudget: historyTokenBudget,
      excludeRequestId: excludeRequestId,
    );

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': dynamicPrompt},
      ...history,
      {'role': 'user', 'content': userMessage},
    ];
    return messages;
  }

  // ==================== API Key 管理 ====================

  static Future<String?> getApiKey() => ApiKeyStore.read();
  static Future<void> setApiKey(String key) => ApiKeyStore.write(key);

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
      final promptTemplate =
          _suggestPrompts[category] ?? _suggestPrompts['custom']!;
      final prompt = promptTemplate.replaceAll(
        '{context}',
        context?.toString() ?? '',
      );

      final dio = Dio();
      final response = await dio.post(
        '$_defaultBaseUrl/v1/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': _defaultModel,
          'temperature': 0.8,
          'max_tokens': 4000,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        },
      );

      final content =
          response.data['choices'][0]['message']['content'] as String;
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
      return '我是小念，你的专属关怀搭子\n目前AI服务尚未配置，请先在设置中填入 DeepSeek API Key。';
    }

    // 1. 保存用户消息到 DB
    final db = await DatabaseHelper.database;
    await db.insert('chat_history', {
      'id': DatabaseHelper.newId(),
      'role': 'user',
      'content': userMessage,
      'created_at': DateTime.now().toIso8601String(),
    });

    // 2. 构建消息列表（动态 system prompt + 动态历史 + 当前消息）
    final messages = await _buildMessages(userMessage);

    try {
      // 3. 调用 API
      final dio = Dio();
      final response = await dio.post(
        '$_defaultBaseUrl/v1/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': _defaultModel,
          'temperature': 0.7,
          'max_tokens': 4000,
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

      // 异步检查是否需要生成对话摘要
      AiMemoryService.checkAndSummarize();

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

    // 1. 保存用户消息
    final db = await DatabaseHelper.database;
    await db.insert('chat_history', {
      'id': DatabaseHelper.newId(),
      'role': 'user',
      'content': userMessage,
      'created_at': DateTime.now().toIso8601String(),
    });

    // 2. 构建消息列表（动态 prompt + 动态历史）
    final messages = await _buildMessages(userMessage);

    try {
      // 3. 流式调用 API
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
          'max_tokens': 4000,
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

      // 异步检查是否需要生成对话摘要
      AiMemoryService.checkAndSummarize();

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
  static CancelToken? _activeChat;
  @visibleForTesting
  static Dio Function(BaseOptions options)? chatClientFactoryForTesting;
  static Completer<void>? _chatFinished;
  static void cancelCurrentChat() => _activeChat?.cancel('user_cancelled');
  static Future<void> stopAndWait() async {
    cancelCurrentChat();
    await _chatFinished?.future.timeout(const Duration(seconds: 60));
  }

  static Future<String> chatWithTools(
    String userMessage, {
    required void Function(String accumulated) onToken,
    required Future<String> Function(String name, Map<String, dynamic> args)
    onToolCall,
    String? requestId,
    bool hideUserMessage = false,
    String userMessageType = 'message',
  }) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) throw const AiChatException('请先配置模型');
    final request = requestId ?? 'chat:${DatabaseHelper.newId()}';
    final cancel = CancelToken();
    if (_activeChat != null) throw const AiChatException('上一轮尚未结束');
    final finished = Completer<void>();
    _chatFinished = finished;
    _activeChat = cancel;
    final dio = (chatClientFactoryForTesting ?? Dio.new)(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    final toolResults = <String>[];
    try {
      await ChatHistoryService.appendOnce(
        requestId: request,
        role: 'user',
        content: userMessage,
        messageType: userMessageType,
        hidden: hideUserMessage,
      );
      final messages = (await _buildMessages(
        userMessage,
        excludeRequestId: request,
        historyTokenBudget: 18000,
      )).map((m) => Map<String, dynamic>.from(m)).toList();
      for (var round = 0; round <= 6; round++) {
        if (cancel.isCancelled) throw cancel.cancelError!;
        final response = await dio.post(
          '$_defaultBaseUrl/v1/chat/completions',
          cancelToken: cancel,
          options: Options(
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
            },
          ),
          data: {
            'model': _defaultModel,
            'temperature': 0.4,
            'max_tokens': 2500,
            'stream': false,
            'messages': messages,
            'tools': _toolDefinitions,
            if (round == 6) 'tool_choice': 'none',
          },
        );
        _trackCacheUsage(response.data['usage'] as Map<String, dynamic>?);
        final message = Map<String, dynamic>.from(
          response.data['choices'][0]['message'] as Map,
        );
        final calls = message['tool_calls'];
        if (calls is List && calls.isNotEmpty && round < 6) {
          if (calls.length > 12) throw const AiChatException('操作数量过多，请缩小本次任务');
          messages.add(message);
          for (final call in calls) {
            if (cancel.isCancelled) throw cancel.cancelError!;
            final name = call['function']?['name'] as String? ?? '';
            final callId = call['id'] as String?;
            if (callId == null) throw const AiChatException('模型工具响应格式不完整');
            String result;
            Map<String, dynamic>? args;
            try {
              args = Map<String, dynamic>.from(
                jsonDecode(call['function']['arguments'] as String) as Map,
              );
            } catch (_) {
              /* Return a protocol error; never call with empty fabricated args. */
            }
            if (args == null) {
              result = jsonEncode({
                'status': 'failure',
                'verified': true,
                'message': '工具参数必须是完整 JSON，请修正参数后再调用',
              });
            } else {
              final validArgs = args;
              result = await ToolOperationJournal.execute(
                requestId: request,
                tool: name,
                arguments: validArgs,
                action: () => onToolCall(name, validArgs),
              );
            }
            toolResults.add(result);
            messages.add({
              'role': 'tool',
              'tool_call_id': callId,
              'content': result,
            });
          }
          continue;
        }
        var content = message['content'] is String
            ? (message['content'] as String).trim()
            : '';
        if (content.isEmpty && toolResults.isNotEmpty) {
          content = toolResults
              .map((r) {
                try {
                  return (jsonDecode(r) as Map)['message']?.toString() ?? '';
                } catch (_) {
                  return '';
                }
              })
              .where((s) => s.isNotEmpty)
              .join('|||');
        }
        if (content.isEmpty) throw const AiChatException('模型没有返回内容，请重试');
        if (cancel.isCancelled) throw cancel.cancelError!;
        await ChatHistoryService.appendOnce(
          requestId: '$request:assistant',
          role: 'assistant',
          content: content,
        );
        onToken(content);
        AiMemoryService.checkAndSummarize().catchError((_) {});
        return content;
      }
      throw const AiChatException('本轮操作已达上限，请查看已完成的结果');
    } on AiChatException {
      rethrow;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        throw const AiChatException('已停止，已完成的操作仍保留');
      }
      final status = error.response?.statusCode;
      throw AiChatException(
        status == 401 || status == 403
            ? '模型授权失败，请检查 API Key'
            : status == 429
            ? '模型服务繁忙或额度不足，请稍后重试'
            : status == 404
            ? '当前账号无法使用配置的模型，请检查模型能力'
            : '模型请求未完成，已完成的操作仍保留，可安全重试',
      );
    } catch (_) {
      throw const AiChatException('本轮未完整完成，请查看已保存的结果后重试');
    } finally {
      if (identical(_activeChat, cancel)) _activeChat = null;
      finished.complete();
      if (identical(_chatFinished, finished)) _chatFinished = null;
      dio.close();
    }
  }

  /// 获取对话历史
  static Future<List<Map<String, dynamic>>> getChatHistory({
    int limit = 50,
    bool includeHidden = false,
    String? beforeTime,
    String? beforeId,
  }) async {
    final db = await DatabaseHelper.database;
    final filters = <String>[
      if (!includeHidden) 'hidden_at IS NULL',
      if (beforeTime != null) '(created_at < ? OR (created_at = ? AND id < ?))',
    ];
    final rows = await db.query(
      'chat_history',
      where: filters.isEmpty ? null : filters.join(' AND '),
      whereArgs: beforeTime == null
          ? null
          : [beforeTime, beforeTime, beforeId ?? ''],
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.reversed.toList(growable: false);
  }

  /// 调用后台文本模型（用于记忆提取、摘要、Dreaming 整合）。
  ///
  /// 当前统一路由到主 Flash 模型。保留旧方法名兼容现有调用方。
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
        options: Options(
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': AiModelCatalog.primary,
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
    // 重置摘要轮次计数
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('conversation_turns', 0);
    await prefs.remove('summarized_up_to');
  }

  /// 清空所有记忆数据（Wiki 事实 + 摘要 + chunks）
  static Future<void> clearAllMemory() async {
    final db = await DatabaseHelper.database;
    await db.delete('ai_wiki_facts');
    await db.delete('ai_conversation_summaries');
    await db.delete('conversation_chunks');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('conversation_turns', 0);
    await prefs.remove('summarized_up_to');
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
