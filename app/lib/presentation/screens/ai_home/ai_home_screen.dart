/// TaWorld AI 主屏 — AI-First 关怀中枢
///
/// 应用的核心入口，以 AI 对话为主体的智能关怀界面。
/// 包含：轻量状态条、AI 对话流（含主动消息）、快捷芯片、输入栏。
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../services/ai_service.dart';
import '../../../services/ai_proactive_service.dart';
import '../../../services/ai_memory_extractor.dart';
import '../../../services/ai_rag_service.dart';
import '../../../services/ai_memory_dreamer.dart';
import '../../../services/local/local_user_service.dart';
import '../../../services/local/partner_service.dart';
import '../../../services/local/local_reminder_service.dart';
import '../../../services/local/local_achievement_service.dart';
import '../../../services/reminder_scheduler.dart';
import '../../../services/weather_service.dart';
import '../../../data/models/partner.dart';
import '../../../data/models/reminder_config.dart';
import '../../widgets/widgets.dart';

// ============================================================
// 消息模型
// ============================================================

enum ProactiveType { none, greeting, weather, careSuggestion, alert, guide }

class _ChatMessage {
  const _ChatMessage({
    required this.role,
    required this.content,
    this.proactiveType = ProactiveType.none,
    this.weatherData,
    this.actionLabel,
    this.streaming = false,
  });
  final String role;
  final String content;
  final ProactiveType proactiveType;
  final Map<String, dynamic>? weatherData;
  final String? actionLabel;
  final bool streaming;
}

// ============================================================
// AI 主屏
// ============================================================

class AiHomeScreen extends StatefulWidget {
  const AiHomeScreen({super.key});

  @override
  State<AiHomeScreen> createState() => _AiHomeScreenState();
}

class _AiHomeScreenState extends State<AiHomeScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];

  bool _sending = false;
  bool _hasApiKey = true;
  bool _loading = true;
  bool _greeted = false;
  String? _executingTool;

  Map<String, dynamic> _stats = {};
  List<dynamic> _achievements = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final has = await AiService.hasApiKey();
    if (!mounted) return;
    setState(() => _hasApiKey = has);

    // 并行加载基础数据
    try {
      final results = await Future.wait([
        LocalUserService.getStats(),
        LocalAchievementService.getAllWithProgress(),
        AiService.getChatHistory(),
      ]);
      if (!mounted) return;

      setState(() {
        _stats = results[0] as Map<String, dynamic>;
        _achievements = results[1] as List;
        // 加载历史消息（assistant 消息按 ||| 拆分为多条气泡）
        for (final row in results[2] as List) {
          final role = row['role'] as String;
          final content = row['content'] as String;
          if (role == 'assistant' && content.contains('|||')) {
            final parts = content
                .split('|||')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            if (parts.length > 1) {
              for (final part in parts) {
                _messages.add(_ChatMessage(role: role, content: part));
              }
            } else {
              _messages.add(_ChatMessage(role: role, content: content));
            }
          } else {
            _messages.add(_ChatMessage(role: role, content: content));
          }
        }
        _loading = false;
      });
      _scrollToBottom();
      // 生成主动消息
      _generateProactiveMessages();
      // 消费后台 AI 主动消息
      _consumePendingProactiveMessages();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---- 问候语 ----
  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了';
    if (hour < 12) return '早上好';
    if (hour < 14) return '中午好';
    if (hour < 18) return '下午好';
    if (hour < 22) return '晚上好';
    return '夜深了';
  }

  bool get _isEvening {
    final h = DateTime.now().hour;
    return h >= 18 || h < 6;
  }

  // ---- AI 主动消息 ----
  Future<void> _generateProactiveMessages() async {
    if (_greeted || !mounted) return;
    _greeted = true;

    final partners = await PartnerService.getAll();

    if (partners.isEmpty) {
      if (!mounted) return;

      // 检查是否已经展示过欢迎消息（持久化，防止切 Tab 重复播放）
      final prefs = await SharedPreferences.getInstance();
      final welcomeShown = prefs.getBool('welcome_shown') ?? false;
      if (welcomeShown) return;

      // 以 AI 消息形式逐条发送欢迎语，沉浸式引导
      final welcomeMessages = [
        '你好呀，我是小念',
        '我可以帮你关注在乎的人的天气、写温暖的关怀语、设置贴心提醒',
        '不过你现在还没有添加关心的人，先来告诉我一个你在意的人吧',
      ];
      for (int i = 0; i < welcomeMessages.length; i++) {
        if (i > 0) {
          final charCount = welcomeMessages[i].length;
          final delayMs = (charCount * 100).clamp(2000, 8000);
          await Future.delayed(Duration(milliseconds: delayMs));
        }
        if (!mounted) break;
        setState(() {
          _messages.add(_ChatMessage(
            role: 'assistant',
            content: welcomeMessages[i],
          ));
        });
        _scrollToBottom();
      }
      // 标记欢迎消息已展示
      await prefs.setBool('welcome_shown', true);
      return;
    }

    // 1) 天气检查
    await _checkWeatherProactive(partners);

    // 2) 问候 + 摘要
    if (!mounted) return;
    final names = partners.map((p) => p.nickname).toList();
    final nameStr = names.length <= 2
        ? names.join(' 和 ')
        : '${names[0]} 等 ${names.length} 个人';
    final streak = _stats['streakDays'] ?? 0;
    final streakStr = streak > 0 ? '你已经连续关心 $streak 天了，真棒！' : '';

    setState(() {
      _messages.insert(
        0,
        _ChatMessage(
          role: 'assistant',
          content:
              '${_greeting()}\n\n'
              '$nameStr 那边一切正常。$streakStr\n\n'
              '有什么我可以帮你的吗？你可以问我天气、让我写句关怀语，'
              '或者直接和我聊天',
          proactiveType: ProactiveType.greeting,
        ),
      );
    });
    _scrollToBottom();
  }

  Future<void> _checkWeatherProactive(List<Partner> partners) async {
    final alerts = <String>[];
    final normalWeather = <String>[];

    for (final partner in partners) {
      try {
        WeatherResult? weather;
        if (partner.latitude != null && partner.longitude != null) {
          weather = await WeatherService.getCurrentWeather(
              partner.longitude!, partner.latitude!);
        } else if (partner.city != null && partner.city!.isNotEmpty) {
          weather = await WeatherService.getCurrentWeatherByCity(partner.city!);
        }
        if (weather == null) continue;

        final configs = await LocalReminderService.getConfigs(partner.id);
        final weatherConfigs = configs.where((c) => c.category == 'weather');
        final conditions = weatherConfigs.isNotEmpty
            ? (weatherConfigs.first.config['notify_conditions'] as List?)
                    ?.cast<String>() ??
                ['rain', 'snow', 'extreme_cold', 'extreme_heat']
            : ['rain', 'snow', 'extreme_cold', 'extreme_heat'];

        final check = WeatherService.checkConditions(weather, conditions);
        if (check.shouldRemind && check.message != null) {
          alerts.add(check.message!);
        } else {
          normalWeather.add('${partner.nickname} 那边 ${weather.temp}\u00B0C ${weather.text}');
        }
      } catch (_) {}
    }

    if (alerts.isNotEmpty && mounted) {
      setState(() {
        _messages.insert(
          0,
          _ChatMessage(
            role: 'assistant',
            content: alerts.join('\n'),
            proactiveType: ProactiveType.weather,
            actionLabel: '查看详情',
          ),
        );
      });
    }

    if (normalWeather.isNotEmpty && alerts.isEmpty && mounted) {
      setState(() {
        _messages.insert(
          0,
          _ChatMessage(
            role: 'assistant',
            content: '今日天气速览\n${normalWeather.join('\n')}\n\n大家都挺好的，放心~',
            proactiveType: ProactiveType.weather,
            weatherData: {'type': 'summary', 'partners': normalWeather.length},
          ),
        );
      });
    }
  }

  // ---- 消费后台 AI 主动消息 ----
  Future<void> _consumePendingProactiveMessages() async {
    try {
      final pending = await AiProactiveService.getPendingMessages();
      if (pending.isEmpty || !mounted) return;

      for (final msg in pending) {
        final id = msg['id'] as String;
        final content = msg['message'] as String;
        final category = msg['category'] as String? ?? 'greeting';

        ProactiveType type;
        switch (category) {
          case 'weather':
            type = ProactiveType.weather;
            break;
          case 'greeting':
            type = ProactiveType.greeting;
            break;
          case 'care':
            type = ProactiveType.careSuggestion;
            break;
          default:
            type = ProactiveType.alert;
        }

        setState(() {
          _messages.add(_ChatMessage(
            role: 'assistant',
            content: content,
            proactiveType: type,
          ));
        });

        await AiProactiveService.markAsShown(id);
      }
      _scrollToBottom();
    } catch (_) {
      // 静默处理
    }
  }

  // ---- 发送消息（带工具调用）----
  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _messages.add(_ChatMessage(role: 'user', content: text));
      _messages.add(const _ChatMessage(
        role: 'assistant',
        content: '',
        streaming: true,
      ));
      _controller.clear();
      _sending = true;
      _executingTool = null;
    });
    _scrollToBottom();
    await _processAiResponse(text);
  }

  // ---- 工具执行调度 ----
  Future<String> _executeTool(String name, Map<String, dynamic> args) async {
    try {
      switch (name) {
        case 'create_reminder':
          return await _toolCreateReminder(args);
        case 'delete_reminder':
          return await _toolDeleteReminder(args);
        case 'get_partner_weather':
          return await _toolGetWeather(args);
        case 'get_all_partners':
          return await _toolGetAllPartners();
        case 'get_reminder_stats':
          return await _toolGetReminderStats();
        case 'create_partner':
          return await _toolCreatePartner(args);
        case 'update_partner':
          return await _toolUpdatePartner(args);
        case 'get_partner_detail':
          return await _toolGetPartnerDetail(args);
        default:
          return '不支持的操作: $name';
      }
    } catch (e) {
      return '执行失败: $e';
    }
  }

  // ---- 工具: 创建提醒 ----
  Future<String> _toolCreateReminder(Map<String, dynamic> args) async {
    final partnerName = args['partner_name'] as String? ?? '';
    final category = args['category'] as String? ?? 'custom';
    var time = args['time'] as String? ?? '22:00';
    final customMessage = args['message'] as String?;

    // 时间格式校验和修正
    final timeMatch = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time);
    if (timeMatch == null) {
      return '时间格式错误：$time，应为 HH:mm 格式（如 22:00）';
    }
    final hour = int.tryParse(timeMatch.group(1)!) ?? 22;
    final minute = int.tryParse(timeMatch.group(2)!) ?? 0;
    if (hour > 23 || minute > 59) {
      return '时间无效：$time，小时应在0-23之间，分钟应在0-59之间';
    }
    time = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

    // 按名字查找 partner
    final partners = await PartnerService.getAll();
    final partner = partners.where((p) => p.nickname == partnerName).toList();
    if (partner.isEmpty) {
      return '未找到名为"$partnerName"的关心的人，请先添加';
    }

    // 检查是否已有同类别提醒
    final existingConfigs =
        await LocalReminderService.getConfigs(partner.first.id);
    final sameCategory = existingConfigs
        .where((c) => c.category == category && c.enabled)
        .toList();
    if (sameCategory.isNotEmpty) {
      final config = sameCategory.first.config;
      final existingTime = config['target_sleep_time'] ??
          config['meals']?[0]?['target_time'] ?? '';
      return '$partnerName 已有${_categoryLabel(category)}提醒（$existingTime），如需修改请先删除旧的';
    }

    // 根据类别创建配置
    Map<String, dynamic> configData;
    switch (category) {
      case 'sleep':
        configData = {
          'target_sleep_time': time,
          'advance_minutes': 30,
        };
        break;
      case 'meal':
        configData = {
          'meals': [
            {
              'name': customMessage ?? '吃饭',
              'target_time': time,
              'advance_minutes': 15,
            },
          ],
        };
        break;
      case 'weather':
        configData = ReminderConfig.defaultConfigFor('weather');
        break;
      default:
        configData = {};
    }

    await LocalReminderService.createConfig(
      partnerId: partner.first.id,
      category: category,
      config: configData,
    );
    await ReminderScheduler.scheduleAll();

    return '成功为$partnerName 创建了${_categoryLabel(category)}提醒，时间 $time';
  }

  // ---- 工具: 删除提醒 ----
  Future<String> _toolDeleteReminder(Map<String, dynamic> args) async {
    final partnerName = args['partner_name'] as String? ?? '';
    final category = args['category'] as String? ?? '';

    final partners = await PartnerService.getAll();
    final partner = partners.where((p) => p.nickname == partnerName).toList();
    if (partner.isEmpty) {
      return '未找到名为"$partnerName"的关心的人';
    }

    final configs = await LocalReminderService.getConfigs(partner.first.id);
    final matching = configs.where((c) => c.category == category).toList();
    if (matching.isEmpty) {
      return '$partnerName 没有${_categoryLabel(category)}提醒';
    }

    for (final config in matching) {
      await LocalReminderService.deleteConfig(config.id);
    }
    await ReminderScheduler.scheduleAll();

    return '已删除$partnerName 的${_categoryLabel(category)}提醒';
  }

  // ---- 工具: 查天气 ----
  Future<String> _toolGetWeather(Map<String, dynamic> args) async {
    final partnerName = args['partner_name'] as String? ?? '';

    if (partnerName.isEmpty) {
      // 查所有人的天气
      final partners = await PartnerService.getAll();
      final lines = <String>[];
      for (final p in partners) {
        final weather = await _getPartnerWeather(p);
        if (weather != null) {
          lines.add('${p.nickname}: ${weather.temp}°C ${weather.text}');
        } else {
          final err = WeatherService.lastError;
          lines.add('${p.nickname}: 天气查询失败${err != null ? "（$err）" : ""}');
        }
      }
      return partners.isEmpty
          ? '还没有添加关心的人'
          : lines.join('; ');
    }

    final partners = await PartnerService.getAll();
    final partner = partners.where((p) => p.nickname == partnerName).toList();
    if (partner.isEmpty) {
      return '未找到名为"$partnerName"的关心的人';
    }

    final weather = await _getPartnerWeather(partner.first);
    if (weather == null) {
      final err = WeatherService.lastError;
      if (partner.first.city == null || partner.first.city!.isEmpty) {
        return '$partnerName 还没有设置城市，无法查询天气，请先帮用户设置城市';
      }
      if (err != null) {
        return '$partnerName 那边天气查询失败：$err';
      }
      return '$partnerName（城市: ${partner.first.city}）暂无天气数据，可能是城市名不匹配或网络问题';
    }

    // 检查是否有天气预警
    final configs = await LocalReminderService.getConfigs(partner.first.id);
    final weatherConfigs = configs.where((c) => c.category == 'weather');
    final conditions = weatherConfigs.isNotEmpty
        ? (weatherConfigs.first.config['notify_conditions'] as List?)
                ?.cast<String>() ??
            ['rain', 'snow', 'extreme_cold', 'extreme_heat']
        : ['rain', 'snow', 'extreme_cold', 'extreme_heat'];

    final check = WeatherService.checkConditions(weather, conditions);
    if (check.shouldRemind && check.message != null) {
      return '$partnerName 那边现在${weather.text}，${weather.temp}°C。${check.message}';
    }

    final extra = <String>[];
    if (weather.humidity != null) extra.add('湿度${weather.humidity}%');
    if (weather.windDir != null) extra.add(weather.windDir!);

    return '$partnerName 那边现在${weather.text}，${weather.temp}°C${extra.isNotEmpty ? '，${extra.join('，')}' : ''}';
  }

  Future<WeatherResult?> _getPartnerWeather(Partner partner) async {
    try {
      if (partner.latitude != null && partner.longitude != null) {
        return await WeatherService.getCurrentWeather(
          partner.longitude!, partner.latitude!,
        );
      } else if (partner.city != null && partner.city!.isNotEmpty) {
        // 清理城市名：去空格、去掉"市"后缀
        final cleanCity = partner.city!.trim().replaceAll(RegExp(r'[市]$'), '');
        return await WeatherService.getCurrentWeatherByCity(cleanCity);
      }
    } catch (_) {}
    return null;
  }

  // ---- 工具: 获取所有人 ----
  Future<String> _toolGetAllPartners() async {
    final partners = await PartnerService.getAll();
    if (partners.isEmpty) return '还没有添加关心的人';

    final lines = <String>[];
    for (final p in partners) {
      final days = DateTime.now().difference(p.createdAt).inDays;
      final cityInfo = p.city != null && p.city!.isNotEmpty ? '，城市: ${p.city}' : '，城市: 未设置';
      lines.add('${p.nickname}（${p.typeLabel}，认识 $days 天$cityInfo）');
    }
    return '关心的人: ${lines.join('、')}';
  }

  // ---- 工具: 获取提醒统计 ----
  Future<String> _toolGetReminderStats() async {
    final stats = await LocalReminderService.getStats();
    final total = stats['totalCount'] ?? 0;
    final streak = stats['streakDays'] ?? 0;
    final byCategory = stats['byCategory'] as Map<String, int>? ?? {};

    final parts = <String>[];
    parts.add('总共发送过 $total 次提醒');
    if (streak > 0) parts.add('连续关心 $streak 天');
    if (byCategory.isNotEmpty) {
      final catLines = byCategory.entries
          .map((e) => '${_categoryLabel(e.key)} ${e.value}次')
          .join('、');
      parts.add('按类别: $catLines');
    }

    return parts.join('；');
  }

  // ---- 工具: 创建关心的人 ----
  Future<String> _toolCreatePartner(Map<String, dynamic> args) async {
    final nickname = args['nickname'] as String? ?? '';
    final type = args['relationship'] as String? ?? 'other';
    final rawCity = args['city'] as String?;
    // 城市名清理：去空格、去掉"市"后缀
    final city = rawCity != null
        ? rawCity.trim().replaceAll(RegExp(r'[市]$'), '')
        : null;
    final note = args['note'] as String?;

    if (nickname.isEmpty) {
      return '创建失败：需要提供名字';
    }

    // 检查是否已存在同名
    final existing = await PartnerService.getAll();
    if (existing.any((p) => p.nickname == nickname)) {
      return '$nickname 已经在你的关心列表里了，不需要重复添加';
    }

    await PartnerService.add(
      nickname: nickname,
      type: type,
      city: city,
      note: note,
    );
    PartnerService.notifyRefresh();

    // 验证创建结果
    final verify = await PartnerService.getAll();
    final created = verify.where((p) => p.nickname == nickname).toList();
    if (created.isEmpty) {
      return '创建失败：数据库写入异常，请重试';
    }
    final p = created.first;

    final typeLabel = _relationshipLabel(type);
    final cityInfo = p.city != null && p.city!.isNotEmpty ? '，城市已设为${p.city}' : '';

    if (city != null && city.isNotEmpty) {
      return '已成功添加 $nickname（$typeLabel$cityInfo）。\n'
          '请主动告诉用户已经添加成功（包含城市信息），然后问用户是否需要设置提醒。\n'
          '用选择题格式让用户选择提醒类型：[选项:睡觉提醒|吃饭提醒|天气提醒|稍后再说]';
    }
    return '已成功添加 $nickname（$typeLabel）。\n'
        '请主动告诉用户已经添加成功，建议用户设置城市和提醒。\n'
        '先问用户 $nickname 在哪个城市，然后再问是否需要设置提醒。\n'
        '提醒类型用选择题格式：[选项:睡觉提醒|吃饭提醒|天气提醒|稍后再说]';
  }

  // ---- 工具: 查看某人详情 ----
  Future<String> _toolGetPartnerDetail(Map<String, dynamic> args) async {
    final partnerName = args['partner_name'] as String? ?? '';

    final partners = await PartnerService.getAll();
    final partner = partners.where((p) => p.nickname == partnerName).toList();
    if (partner.isEmpty) {
      return '未找到名为"$partnerName"的关心的人';
    }

    final p = partner.first;
    final days = DateTime.now().difference(p.createdAt).inDays;
    final parts = <String>[
      '$partnerName（${p.typeLabel}，认识 $days 天）',
    ];
    if (p.city != null && p.city!.isNotEmpty) {
      parts.add('城市: ${p.city}');
    } else {
      parts.add('城市: 未设置');
    }
    if (p.note != null && p.note!.isNotEmpty) {
      parts.add('描述: ${p.note}');
    }

    // 查询提醒配置
    final configs = await LocalReminderService.getConfigs(p.id);
    final enabled = configs.where((c) => c.enabled).toList();
    if (enabled.isNotEmpty) {
      final categories = enabled.map((c) {
        switch (c.category) {
          case 'sleep':
            final time = c.config['target_sleep_time'] ?? '';
            return '睡觉提醒${time.isNotEmpty ? "($time)" : ""}';
          case 'meal':
            final meals = c.config['meals'] as List?;
            final time = meals != null && meals.isNotEmpty
                ? meals[0]['target_time'] ?? ''
                : '';
            return '吃饭提醒${time.isNotEmpty ? "($time)" : ""}';
          case 'weather':
            return '天气提醒';
          default:
            return c.category;
        }
      }).join('、');
      parts.add('提醒: $categories');
    } else {
      parts.add('提醒: 暂无');
    }

    return parts.join('；');
  }

  // ---- 工具: 更新关心的人 ----
  Future<String> _toolUpdatePartner(Map<String, dynamic> args) async {
    final partnerName = args['partner_name'] as String? ?? '';
    final newNickname = args['new_nickname'] as String?;
    final newType = args['relationship'] as String?;
    final rawCity = args['city'] as String?;
    final city = rawCity != null
        ? rawCity.trim().replaceAll(RegExp(r'[市县区]$'), '')
        : null;
    final note = args['note'] as String?;

    final partners = await PartnerService.getAll();
    final partner = partners.where((p) => p.nickname == partnerName).toList();
    if (partner.isEmpty) {
      return '未找到名为"$partnerName"的关心的人';
    }

    final p = partner.first;
    final changes = <String>[];

    await PartnerService.update(
      p.id,
      nickname: newNickname,
      type: newType,
      city: city,
      note: note,
    );
    PartnerService.notifyRefresh();

    if (newNickname != null && newNickname != partnerName) {
      changes.add('名字改为$newNickname');
    }
    if (newType != null) {
      changes.add('关系改为${_relationshipLabel(newType)}');
    }
    if (city != null) {
      changes.add('城市改为$city');
    }
    if (note != null) {
      changes.add('描述改为$note');
    }

    if (changes.isEmpty) {
      return '${p.nickname}的信息没有变化';
    }

    // 验证更新结果
    final verifyName = newNickname ?? partnerName;
    final verify = await PartnerService.getAll();
    final updated = verify.where((p) => p.nickname == verifyName).toList();
    if (updated.isEmpty) {
      return '更新失败：数据库写入异常，请重试';
    }

    return '已更新$verifyName：${changes.join('、')}';
  }

  String _relationshipLabel(String type) {
    return switch (type) {
      'couple' => '情侣',
      'partner' => '伴侣',
      'family' => '家人',
      'friend' => '朋友',
      'colleague' => '同事',
      'classmate' => '同学',
      _ => '关心的人',
    };
  }

  // ---- 工具名称映射 ----
  String _categoryLabel(String category) {
    return switch (category) {
      'sleep' => '睡觉',
      'meal' => '吃饭',
      'weather' => '天气',
      'custom' => '自定义',
      _ => category,
    };
  }

  String _toolNameLabel(String name) {
    return switch (name) {
      'create_reminder' => '创建提醒',
      'delete_reminder' => '删除提醒',
      'get_partner_weather' => '查询天气',
      'get_all_partners' => '查看关心的人',
      'get_partner_detail' => '查看详情',
      'get_reminder_stats' => '查看统计',
      'create_partner' => '添加关心的人',
      'update_partner' => '修改信息',
      _ => name,
    };
  }

  /// 对话完成后异步执行记忆处理
  ///
  /// 1. 将对话片段存入 RAG 库（用于未来检索）
  /// 2. 调用 Pro 模型提取事实到 Wiki（越用越懂你）
  void _postConversationMemory(String userMessage, String assistantReply) {
    // 1. 存入 RAG 库
    AiRagService.storeConversationChunks(
      userMessage: userMessage,
      assistantReply: assistantReply.replaceAll('|||', ' '),
    ).catchError((_) {});

    // 2. 提取记忆事实（异步，使用 Pro 模型）
    AiMemoryExtractor.extractFromConversation(
      userMessage: userMessage,
      assistantReply: assistantReply.replaceAll('|||', ' '),
    ).catchError((_) {});
  }

  // ---- 快捷芯片 ----

  /// 用户点击选择题按钮，直接发送选项内容（不经过输入框）
  void _sendChoiceMessage(String choice) {
    if (_sending) return;

    setState(() {
      _messages.add(_ChatMessage(role: 'user', content: choice));
      _messages.add(const _ChatMessage(
        role: 'assistant',
        content: '',
        streaming: true,
      ));
      _sending = true;
      _executingTool = null;
    });
    _scrollToBottom();
    _processAiResponse(choice);
  }

  /// 处理 AI 回复（从 _sendMessage 中提取的公共逻辑）
  Future<void> _processAiResponse(String text) async {
    try {
      await AiService.chatWithTools(text,
        onToolCall: (name, args) async {
          if (!mounted) return '操作已取消';
          setState(() => _executingTool = name);
          _scrollToBottom();
          final result = await _executeTool(name, args);
          if (!mounted) return result;
          setState(() => _executingTool = null);
          _scrollToBottom();
          return result;
        },
        onToken: (accumulated) {
          if (!mounted) return;
          setState(() {
            final idx = _messages.lastIndexWhere((m) => m.streaming);
            if (idx >= 0) {
              _messages[idx] = _ChatMessage(
                role: 'assistant',
                content: accumulated,
                streaming: true,
              );
            }
          });
        },
      );

      if (!mounted) return;

      final idx = _messages.lastIndexWhere((m) => m.streaming);
      if (idx >= 0) {
        final fullContent = _messages[idx].content;
        _messages.removeAt(idx);

        _postConversationMemory(text, fullContent);

        final parts = fullContent
            .split('|||')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

        if (parts.isEmpty) {
          _messages.add(_ChatMessage(
            role: 'assistant',
            content: fullContent.trim(),
          ));
        } else {
          for (int i = 0; i < parts.length; i++) {
            if (i > 0) {
              final charCount = parts[i].length;
              final delayMs = (charCount * 100).clamp(2000, 8000);
              await Future.delayed(Duration(milliseconds: delayMs));
            }
            if (!mounted) break;
            setState(() {
              _messages.add(_ChatMessage(role: 'assistant', content: parts[i]));
            });
            _scrollToBottom();
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      final idx = _messages.lastIndexWhere((m) => m.streaming);
      if (idx >= 0) _messages.removeAt(idx);

      setState(() {
        _messages.add(_ChatMessage(
          role: 'assistant',
          content: '抱歉，网络好像出了点问题：$e',
        ));
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _executingTool = null;
        });
      }
      _scrollToBottom();
    }
  }

  /// 将推荐提示词放入输入框，而非直接发送。
  /// 如果输入框已有内容，弹窗确认是否替换。
  Future<void> _putInInputField(String text) async {
    final currentText = _controller.text.trim();
    if (currentText.isEmpty) {
      // 输入框为空，直接填入
      _controller.text = text;
      return;
    }

    // 输入框有内容，检查是否需要弹窗
    final prefs = await SharedPreferences.getInstance();
    final skipAsk = prefs.getBool('chip_replace_without_ask') ?? false;

    if (skipAsk) {
      // 用户之前勾选了"不再提醒"，直接替换
      _controller.text = text;
      return;
    }

    // 弹窗确认
    if (!mounted) return;
    bool dontAskAgain = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: TaRadius.borderLg),
          title: const Text('替换输入内容'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('输入框已有内容，是否清空并填入推荐提示词？'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: dontAskAgain,
                    onChanged: (v) => setDialogState(() => dontAskAgain = v ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '不再提醒',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('替换'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      // 保存"不再提醒"偏好
      if (dontAskAgain) {
        await prefs.setBool('chip_replace_without_ask', true);
      }
      _controller.text = text;
    }
  }

  Future<void> _handleChip(String action) async {
    switch (action) {
      case 'weather':
        _putInInputField('帮我看看大家的天气');
        break;

      case 'goodnight':
        _putInInputField('帮我写一句晚安语');
        break;

      case 'goodmorning':
        _putInInputField('帮我写一句早安语');
        break;

      case 'care':
        _putInInputField('给我一些关心建议');
        break;

      case 'remind_meal':
        _putInInputField('帮我写一条提醒吃饭的消息');
        break;
    }
  }

  // ---- 一键清空消息显示（仅清除视觉展示，不删除历史记录）----
  Future<void> _clearMessagesDisplay() async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: TaRadius.borderLg),
        title: const Text('清空屏幕'),
        content: const Text('确定要清空当前屏幕上的对话内容吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _messages.clear();
    });
  }

  // ---- 清历史（总结 → 写入 Wiki → 清空显示和 DB）----
  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: TaRadius.borderLg),
        title: const Text('清除对话记录'),
        content: const Text(
          '确定要清除当前对话记录吗？\n\n'
          '小念会先将对话内容总结并存入长期记忆，然后清除显示。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // 1. 收集当前所有对话内容
    final conversationMessages = _messages.where(
      (m) => m.role == 'user' || m.role == 'assistant',
    ).toList();

    if (conversationMessages.isNotEmpty) {
      final userParts = conversationMessages
          .where((m) => m.role == 'user')
          .map((m) => m.content)
          .join('\n');
      final assistantParts = conversationMessages
          .where((m) => m.role == 'assistant')
          .map((m) => m.content)
          .join('\n');

      // 2. 异步提取记忆到 Wiki（不阻塞 UI）
      AiMemoryExtractor.extractFromConversation(
        userMessage: userParts,
        assistantReply: assistantParts,
      ).catchError((_) {});

      // 3. 触发记忆整合
      AiMemoryDreamer.dream().catchError((_) => DreamResult());
    }

    // 4. 清除 DB 中的聊天记录
    await AiService.clearChatHistory();

    // 5. 清空显示
    if (mounted) {
      setState(() {
        _messages.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('对话已总结并存入长期记忆')),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: TaAnimation.fast,
          curve: TaAnimation.curve,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    super.build(context); // keep-alive
    final theme = Theme.of(context);

    if (_loading) {
      return const SafeArea(child: TaLoading(message: '加载中...'));
    }

    return SafeArea(
      child: Column(
        children: [
          // ---- 轻量状态条 ----
          _buildStatusBar(theme),

          // ---- API Key 提示 ----
          if (!_hasApiKey) _buildApiKeyBanner(theme),

          // ---- 消息列表 ----
          Expanded(child: _buildMessageList(theme)),

          // ---- 思考中 ----
          if (_sending && !_messages.any((m) => m.streaming))
            _buildThinking(theme),

          // ---- 快捷芯片 + 输入栏 ----
          _buildInputBar(theme),
        ],
      ),
    );
  }

  // ---- 状态条 ----
  Widget _buildStatusBar(ThemeData theme) {
    final streakDays = _stats['streakDays'] ?? 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        TaSpacing.pagePadding, TaSpacing.sm, TaSpacing.pagePadding, TaSpacing.xs,
      ),
      child: Row(
        children: [
          Container(
            width: TaSizes.avatarMd,
            height: TaSizes.avatarMd,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: TaShadows.sm,
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/onboarding_mascot.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: TaSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '小念 · 你的关怀搭子',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (streakDays > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: TaRadius.borderFull,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TaStreakFlame(days: streakDays, iconSize: 16),
                  const SizedBox(width: 2),
                  Text(
                    '$streakDays',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: TaSpacing.xs),
          GestureDetector(
            onTap: () => context.push(Routes.achievements),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: TaRadius.borderFull,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.emoji_events_rounded,
                    size: 18,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '${_achievements.where((a) => a.unlocked == true).length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 清除消息：单击清空显示，长按清除历史（含总结存档）
          if (_messages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: TaSpacing.xs),
              child: GestureDetector(
                onTap: _clearMessagesDisplay,
                onLongPress: _clearHistory,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: TaRadius.borderFull,
                  ),
                  child: Icon(
                    Icons.cleaning_services_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---- API Key Banner ----
  Widget _buildApiKeyBanner(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: TaSpacing.pagePadding,
        vertical: TaSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 18, color: theme.colorScheme.error),
          const SizedBox(width: TaSpacing.xs),
          Expanded(
            child: Text(
              'AI 服务未配置，请先设置 API Key',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          const SizedBox(width: TaSpacing.xs),
          FilledButton.tonal(
            onPressed: () async {
              await context.push(Routes.apiKeys);
              final has = await AiService.hasApiKey();
              if (mounted) setState(() => _hasApiKey = has);
            },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: TaSpacing.md),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('去配置', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ---- 消息列表 ----
  Widget _buildMessageList(ThemeData theme) {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/ai_empty_chat.png',
              width: 72,
              height: 72,
              fit: BoxFit.contain,
            ).animate().scale(duration: 500.ms, curve: TaAnimation.bounce),
            const SizedBox(height: TaSpacing.md),
            Text('小念', style: theme.textTheme.titleLarge),
            const SizedBox(height: TaSpacing.xs),
            Text(
              '有什么想问的，随时告诉我~',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: TaSpacing.pagePadding,
        vertical: TaSpacing.xs,
      ),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        if (msg.proactiveType != ProactiveType.none) {
          return _buildProactiveCard(msg, theme)
              .animate()
              .fadeIn(duration: TaAnimation.normal);
        }
        return _ChatBubble(
          message: msg,
          onChoiceSelected: (choice) => _sendChoiceMessage(choice),
        );
      },
    );
  }

  // ---- 主动消息卡片 ----
  Widget _buildProactiveCard(_ChatMessage msg, ThemeData theme) {
    switch (msg.proactiveType) {
      case ProactiveType.weather:
        return _WeatherCard(message: msg);
      case ProactiveType.greeting:
        return _GreetingCard(message: msg);
      case ProactiveType.guide:
        return _GuideCard(message: msg);
      default:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: TaSpacing.xxs),
          padding: const EdgeInsets.all(TaSpacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: TaRadius.borderMd,
            border: Border.all(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: TaSpacing.xs),
              Expanded(
                child: Text(msg.content,
                    style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
        ).animate().fadeIn(duration: TaAnimation.normal);
    }
  }

  // ---- 思考中 / 执行工具中 ----
  Widget _buildThinking(ThemeData theme) {
    final label = _executingTool != null
        ? '正在${_toolNameLabel(_executingTool!)}...'
        : 'AI 正在思考...';
    final icon = _executingTool != null
        ? Icons.build_rounded
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TaSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const TaThinkingDots(),
          const SizedBox(width: TaSpacing.xs),
          if (icon != null)
            Icon(icon, size: 14, color: theme.colorScheme.primary),
          if (icon != null) const SizedBox(width: 4),
          Text(label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
        ],
      ),
    );
  }

  // ---- 输入栏 ----
  Widget _buildInputBar(ThemeData theme) {
    final chips = _buildChips();

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        TaSpacing.pagePadding,
        TaSpacing.xs,
        TaSpacing.pagePadding,
        TaSpacing.xs + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 快捷芯片
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: chips.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: TaSpacing.xs),
              itemBuilder: (_, i) {
                final chip = chips[i];
                return ActionChip(
                  avatar: Image.asset(chip.$1, width: 18, height: 18),
                  label: Text(chip.$2,
                      style: const TextStyle(fontSize: 13)),
                  onPressed: () => _handleChip(chip.$3),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                );
              },
            ),
          ),
          const SizedBox(height: TaSpacing.xs),
          // 输入框 + 发送
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: TaRadius.borderFull,
                  ),
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: '问我任何关于关怀的问题...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: TaSpacing.md,
                        vertical: TaSpacing.sm,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
              const SizedBox(width: TaSpacing.xs),
              Container(
                decoration: BoxDecoration(
                  gradient: TaGradients.primary(theme.brightness),
                  borderRadius: TaRadius.borderFull,
                ),
                child: IconButton(
                  onPressed: _sending ? null : _sendMessage,
                  icon:
                      const Icon(Icons.send_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<(String, String, String)> _buildChips() {
    final chips = <(String, String, String)>[
      ('assets/images/chip_weather.png', '今日天气', 'weather'),
    ];
    if (_isEvening) {
      chips.add(('assets/images/chip_goodnight.png', '写句晚安语', 'goodnight'));
    } else {
      chips.add(('assets/images/chip_goodmorning.png', '写句早安语', 'goodmorning'));
    }
    chips
      ..add(('assets/images/chip_care.png', '关心建议', 'care'))
      ..add(('assets/images/chip_meal.png', '提醒吃饭', 'remind_meal'));
    return chips;
  }
}

// ============================================================
// 聊天气泡
// ============================================================

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, this.onChoiceSelected});
  final _ChatMessage message;
  final ValueChanged<String>? onChoiceSelected;

  /// 从消息内容中提取选择题选项
  static List<String> _parseChoices(String content) {
    final match = RegExp(r'\[选项:([^\]]+)\]').firstMatch(content);
    if (match == null) return [];
    return match
        .group(1)!
        .split('|')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == 'user';

    // 流式消息：隐藏 ||| 分隔符和选择题标记，空内容时显示输入光标
    String displayContent = message.content;
    if (message.streaming) {
      displayContent = displayContent.replaceAll('|||', '');
    }
    // 移除选择题标记
    displayContent = displayContent
        .replaceAll(RegExp(r'\[选项:[^\]]+\]'), '')
        .trim();

    final choices = _parseChoices(message.content);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: TaSpacing.xxs),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: TaSpacing.md,
          vertical: TaSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: isUser
              ? const BorderRadius.only(
                  topLeft: Radius.circular(TaRadius.md),
                  topRight: Radius.circular(TaRadius.md),
                  bottomLeft: Radius.circular(TaRadius.md),
                  bottomRight: Radius.circular(TaRadius.xs),
                )
              : const BorderRadius.only(
                  topLeft: Radius.circular(TaRadius.md),
                  topRight: Radius.circular(TaRadius.md),
                  bottomLeft: Radius.circular(TaRadius.xs),
                  bottomRight: Radius.circular(TaRadius.md),
                ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            message.streaming && displayContent.isEmpty
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(3, (i) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (isUser
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.onSurface)
                                .withValues(alpha: 0.4),
                          ),
                        ),
                      );
                    }),
                  )
                : Text(
                    displayContent,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isUser
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
            if (choices.isNotEmpty && !message.streaming) ...[
              const SizedBox(height: TaSpacing.sm),
              ..._buildChoiceButtons(theme, isUser, choices),
            ],
          ],
        ),
      ),
    ).animate().fadeIn(duration: TaAnimation.fast, curve: TaAnimation.curve);
  }

  List<Widget> _buildChoiceButtons(ThemeData theme, bool isUser, List<String> choices) {
    return [
      Wrap(
        spacing: TaSpacing.xs,
        runSpacing: TaSpacing.xs,
        children: choices.map((choice) {
          return Material(
            color: isUser
                ? theme.colorScheme.onPrimary.withValues(alpha: 0.2)
                : theme.colorScheme.primaryContainer,
            borderRadius: TaRadius.borderFull,
            child: InkWell(
              borderRadius: TaRadius.borderFull,
              onTap: () => onChoiceSelected?.call(choice),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TaSpacing.md,
                  vertical: 8,
                ),
                child: Text(
                  choice,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isUser
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    ];
  }
}

// ============================================================
// 天气卡片
// ============================================================

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.message});
  final _ChatMessage message;

  /// Detect weather condition from message content and return banner asset.
  String? _weatherBannerAsset() {
    final content = message.content;
    if (content.contains('雨')) return 'assets/images/weather_rain.png';
    if (content.contains('雪')) return 'assets/images/weather_snow.png';
    if (content.contains('酷热') || content.contains('高温')) return 'assets/images/weather_heat.png';
    if (content.contains('极寒') || content.contains('低温')) return 'assets/images/weather_cold.png';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bannerAsset = _weatherBannerAsset();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: TaSpacing.xs),
      decoration: BoxDecoration(
        gradient: TaGradients.sky(theme.brightness),
        borderRadius: TaRadius.borderMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (bannerAsset != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Image.asset(
                bannerAsset,
                height: 60,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(TaSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Image.asset('assets/images/chip_weather.png',
                        width: 24, height: 24),
                    const SizedBox(width: TaSpacing.xs),
                    Text('天气关注',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                        )),
                  ],
                ),
                const SizedBox(height: TaSpacing.xs),
                Text(
                  message.content,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                if (message.actionLabel != null) ...[
                  const SizedBox(height: TaSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: TaSpacing.sm, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: TaRadius.borderFull,
                      ),
                      child: Text(
                        message.actionLabel!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 问候卡片
// ============================================================

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({required this.message});
  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: TaSpacing.xs),
      padding: const EdgeInsets.all(TaSpacing.md),
      decoration: BoxDecoration(
        gradient: TaGradients.warm(theme.brightness),
        borderRadius: TaRadius.borderMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Image.asset('assets/images/ai_empty_chat.png',
                  width: 20, height: 20),
              const SizedBox(width: TaSpacing.xs),
              Text('小念',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.9),
                  )),
            ],
          ),
          const SizedBox(height: TaSpacing.sm),
          Text(
            message.content,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 引导卡片
// ============================================================

class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.message});
  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: TaSpacing.xs),
      padding: const EdgeInsets.all(TaSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: TaRadius.borderMd,
        border: Border.all(
          color: theme.colorScheme.secondaryContainer,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset('assets/images/chip_care.png', width: 20, height: 20),
              const SizedBox(width: TaSpacing.xs),
              Expanded(
                child: Text(message.content, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
          const SizedBox(height: TaSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                final result = await context.push<bool>(Routes.addPartner);
                if (result == true) PartnerService.notifyRefresh();
              },
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: const Text('添加关心的人'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
