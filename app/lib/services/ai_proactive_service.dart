/// TaWorld AI 主动消息服务
///
/// 后台评估是否需要主动给用户发消息。
/// 在 WorkManager 后台 Isolate 中运行。
library;

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/local/database_helper.dart';
import 'ai_service.dart';
import 'local/partner_service.dart';
import 'local/local_reminder_service.dart';
import 'weather_service.dart';

/// AI 主动消息服务
abstract final class AiProactiveService {
  /// 检查 AI 主动关怀是否启用
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('ai_proactive_enabled') ?? true;
  }

  /// 设置 AI 主动关怀开关
  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ai_proactive_enabled', enabled);
  }

  /// 后台评估：收集所有 partner 上下文，调用 AI 判断是否主动联系
  ///
  /// 在 WorkManager 后台 Isolate 中调用。
  /// 返回是否生成了待发消息。
  static Future<bool> evaluate() async {
    // 检查开关
    if (!await isEnabled()) return false;

    // 全局冷却检查
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    final lastProactive = prefs.getInt('last_proactive_time');
    if (lastProactive != null) {
      final elapsed = now.difference(
        DateTime.fromMillisecondsSinceEpoch(lastProactive),
      );
      if (elapsed.inHours < 4) return false;
    }

    // 每日上限检查（最多 2 条/天）
    final todayKey = 'proactive_count_${now.year}${now.month}${now.day}';
    final todayCount = prefs.getInt(todayKey) ?? 0;
    if (todayCount >= 2) return false;

    // 夜间静默（22:00~08:00）
    if (now.hour >= 22 || now.hour < 8) return false;

    final partners = await PartnerService.getAll();
    if (partners.isEmpty) return false;

    final key = await AiService.getApiKey();
    if (key == null || key.isEmpty) return false;

    // 收集所有 partner 上下文
    final contexts = <String>[];
    for (final partner in partners) {
      final info = <String>[];
      info.add('名字: ${partner.nickname}');
      info.add('关系: ${partner.type}');
      if (partner.city != null && partner.city!.isNotEmpty) {
        info.add('城市: ${partner.city}');
      }

      // 提醒配置
      final configs = await LocalReminderService.getConfigs(partner.id);
      final enabledConfigs = configs.where((c) => c.enabled).toList();
      if (enabledConfigs.isNotEmpty) {
        info.add('已设提醒: ${enabledConfigs.map((c) => c.categoryLabel).join(', ')}');
      }

      // 距上次联系天数（用关系创建天数近似）
      final days = DateTime.now().difference(partner.createdAt).inDays;
      info.add('认识天数: $days');

      // 天气
      try {
        WeatherResult? weather;
        if (partner.latitude != null && partner.longitude != null) {
          weather = await WeatherService.getCurrentWeather(
            partner.longitude!, partner.latitude!,
          );
        } else if (partner.city != null && partner.city!.isNotEmpty) {
          weather = await WeatherService.getCurrentWeatherByCity(partner.city!);
        }
        if (weather != null) {
          info.add('天气: ${weather.temp}°C ${weather.text}');
        }
      } catch (_) {}

      contexts.add(info.join(', '));
    }

    final hour = now.hour;
    String timeContext;
    if (hour < 12) {
      timeContext = '上午';
    } else if (hour < 14) {
      timeContext = '中午';
    } else if (hour < 18) {
      timeContext = '下午';
    } else {
      timeContext = '晚上';
    }

    final prompt = '''你正在评估是否需要主动给用户发一条关怀消息。

当前时间: ${now.hour}:${now.hour.toString().padLeft(2, '0')} ($timeContext)
用户关心的人:
${contexts.join('\n')}

请评估是否需要主动提醒用户关心某个人。

规则:
1. 只有在有明确理由时才建议主动联系（天气变化、合适的时间问候等）
2. 不要为了发消息而发消息
3. 消息要简短自然，像朋友发微信
4. 不使用emoji和markdown

返回JSON格式（只返回JSON，不要其他文字）:
{"should_notify": true/false, "partner_id": "xxx或null", "category": "weather/greeting/care", "message": "消息内容", "confidence": 0.0-1.0}

如果不需要发消息，返回:
{"should_notify": false, "confidence": 0.0}''';

    try {
      final dio = Dio();
      final response = await dio.post(
        'https://api.deepseek.com/v1/chat/completions',
        options: Options(headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': 'deepseek-v4-flash',
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.7,
          'max_tokens': 300,
        },
      );

      final content = response.data['choices']?[0]?['message']?['content'] as String?;
      if (content == null) return false;

      final result = _parseJson(content);
      if (result == null) return false;
      if (result['should_notify'] != true) return false;

      final confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;
      if (confidence < 0.7) return false;

      final message = result['message'] as String? ?? '';
      if (message.isEmpty) return false;

      // 写入待发消息
      final db = await DatabaseHelper.database;
      final id = DatabaseHelper.newId();
      await db.insert('ai_pending_messages', {
        'id': id,
        'partner_id': result['partner_id'],
        'category': result['category'] ?? 'greeting',
        'message': message,
        'confidence': confidence,
        'status': 'pending',
        'created_at': now.toIso8601String(),
        'shown_at': null,
      });

      // 发送通知
      final bgPlugin = FlutterLocalNotificationsPlugin();
      await bgPlugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      await bgPlugin.show(
        _makeNotificationId(id),
        'AI 关怀提醒',
        message,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'taworld_ai_proactive',
            'AI 关怀消息',
            channelDescription: 'AI 根据上下文主动发送的关怀建议',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: 'ai_proactive',
      );

      // 记录发送时间
      await prefs.setInt('last_proactive_time', now.millisecondsSinceEpoch);
      await prefs.setInt(todayKey, todayCount + 1);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 获取所有待发消息
  static Future<List<Map<String, dynamic>>> getPendingMessages() async {
    final db = await DatabaseHelper.database;
    return db.query(
      'ai_pending_messages',
      where: "status = 'pending'",
      orderBy: 'created_at ASC',
    );
  }

  /// 标记消息为已展示
  static Future<void> markAsShown(String id) async {
    final db = await DatabaseHelper.database;
    await db.update(
      'ai_pending_messages',
      {
        'status': 'shown',
        'shown_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 删除消息
  static Future<void> dismissMessage(String id) async {
    final db = await DatabaseHelper.database;
    await db.update(
      'ai_pending_messages',
      {'status': 'dismissed'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 解析 AI 返回的 JSON（容错处理 markdown 代码块）
  static Map<String, dynamic>? _parseJson(String content) {
    try {
      // 尝试直接解析
      return jsonDecode(content.trim()) as Map<String, dynamic>;
    } catch (_) {
      // 尝试提取 JSON 块
      final match = RegExp(r'\{[^{}]*\}').firstMatch(content);
      if (match != null) {
        try {
          return jsonDecode(match.group(0)!) as Map<String, dynamic>;
        } catch (_) {}
      }
      return null;
    }
  }

  /// 生成通知 ID
  static int _makeNotificationId(String messageId) {
    return messageId.hashCode.abs() % 2147483647;
  }
}
