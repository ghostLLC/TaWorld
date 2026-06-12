/// TaWorld 关怀建议服务
///
/// 生成温暖、自然的关怀建议，帮助用户想起关心 Ta。
/// 优先使用 AI 生成；无 API Key 或失败时使用本地上下文文案兜底。
library;

import 'dart:math';

import 'ai_service.dart';
import 'weather_service.dart';
import '../data/models/partner.dart';
import '../data/models/reminder_config.dart';

abstract final class CareSuggestionService {
  /// 为某个关心的人生成一条关怀建议
  ///
  /// [partner] 关心的人
  /// [configs] 该人的提醒配置列表（可为空）
  /// [weatherHint] 天气摘要（可为 null）
  static Future<String> generate({
    required Partner partner,
    List<ReminderConfig>? configs,
    WeatherResult? weather,
  }) async {
    // 构建上下文
    final hour = DateTime.now().hour;
    final timeOfDay = _timeOfDayLabel(hour);
    final configCategories = configs?.map((c) => c.category).toList() ?? [];

    // 1. 尝试 AI 生成
    if (await AiService.hasApiKey()) {
      try {
        // 选一个最相关的类别来生成建议
        final category = _pickCategory(hour, configCategories);
        final context = <String, dynamic>{
          'time_of_day': timeOfDay,
          'hour': hour,
          'partner_name': partner.nickname,
          'relationship': partner.typeLabel,
        };
        if (weather != null) {
          context['weather'] = '${weather.text}, ${weather.temp}°C';
          if (weather.windDir != null) context['wind'] = weather.windDir;
        }
        if (configCategories.isNotEmpty) {
          context['active_reminders'] = configCategories;
        }

        final aiResult = await AiService.generateSuggestion(
          category: category,
          context: context,
        );
        // 从主建议和备选里随机选一条，避免每次一样
        final all = [aiResult.suggestion, ...aiResult.alternatives];
        return all[Random().nextInt(all.length)];
      } catch (_) {
        // AI 失败，继续走本地
      }
    }

    // 2. 本地兜底：基于时段 + 天气 + 关系类型生成
    return _localSuggestion(
      hour: hour,
      partner: partner,
      weather: weather,
      configCategories: configCategories,
    );
  }

  /// 根据当前时间和已配置类别选择最合适的类别
  static String _pickCategory(int hour, List<String> configCategories) {
    // 优先选择与当前时段匹配的、已配置的类别
    if (hour >= 6 && hour < 10 && configCategories.contains('meal')) return 'meal';
    if (hour >= 10 && hour < 14 && configCategories.contains('meal')) return 'meal';
    if (hour >= 17 && hour < 20 && configCategories.contains('meal')) return 'meal';
    if (hour >= 21 && configCategories.contains('sleep')) return 'sleep';
    if (configCategories.contains('weather')) return 'weather';

    // 没有匹配的已配置类别时，按时段选
    if (hour >= 21) return 'sleep';
    if ((hour >= 6 && hour < 10) || (hour >= 10 && hour < 14) || (hour >= 17 && hour < 20)) {
      return 'meal';
    }
    return 'custom';
  }

  static String _timeOfDayLabel(int hour) {
    if (hour < 6) return '凌晨';
    if (hour < 9) return '早晨';
    if (hour < 12) return '上午';
    if (hour < 14) return '中午';
    if (hour < 18) return '下午';
    if (hour < 21) return '傍晚';
    return '夜晚';
  }

  // ==================== 本地文案库 ====================

  static String _localSuggestion({
    required int hour,
    required Partner partner,
    WeatherResult? weather,
    required List<String> configCategories,
  }) {
    final name = partner.nickname;
    final pool = <String>[];

    // ---- 天气相关 ----
    if (weather != null) {
      if (weather.temp <= 0) {
        pool.addAll([
          '$name那边只有${weather.temp}°C，问问她有没有穿够衣服 🧣',
          '今天好冷，提醒$name多穿点别着凉了',
        ]);
      } else if (weather.temp >= 35) {
        pool.addAll([
          '$name那边${weather.temp}°C，提醒她注意防暑降暑 🧊',
          '这么热的天，问问$name有没有多喝水 💧',
        ]);
      }
      if (_isRainy(weather.text)) {
        pool.addAll([
          '试试问她：今天带伞了吗？🌂',
          '$name那边在下雨，提醒她带伞出门',
          '下雨天容易堵车，提醒$name早点出门',
        ]);
      }
      if (_isSnowy(weather.text)) {
        pool.addAll([
          '$name那边下雪了，提醒她注意保暖 ❄️',
          '下雪天路滑，提醒$name注意安全',
        ]);
      }
      // 天气正常也可以关心
      if (pool.isEmpty) {
        pool.addAll([
          '$name那边今天${weather.text}，${weather.temp}°C，告诉她天气不错适合出门 ☀️',
          '今天$name那边天气挺好的，可以关心一下',
        ]);
      }
    }

    // ---- 时段相关 ----
    if (hour >= 6 && hour < 9) {
      pool.addAll([
        '早上好~ 问问$name昨晚睡得好吗 ☀️',
        '新的一天，给$name发个早安吧',
        '早餐时间到了，问问$name吃了什么 🥐',
      ]);
    } else if (hour >= 11 && hour < 13) {
      pool.addAll([
        '快到午饭时间了，提醒$name按时吃饭 🍚',
        '问问$name中午想吃什么',
        '午休时间快到了，关心一下她上午累不累',
      ]);
    } else if (hour >= 14 && hour < 17) {
      pool.addAll([
        '下午容易犯困，问问$name要不要来杯咖啡 ☕',
        '下午了，关心一下$name今天过得怎么样',
        '下午茶时间~ 提醒$name休息一下',
      ]);
    } else if (hour >= 17 && hour < 19) {
      pool.addAll([
        '快到晚饭时间了，问问$name今天吃了什么 🍜',
        '下班时间，关心一下$name今天辛不辛苦',
        '晚饭时间到啦，提醒$name好好吃饭',
      ]);
    } else if (hour >= 21) {
      pool.addAll([
        '夜深了，提醒$name早点休息 🌙',
        '问问$name今天过得怎么样，道个晚安吧 ✨',
        '快睡觉了，给$name说声晚安 💤',
        '该放下手机了，提醒$name早点睡',
      ]);
    } else {
      pool.addAll([
        '想$name了就发条消息吧 💝',
        '随便聊聊天也是很好的关心',
        '问问$name最近在忙什么',
        '一句简单的"在干嘛"也是温暖 ☀️',
      ]);
    }

    // ---- 关系类型相关 ----
    if (partner.type == 'couple') {
      pool.addAll([
        '给$name分享一首你最近听的歌 🎵',
        '问问$name周末想做什么，一起安排',
      ]);
    } else if (partner.type == 'family') {
      pool.addAll([
        '好久没打电话了，问问$name最近身体怎么样',
        '给$name分享一下你最近的生活吧',
      ]);
    } else if (partner.type == 'friend') {
      pool.addAll([
        '最近有没有什么好玩的事？分享给$name吧',
        '问问$name周末有没有空，一起出去玩',
      ]);
    }

    // 随机选一条返回
    return pool[Random().nextInt(pool.length)];
  }

  static bool _isRainy(String text) {
    const keywords = ['小雨', '中雨', '大雨', '暴雨', '阵雨', '雷阵雨'];
    return keywords.any(text.contains);
  }

  static bool _isSnowy(String text) {
    const keywords = ['小雪', '中雪', '大雪', '暴雪', '雨夹雪'];
    return keywords.any(text.contains);
  }
}
