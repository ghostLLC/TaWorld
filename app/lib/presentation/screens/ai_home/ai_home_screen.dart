/// TaWorld AI 主屏 — AI-First 关怀中枢
///
/// 应用的核心入口，以 AI 对话为主体的智能关怀界面。
/// 包含：轻量状态条、AI 对话流（含主动消息）、快捷芯片、输入栏。
library;

import '../reminder_health/reminder_health_screen.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:timezone/timezone.dart' as tz;

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/models/reminder_occurrence_record.dart';
import '../../../services/ai_service.dart';
import '../../../services/partner_selection.dart';
import '../../../services/reminder_edit_service.dart';
import '../../../services/reminder_health_service.dart';
import '../../../services/chat_history_service.dart';
import '../../../services/ai_proactive_service.dart';
import '../../../services/ai_memory_extractor.dart';
import '../../../services/ai_rag_service.dart';
import '../../../services/ai_memory_dreamer.dart';
import '../../../services/local/local_user_service.dart';
import '../../../services/local/partner_service.dart';
import '../../../services/local/local_reminder_service.dart';
import '../../../services/local/local_achievement_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/background_execution_service.dart';
import '../../../services/reminder_scheduler.dart';
import '../../../services/reminder_occurrence_service.dart';
import '../../../services/reminder_tool_planner.dart';
import '../../../services/image_understanding_service.dart';
import '../../../services/timezone_service.dart';
import '../../../services/weather_service.dart';
import '../../../data/models/partner.dart';
import '../../widgets/widgets.dart';
import 'conversation_activity.dart';
import 'conversation_presentation.dart';
import 'ai_quick_action_chip.dart';
import 'milestone_message_card.dart';
import 'retry_message_card.dart';
import 'reminder_follow_up_card.dart';
import 'tool_execution_result.dart';
import 'ai_voice_input_button.dart';
import 'ai_image_input_button.dart';
import 'chat_image_bubble.dart';

// ============================================================
// 消息模型
// ============================================================

enum ProactiveType { none, greeting, weather, careSuggestion, alert, guide }

class AiChatLaunchRequest {
  const AiChatLaunchRequest({required this.partnerName});

  final String partnerName;
}

class _ChatMessage {
  const _ChatMessage({
    this.id,
    required this.role,
    required this.content,
    this.proactiveType = ProactiveType.none,
    this.weatherData,
    this.actionLabel,
    this.streaming = false,
    this.milestone,
    this.retryText,
    this.requestId,
    this.reminderOccurrence,
    this.localImagePath,
  });
  final String? id;
  final String role;
  final String content;
  final ProactiveType proactiveType;
  final Map<String, dynamic>? weatherData;
  final String? actionLabel;
  final bool streaming;
  final ToolMilestone? milestone;
  final String? retryText;
  final String? requestId;
  final ReminderOccurrenceRecord? reminderOccurrence;
  final String? localImagePath;
}

// ============================================================
// AI 主屏
// ============================================================

class AiHomeScreen extends StatefulWidget {
  const AiHomeScreen({super.key, this.draftNotifier});

  /// 来自关心图谱等外部入口的待发送上下文。
  final ValueNotifier<AiChatLaunchRequest?>? draftNotifier;

  @override
  State<AiHomeScreen> createState() => _AiHomeScreenState();
}

class _AiHomeScreenState extends State<AiHomeScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _controller = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  final _speech = stt.SpeechToText();
  final _imagePicker = ImagePicker();

  bool _sending = false;
  bool _hasOlder = false, _loadingOlder = false;
  String? _oldestTime, _oldestId, _historyError;
  bool _speechInitialized = false;
  bool _isListening = false;
  bool _processingImage = false;
  String _voicePrefix = '';
  bool _hasApiKey = true;
  bool _loading = true;
  bool _greeted = false;
  AiActivityPhase _activityPhase = AiActivityPhase.idle;
  String? _executingTool;

  Map<String, dynamic> _stats = {};
  List<dynamic> _achievements = [];

  @override
  void initState() {
    super.initState();
    widget.draftNotifier?.addListener(_consumeExternalDraft);
    _init();
  }

  @override
  void didUpdateWidget(covariant AiHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draftNotifier == widget.draftNotifier) return;
    oldWidget.draftNotifier?.removeListener(_consumeExternalDraft);
    widget.draftNotifier?.addListener(_consumeExternalDraft);
  }

  void _consumeExternalDraft() {
    final launch = widget.draftNotifier?.value;
    if (launch == null) return;
    if (_sending) {
      Future<void>.delayed(const Duration(milliseconds: 240), () {
        if (mounted) _consumeExternalDraft();
      });
      return;
    }
    widget.draftNotifier?.value = null;
    final requestId = 'graph-chat:${DatabaseHelper.newId()}';
    final prompt =
        '用户刚从关心图谱点开了${launch.partnerName}。请结合已有记忆，主动发起一个简短、自然、具体的问题，'
        '带用户继续关心Ta的天气、近况或提醒。只发一句，不要让用户先复述，也不要解释页面入口。';
    setState(() {
      _sending = true;
      _activityPhase = AiActivityPhase.waitingForReply;
    });
    _scrollToBottom();
    final fallback = '我在。最近想先聊聊${launch.partnerName}的天气、近况，还是提醒？';
    if (!_hasApiKey) {
      _appendAssistantFallback(
        requestId: requestId,
        content: fallback,
      ).whenComplete(() {
        if (!mounted) return;
        setState(() {
          _sending = false;
          _activityPhase = AiActivityPhase.idle;
        });
      });
      return;
    }
    _processAiResponse(
      prompt,
      requestId: requestId,
      hideUserMessage: true,
      recordConversationMemory: false,
      fallbackAssistantText: fallback,
    );
  }

  Future<void> _appendAssistantFallback({
    required String requestId,
    required String content,
  }) async {
    final record = await ChatHistoryService.appendOnce(
      requestId: '$requestId:fallback',
      role: 'assistant',
      content: content,
      messageType: 'launch_question',
      metadata: const {'source': 'care_graph_fallback'},
    );
    if (!mounted) return;
    setState(() {
      _messages.add(
        _ChatMessage(id: record.id, role: 'assistant', content: content),
      );
    });
    _scrollToBottom();
  }

  Future<void> _init() async {
    try {
      final has = await AiService.hasApiKey();
      if (mounted) setState(() => _hasApiKey = has);
    } catch (_) {
      /* Service configuration does not hide local history. */
    }
    try {
      _stats = await LocalUserService.getStats();
    } catch (_) {}
    try {
      _achievements = await LocalAchievementService.getAllWithProgress();
    } catch (_) {}
    try {
      final history = await AiService.getChatHistory();
      final messages = await _decodeHistoryRows(history);
      if (!mounted) return;
      setState(() {
        final known = _messages.map((m) => m.id).whereType<String>().toSet();
        _messages.insertAll(0, messages.where((m) => !known.contains(m.id)));
        _setHistoryCursor(history);
        _historyError = null;
        _loading = false;
      });
      _scrollToBottom();
      _generateProactiveMessages();
      _consumePendingProactiveMessages();
      _loadReminderFollowUps();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _historyError = '对话暂未读出，点击重试；这不代表历史已丢失';
        });
      }
    }
  }

  void _setHistoryCursor(List<Map<String, dynamic>> rows) {
    _hasOlder = rows.length == 50;
    if (rows.isNotEmpty) {
      _oldestTime = rows.first['created_at'] as String;
      _oldestId = rows.first['id'] as String;
    }
  }

  Future<List<_ChatMessage>> _decodeHistoryRows(
    List<Map<String, dynamic>> rows,
  ) async {
    final attachments = await ChatHistoryService.getAttachmentsByMessageIds(
      rows
          .where((r) => r['message_type'] == 'image')
          .map((r) => r['id'] as String),
    );
    final messages = <_ChatMessage>[];
    for (final row in rows) {
      final id = row['id'] as String,
          role = row['role'] as String,
          content = row['content'] as String;
      if (row['message_type'] == 'image') {
        messages.add(
          _ChatMessage(
            id: id,
            role: role,
            content: content,
            localImagePath: attachments[id]?['local_path'] as String?,
          ),
        );
      } else if (row['message_type'] == 'milestone') {
        messages.add(
          _ChatMessage(
            id: id,
            role: role,
            content: content,
            milestone: _decodeMilestone(row['metadata_json'] as String?),
          ),
        );
      } else if (role == 'assistant') {
        for (final part in splitAssistantPresentationSegments(content)) {
          messages.add(_ChatMessage(id: id, role: role, content: part));
        }
      } else {
        messages.add(_ChatMessage(id: id, role: role, content: content));
      }
    }
    return messages;
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasOlder) return;
    setState(() => _loadingOlder = true);
    final previousMax = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final previousOffset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    try {
      final rows = await AiService.getChatHistory(
        beforeTime: _oldestTime,
        beforeId: _oldestId,
      );
      final messages = await _decodeHistoryRows(rows);
      if (!mounted) return;
      setState(() {
        _messages.insertAll(0, messages);
        _setHistoryCursor(rows);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(
            (previousOffset +
                    _scrollController.position.maxScrollExtent -
                    previousMax)
                .clamp(0, _scrollController.position.maxScrollExtent),
          );
        }
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('更早的对话暂未读出，请重试')));
      }
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _loadReminderFollowUps() async {
    List<ReminderOccurrenceRecord> pending;
    try {
      pending = await ReminderOccurrenceService.pendingFollowUps();
    } catch (_) {
      // Import/restore and widget teardown may close the shared database while
      // this optional background query is still queued. It must never surface
      // as a page error or an uncaught lifecycle exception.
      return;
    }
    if (!mounted || pending.isEmpty) return;
    setState(() {
      for (final occurrence in pending) {
        final alreadyShown = _messages.any(
          (message) => message.reminderOccurrence?.id == occurrence.id,
        );
        if (!alreadyShown) {
          _messages.add(
            _ChatMessage(
              role: 'system',
              content: occurrence.message ?? '',
              reminderOccurrence: occurrence,
            ),
          );
        }
      }
    });
    _scrollToBottom();
  }

  ToolMilestone? _decodeMilestone(String? metadataJson) {
    if (metadataJson == null || metadataJson.isEmpty) return null;
    try {
      final decoded = jsonDecode(metadataJson) as Map<String, dynamic>;
      final milestone = decoded['milestone'];
      if (milestone is! Map) return null;
      return ToolMilestone.fromMap(Map<String, dynamic>.from(milestone));
    } catch (_) {
      return null;
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

      final prefs = await SharedPreferences.getInstance();
      // 兼容旧版本：welcome_shown 只表示开场介绍曾展示，不代表已完成引导。
      final introShown =
          prefs.getBool('welcome_intro_shown') ??
          prefs.getBool('welcome_shown') ??
          false;
      final plan = planOnboardingEntry(
        hasPartners: false,
        introShown: introShown,
      );

      if (plan != OnboardingEntryPlan.none) {
        setState(() => _activityPhase = AiActivityPhase.onboarding);
        _scrollToBottom();
      }

      if (plan == OnboardingEntryPlan.introAndPrompt) {
        const welcomeMessages = ['你好呀，我是小念', '我可以帮你关注在乎的人的天气、写温暖的关怀语、设置贴心提醒'];
        const requestIds = [
          'onboarding:intro:hello',
          'onboarding:intro:capability',
        ];
        for (var index = 0; index < welcomeMessages.length; index++) {
          await Future.delayed(
            Duration(milliseconds: index == 0 ? 1800 : 2100),
          );
          if (!mounted) return;
          await _appendOnboardingMessage(
            requestId: requestIds[index],
            content: welcomeMessages[index],
          );
        }
        await prefs.setBool('welcome_intro_shown', true);
      }

      if (!mounted || plan == OnboardingEntryPlan.none) return;
      await Future.delayed(const Duration(milliseconds: 2100));
      if (!mounted) return;
      await _appendOnboardingMessage(
        requestId: 'onboarding:prompt:person',
        content: '先来告诉我一个你在意的人吧',
      );
      if (!mounted) return;
      setState(() => _activityPhase = AiActivityPhase.idle);
      _scrollToBottom();
      _focusComposer();
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

  Future<void> _appendOnboardingMessage({
    required String requestId,
    required String content,
  }) async {
    final alreadyVisible = _messages.any(
      (message) => message.role == 'assistant' && message.content == content,
    );
    if (!alreadyVisible && mounted) {
      setState(() {
        _messages.add(_ChatMessage(role: 'assistant', content: content));
      });
      _scrollToBottom();
    }

    final result = await ChatHistoryService.appendOnce(
      requestId: requestId,
      role: 'assistant',
      content: content,
      messageType: 'onboarding',
      metadata: const {'source': 'local_onboarding'},
    );
    if (!mounted || !result.inserted || !alreadyVisible) return;
  }

  Future<void> _checkWeatherProactive(List<Partner> partners) async {
    final alerts = <String>[];
    final normalWeather = <String>[];

    for (final partner in partners) {
      try {
        WeatherResult? weather;
        if (partner.latitude != null && partner.longitude != null) {
          weather = await WeatherService.getCurrentWeather(
            partner.longitude!,
            partner.latitude!,
          );
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
          normalWeather.add(
            '${partner.nickname} 那边 ${weather.temp}\u00B0C ${weather.text}',
          );
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
            content:
                '今日天气速览\n${normalWeather.join('\n')}\n\n以上仅为当地天气，不代表人物当前状态。',
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
          _messages.add(
            _ChatMessage(
              role: 'assistant',
              content: content,
              proactiveType: type,
            ),
          );
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

    _controller.clear();
    await _sendText(text);
  }

  Future<void> _sendText(String text) async {
    if (text.trim().isEmpty || _sending) return;

    final requestId = 'chat:${DatabaseHelper.newId()}';

    setState(() {
      _messages.add(
        _ChatMessage(role: 'user', content: text, requestId: requestId),
      );
      _sending = true;
      _executingTool = null;
      _activityPhase = AiActivityPhase.waitingForReply;
    });
    _scrollToBottom();
    await _processAiResponse(text, requestId: requestId);
  }

  Future<void> _toggleVoiceInput() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    try {
      if (!_speechInitialized) {
        _speechInitialized = await _speech.initialize(
          onStatus: (status) {
            if (!mounted) return;
            if (status == 'done' || status == 'notListening') {
              setState(() => _isListening = false);
            }
          },
          onError: (_) {
            if (mounted) setState(() => _isListening = false);
          },
        );
      }
      if (!_speechInitialized) {
        _showComposerMessage('当前设备暂不支持语音识别');
        return;
      }
      final locales = await _speech.locales();
      final zhLocale = locales
          .where((locale) => locale.localeId.toLowerCase().startsWith('zh'))
          .map((locale) => locale.localeId)
          .firstOrNull;
      _voicePrefix = _controller.text.trimRight();
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          final recognized = result.recognizedWords.trim();
          final combined = [
            if (_voicePrefix.isNotEmpty) _voicePrefix,
            if (recognized.isNotEmpty) recognized,
          ].join(' ');
          _controller.value = TextEditingValue(
            text: combined,
            selection: TextSelection.collapsed(offset: combined.length),
          );
        },
        listenOptions: stt.SpeechListenOptions(
          localeId: zhLocale,
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
          pauseFor: const Duration(seconds: 3),
        ),
      );
      if (mounted) setState(() => _isListening = true);
    } catch (_) {
      if (mounted) {
        setState(() => _isListening = false);
        _showComposerMessage('没有听清，请检查麦克风权限后再试');
      }
    }
  }

  void _showComposerMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _chooseImageSource() async {
    if (_sending || _processingImage) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            TaSpacing.pagePadding,
            0,
            TaSpacing.pagePadding,
            TaSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('拍一张'),
                subtitle: const Text('用相机记录此刻'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('从相册选择'),
                subtitle: const Text('让小念帮你理解图片'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    await _pickAndUnderstandImage(source);
  }

  Future<void> _pickAndUnderstandImage(ImageSource source) async {
    StoredImageAttachment? stored;
    var persisted = false;
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 86,
      );
      if (picked == null || !mounted) return;
      setState(() {
        _processingImage = true;
        _sending = true;
        _executingTool = 'understand_image';
        _activityPhase = AiActivityPhase.executingTool;
      });
      stored = await ImageUnderstandingService.storeLocalCopy(
        File(picked.path),
      );
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMessage(
            role: 'user',
            content: '正在理解这张图片…',
            localImagePath: stored!.localPath,
          ),
        );
      });
      _scrollToBottom();

      final understanding = await ImageUnderstandingService.analyze(
        File(stored.localPath),
      );
      final messageId = await ImageUnderstandingService.persistUnderstanding(
        attachment: stored,
        understanding: understanding,
      );
      persisted = true;
      final receipt = ImageUnderstandingService.memoryReceipt(understanding);
      ToolMilestone? memoryMilestone;
      ChatHistoryWriteResult? receiptRecord;
      if (receipt != null) {
        memoryMilestone = ToolMilestone(
          status: ToolExecutionStatus.information,
          title: receipt.title,
          detail: receipt.detail,
        );
        receiptRecord = await ChatHistoryService.append(
          role: 'system',
          content: '${receipt.title}：${receipt.detail}',
          messageType: 'milestone',
          metadata: {
            'source': 'image_memory',
            'image_message_id': messageId,
            'milestone': memoryMilestone.toMap(),
          },
        );
      }
      if (!mounted) return;
      final index = _messages.lastIndexWhere(
        (message) => message.localImagePath == stored!.localPath,
      );
      setState(() {
        if (index >= 0) {
          _messages[index] = _ChatMessage(
            id: messageId,
            role: 'user',
            content: understanding.summary,
            localImagePath: stored!.localPath,
          );
        }
        if (memoryMilestone != null && receiptRecord != null) {
          _messages.add(
            _ChatMessage(
              id: receiptRecord.id,
              role: 'system',
              content: '${memoryMilestone.title}：${memoryMilestone.detail}',
              milestone: memoryMilestone,
            ),
          );
        }
        _processingImage = false;
        _executingTool = null;
        _activityPhase = AiActivityPhase.waitingForReply;
      });

      final facts = understanding.facts.isEmpty
          ? '没有额外的长期事实'
          : understanding.facts.map((fact) => '- $fact').join('\n');
      final prompt =
          '用户刚发送了一张图片。图片客观概述：${understanding.summary}\n'
          '从图片中确认的事实：\n$facts\n'
          '请结合已有上下文自然回应；如果适合继续关怀或设置提醒，只问一个简短的下一步问题。'
          '不要复述分析规则，也不要声称看到了未确认的信息。';
      await _processAiResponse(
        prompt,
        requestId: 'image-context:$messageId',
        hideUserMessage: true,
        hiddenMessageType: 'image_context',
        recordConversationMemory: false,
      );
    } catch (error) {
      if (stored != null && !persisted) {
        final file = File(stored.localPath);
        if (await file.exists()) await file.delete();
      }
      if (!mounted) return;
      setState(() {
        if (!persisted) {
          _messages.removeWhere(
            (message) => message.localImagePath == stored?.localPath,
          );
        }
        _processingImage = false;
        _sending = false;
        _executingTool = null;
        _activityPhase = AiActivityPhase.idle;
      });
      _showComposerMessage(error.toString());
    }
  }

  // ---- 工具执行调度 ----
  Future<ToolExecutionResult> _executeTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    try {
      if (const {
            'create_reminder',
            'delete_reminder',
            'update_partner',
            'get_partner_weather',
            'get_partner_detail',
          }.contains(name) &&
          args['subject'] != 'self' &&
          !const {'我', '自己', '本人', '用户'}.contains(args['partner_name']) &&
          !(name == 'get_partner_weather' &&
              args['partner_id'] == null &&
              (args['partner_name'] ?? '') == '')) {
        final person = PartnerSelection.resolve(
          await PartnerService.getAll(),
          id: args['partner_id'] as String?,
          name: args['partner_name'] as String?,
        );
        args = {
          ...args,
          'partner_id': person.id,
          'partner_name': person.nickname,
        };
      }
      switch (name) {
        case 'update_reminder':
          final saved = await ReminderEditService.update(args);
          try {
            await ReminderScheduler.scheduleAll();
          } catch (_) {
            return ToolExecutionResult.partialSuccess(
              toolName: name,
              modelMessage: '修改已保存，系统通知尚未同步，请查看提醒检查',
              title: '提醒已更新',
              detail: '通知待同步',
              entityId: saved.id,
              verified: true,
            );
          }
          await ReminderHealthService.check();
          final pending =
              ReminderHealthService.current.value?.issues ?? const <String>[];
          if (saved.enabled && pending.isNotEmpty) {
            return ToolExecutionResult.partialSuccess(
              toolName: name,
              modelMessage: '修改已保存；${pending.join('；')}',
              title: '提醒已更新',
              detail: pending.first,
              entityId: saved.id,
              verified: true,
            );
          }
          return ToolExecutionResult.success(
            toolName: name,
            modelMessage: '已保存并回读：${jsonEncode(saved.toMap())}',
            title: saved.enabled ? '提醒已更新' : '提醒已暂停',
            detail: saved.enabled ? '已同步未来的提醒安排' : '暂停期间不会安排这条提醒',
            entityId: saved.id,
            verified: true,
          );
        case 'get_reminders':
          final all = await LocalReminderService.getAllConfigs();
          return ToolExecutionResult.information(
            toolName: name,
            modelMessage: jsonEncode([
              for (final group in all.values)
                for (final c in group) c.toMap(),
            ]),
          );
        case 'get_capabilities':
          await ReminderHealthService.check();
          return ToolExecutionResult.information(
            toolName: name,
            modelMessage: jsonEncode({
              'person_create_update': true,
              'reminders_create_update_pause': true,
              'one_time_daily_weekdays': true,
              'weather_monitoring': 'device_best_effort',
              'send_to_friend': false,
              'notification': ReminderHealthService.current.value?.summary,
            }),
          );
        case 'create_reminder':
          return await _toolCreateReminder(args);
        case 'delete_reminder':
          return await _toolDeleteReminder(args);
        case 'get_partner_weather':
          return ToolExecutionResult.information(
            toolName: name,
            modelMessage: await _toolGetWeather(args),
          );
        case 'get_all_partners':
          return ToolExecutionResult.information(
            toolName: name,
            modelMessage: await _toolGetAllPartners(),
          );
        case 'get_reminder_stats':
          return ToolExecutionResult.information(
            toolName: name,
            modelMessage: await _toolGetReminderStats(),
          );
        case 'create_partner':
          return await _toolCreatePartner(args);
        case 'update_partner':
          return await _toolUpdatePartner(args);
        case 'get_partner_detail':
          return ToolExecutionResult.information(
            toolName: name,
            modelMessage: await _toolGetPartnerDetail(args),
          );
        default:
          return ToolExecutionResult.information(
            toolName: name,
            modelMessage: '不支持的操作: $name',
          );
      }
    } catch (e) {
      if (_isStateChangingTool(name)) {
        return ToolExecutionResult.failure(
          toolName: name,
          modelMessage: '执行失败: $e',
          title: '操作未完成',
          detail: '操作未完整完成，请检查现有记录后重试',
        );
      }
      return ToolExecutionResult.information(
        toolName: name,
        modelMessage: '执行失败: $e',
      );
    }
  }

  bool _isStateChangingTool(String name) => const {
    'create_reminder',
    'update_reminder',
    'delete_reminder',
    'create_partner',
    'update_partner',
  }.contains(name);

  // ---- 工具: 创建提醒 ----
  Future<ToolExecutionResult> _toolCreateReminder(
    Map<String, dynamic> args,
  ) async {
    final parseResult = ReminderToolPlanner.parse(args);
    final plan = parseResult.plan;
    if (plan == null) {
      final message = parseResult.error ?? '提醒参数不完整';
      return ToolExecutionResult.failure(
        toolName: 'create_reminder',
        modelMessage: message,
        title: '提醒未创建',
        detail: message,
      );
    }

    Partner? partner;
    if (!plan.isSelfReminder) {
      final partners = await PartnerService.getAll();
      final matchingPartners = partners
          .where(
            (partner) => args['partner_id'] != null
                ? partner.id == args['partner_id']
                : partner.nickname == plan.partnerName,
          )
          .toList();
      if (matchingPartners.isEmpty) {
        final message = '未找到名为"${plan.partnerName}"的关心的人，请先添加';
        return ToolExecutionResult.failure(
          toolName: 'create_reminder',
          modelMessage: message,
          title: '提醒未创建',
          detail: message,
        );
      }
      partner = matchingPartners.first;
    }

    if (plan.isSelfReminder && plan.category == 'weather') {
      return ToolExecutionResult.failure(
        toolName: 'create_reminder',
        modelMessage: '自己的天气提醒还需要先确认当前位置，请先创建睡觉或吃饭提醒',
        title: '天气提醒未创建',
        detail: '需要先补充用户所在地',
        verified: true,
      );
    }

    if (plan.monitorsWeatherChanges &&
        partner?.city?.isNotEmpty != true &&
        (partner?.latitude == null || partner?.longitude == null)) {
      final message = '${plan.partnerName}还没有所在地，无法监测当地天气变化。请先确认城市';
      return ToolExecutionResult.failure(
        toolName: 'create_reminder',
        modelMessage: message,
        title: '天气监测未开启',
        detail: '需要先补充${plan.partnerName}的所在地',
        entityId: partner?.id,
        verified: true,
      );
    }

    String? timezoneId;
    if (plan.timezoneMode == 'partner') {
      timezoneId = ReminderToolPlanner.resolveTimezoneId(
        plan: plan,
        partner: partner!,
      );
      if (timezoneId == null) {
        final explicit = plan.timezoneId?.trim();
        final message = explicit?.isNotEmpty == true
            ? '时区 $explicit 无效，请使用 IANA 时区（如 Asia/Singapore）'
            : '还不能确定${plan.partnerName}的当地时区。请先确认所在地或 IANA 时区，再创建按Ta当地时间执行的提醒';
        return ToolExecutionResult.failure(
          toolName: 'create_reminder',
          modelMessage: message,
          title: '提醒未创建',
          detail: '需要确认${plan.partnerName}的当地时区',
          entityId: partner.id,
          verified: true,
        );
      }
    }

    // 两种天气提醒可以并存；同一种天气模式或其他同类别提醒不重复创建。
    final subjectKind = plan.isSelfReminder ? 'user' : 'partner';
    final subjectId = plan.isSelfReminder ? 'self' : partner!.id;
    final existingConfigs = await LocalReminderService.getConfigsForSubject(
      subjectKind,
      subjectId,
    );
    final sameCategory = existingConfigs.where((config) {
      if (!config.enabled || config.category != plan.category) return false;
      if (plan.category == 'custom') {
        return jsonEncode(config.config) == jsonEncode(plan.config);
      }
      if (plan.category != 'weather') return true;
      final existingMode = config.config['mode'] ?? 'daily_digest';
      return existingMode == plan.config['mode'];
    }).toList();
    if (sameCategory.isNotEmpty) {
      final config = sameCategory.first.config;
      final existingTime =
          config['target_sleep_time'] ??
          config['meals']?[0]?['target_time'] ??
          config['digest_time'] ??
          '${config['monitor_start'] ?? '07:00'}–${config['monitor_end'] ?? '23:00'}';
      final reminderLabel = _reminderPlanLabel(plan);
      final message =
          '${plan.partnerName}已有$reminderLabel（$existingTime），如用户要求修改，请调用 update_reminder，reminder_id=${sameCategory.first.id}';
      return ToolExecutionResult.failure(
        toolName: 'create_reminder',
        modelMessage: message,
        title: '提醒未创建',
        detail: message,
        entityId: sameCategory.first.id,
        verified: true,
      );
    }

    final created = await LocalReminderService.createConfig(
      partnerId: partner?.id ?? '',
      category: plan.category,
      config: plan.config,
      timezoneMode: plan.timezoneMode,
      timezoneId: timezoneId,
      subjectKind: subjectKind,
      subjectId: subjectId,
    );
    final verifiedConfigs = await LocalReminderService.getConfigsForSubject(
      subjectKind,
      subjectId,
    );
    final verified = verifiedConfigs.any(
      (config) =>
          config.id == created.id &&
          config.category == plan.category &&
          config.timezoneMode == plan.timezoneMode &&
          config.timezoneId == timezoneId &&
          config.config['mode'] == plan.config['mode'],
    );
    if (!verified) {
      var rolledBack = false;
      try {
        await LocalReminderService.deleteConfig(created.id);
        rolledBack = true;
      } catch (_) {}
      return ToolExecutionResult.failure(
        toolName: 'create_reminder',
        modelMessage: rolledBack
            ? '提醒写入后校验失败，已回滚本次创建，请重试'
            : '提醒写入后校验失败且自动回滚未完成，请到提醒管理中检查',
        title: '提醒未创建',
        detail: rolledBack ? '数据库校验失败，本次更改已撤销' : '需要检查是否留下未完整配置',
        entityId: created.id,
      );
    }

    final reminderLabel = _reminderPlanLabel(plan);
    final timeDetail = plan.monitorsWeatherChanges
        ? '${plan.config['monitor_start']}–${plan.config['monitor_end']}'
        : plan.config['scheduled_at'] != null
        ? '单次 ${plan.displayTime}'
        : plan.config['weekdays'] != null
        ? '每周 ${plan.config['weekdays']} · ${plan.displayTime}'
        : '每天 ${plan.displayTime}';
    final zoneDetail = plan.timezoneMode == 'partner'
        ? '${plan.partnerName}当地时间 · $timezoneId'
        : '你的当地时间';

    if (plan.monitorsWeatherChanges) {
      final readiness = await BackgroundExecutionService.getReadiness();
      if (!readiness.notificationGranted ||
          !readiness.batteryOptimizationIgnored) {
        return ToolExecutionResult.partialSuccess(
          toolName: 'create_reminder',
          modelMessage:
              '天气突变监测已保存并验证，但系统通知或后台运行条件尚未完全就绪。它是设备端尽力监测，可能受省电和网络限制而延迟',
          title: '天气监测已保存',
          detail: '${plan.partnerName} · $timeDetail · $zoneDetail；请完善后台权限',
          entityId: created.id,
          verified: true,
        );
      }
      return ToolExecutionResult.success(
        toolName: 'create_reminder',
        modelMessage:
            '已为${plan.partnerName}开启并验证天气突变尽力监测，监测时段 $timeDetail（$zoneDetail）。后台省电或网络限制仍可能造成延迟',
        title: '$reminderLabel已开启',
        detail: '${plan.partnerName} · $timeDetail · $zoneDetail',
        entityId: created.id,
        verified: true,
      );
    }

    final schedulingReady =
        TimezoneService.isInitialized && NotificationService.isInitialized;
    final occurrences = schedulingReady
        ? plan.isSelfReminder
              ? ReminderScheduler.calculateSelfOccurrences(
                  config: created,
                  now: tz.TZDateTime.now(tz.local),
                )
              : ReminderScheduler.calculateOccurrences(
                  config: created,
                  partner: partner!,
                  now: tz.TZDateTime.now(tz.local),
                )
        : const [];
    try {
      await ReminderScheduler.scheduleAll();
    } catch (_) {
      return ToolExecutionResult.partialSuccess(
        toolName: 'create_reminder',
        modelMessage: '提醒已保存并验证，但系统通知调度失败',
        title: '提醒已保存',
        detail: '${plan.partnerName} · $reminderLabel · $timeDetail；通知尚未调度',
        entityId: created.id,
        verified: true,
      );
    }

    if (!schedulingReady || occurrences.isEmpty) {
      return ToolExecutionResult.partialSuccess(
        toolName: 'create_reminder',
        modelMessage: '提醒已保存并验证，但通知服务或时区调度尚未就绪',
        title: '提醒已保存',
        detail: '${plan.partnerName} · $reminderLabel · $timeDetail；稍后将重试调度',
        entityId: created.id,
        verified: true,
      );
    }

    final readiness = await BackgroundExecutionService.getReadiness();
    if (!readiness.notificationGranted || !readiness.exactAlarmAllowed) {
      return ToolExecutionResult.partialSuccess(
        toolName: 'create_reminder',
        modelMessage: '提醒已保存、验证并提交调度，但通知权限或精确定时权限尚未完全就绪，系统可能改用非精确定时',
        title: '提醒已保存',
        detail: '${plan.partnerName} · $timeDetail · $zoneDetail；请完善系统权限',
        entityId: created.id,
        verified: true,
      );
    }

    return ToolExecutionResult.success(
      toolName: 'create_reminder',
      modelMessage:
          '已为${plan.partnerName}创建、回读验证并调度$reminderLabel，$timeDetail（$zoneDetail）',
      title: '$reminderLabel已设置',
      detail: '${plan.partnerName} · $timeDetail · $zoneDetail',
      entityId: created.id,
      verified: true,
    );
  }

  String _reminderPlanLabel(ReminderToolPlan plan) {
    if (plan.monitorsWeatherChanges) return '天气突变监测';
    if (plan.category == 'weather') return '每日天气简报';
    return _categoryLabel(plan.category);
  }

  // ---- 工具: 删除提醒 ----
  Future<ToolExecutionResult> _toolDeleteReminder(
    Map<String, dynamic> args,
  ) async {
    final partnerName = args['partner_name'] as String? ?? '';
    final category = args['category'] as String? ?? '';
    final weatherMode = args['weather_mode'] as String?;
    final isSelf =
        args['subject'] == 'self' ||
        const {'我', '自己', '本人', '用户'}.contains(partnerName.trim());

    Partner? partner;
    if (!isSelf) {
      final partners = await PartnerService.getAll();
      final matches = partners
          .where(
            (p) => args['partner_id'] != null
                ? p.id == args['partner_id']
                : p.nickname == partnerName,
          )
          .toList();
      if (matches.isEmpty) {
        final message = '未找到名为"$partnerName"的关心的人';
        return ToolExecutionResult.failure(
          toolName: 'delete_reminder',
          modelMessage: message,
          title: '提醒未删除',
          detail: message,
        );
      }
      partner = matches.first;
    }

    final displayName = isSelf ? '你自己' : partnerName;
    final configs = await LocalReminderService.getConfigsForSubject(
      isSelf ? 'user' : 'partner',
      isSelf ? 'self' : partner!.id,
    );
    final selection = ReminderToolPlanner.selectDeletionTargets(
      configs,
      category: category,
      weatherMode: weatherMode,
    );
    if (selection.error != null) {
      return ToolExecutionResult.failure(
        toolName: 'delete_reminder',
        modelMessage: selection.error!,
        title: '提醒未删除',
        detail: selection.error!,
        verified: true,
      );
    }
    final matching = selection.targets;
    if (matching.isEmpty) {
      final requestedLabel = category == 'weather'
          ? weatherMode == 'weather_change'
                ? '天气突变监测'
                : weatherMode == 'daily_digest'
                ? '每日天气简报'
                : '天气提醒'
          : '${_categoryLabel(category)}提醒';
      final message = '$displayName没有$requestedLabel';
      return ToolExecutionResult.failure(
        toolName: 'delete_reminder',
        modelMessage: message,
        title: '提醒未删除',
        detail: message,
        verified: true,
      );
    }

    for (final config in matching) {
      await LocalReminderService.deleteConfig(config.id);
    }
    final remaining = await LocalReminderService.getConfigsForSubject(
      isSelf ? 'user' : 'partner',
      isSelf ? 'self' : partner!.id,
    );
    final verified = matching.every(
      (deleted) => remaining.every((config) => config.id != deleted.id),
    );
    if (!verified) {
      return ToolExecutionResult.failure(
        toolName: 'delete_reminder',
        modelMessage: '提醒删除后校验失败，请重试',
        title: '提醒未删除',
        detail: '数据库校验失败，请重试',
      );
    }

    final schedulingReady =
        TimezoneService.isInitialized && NotificationService.isInitialized;
    try {
      await ReminderScheduler.scheduleAll();
    } catch (_) {
      return ToolExecutionResult.partialSuccess(
        toolName: 'delete_reminder',
        modelMessage: '提醒配置已删除，但系统通知同步失败',
        title: '提醒已删除',
        detail: '$displayName · ${_categoryLabel(category)}；通知将在下次启动时同步',
        verified: true,
      );
    }
    if (!schedulingReady) {
      return ToolExecutionResult.partialSuccess(
        toolName: 'delete_reminder',
        modelMessage: '提醒配置已删除，但通知服务尚未就绪',
        title: '提醒已删除',
        detail: '$displayName · ${_categoryLabel(category)}；重启后将同步通知',
        verified: true,
      );
    }

    return ToolExecutionResult.success(
      toolName: 'delete_reminder',
      modelMessage: '已删除并验证$displayName的${_categoryLabel(category)}提醒',
      title: '${_categoryLabel(category)}提醒已删除',
      detail: displayName,
      verified: true,
    );
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
      return partners.isEmpty ? '还没有添加关心的人' : lines.join('; ');
    }

    final partners = await PartnerService.getAll();
    final partner = partners
        .where(
          (p) => args['partner_id'] != null
              ? p.id == args['partner_id']
              : p.nickname == partnerName,
        )
        .toList();
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
          partner.longitude!,
          partner.latitude!,
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
      final cityInfo = p.city != null && p.city!.isNotEmpty
          ? '，城市: ${p.city}'
          : '，城市: 未设置';
      lines.add(
        'ID=${p.id} ${p.nickname}（${p.typeLabel}，添加于 $days 天前$cityInfo）',
      );
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
    parts.add('总共确认过 $total 次关心');
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
  Future<ToolExecutionResult> _toolCreatePartner(
    Map<String, dynamic> args,
  ) async {
    final nickname = args['nickname'] as String? ?? '';
    final type = args['relationship'] as String? ?? 'other';
    final rawCity = args['city'] as String?;
    // 城市名清理：去空格、去掉"市"后缀
    final city = rawCity?.trim().replaceAll(RegExp(r'[市]$'), '');
    final timezoneId = (args['timezone_id'] as String?)?.trim();
    final note = args['note'] as String?;

    if (nickname.isEmpty) {
      return ToolExecutionResult.failure(
        toolName: 'create_partner',
        modelMessage: '创建失败：需要提供名字',
        title: '未添加关心的人',
        detail: '需要先提供名字',
      );
    }
    if (timezoneId != null &&
        timezoneId.isNotEmpty &&
        !_isValidTimezoneId(timezoneId)) {
      return ToolExecutionResult.failure(
        toolName: 'create_partner',
        modelMessage: '时区 $timezoneId 无效，请先向用户确认正确的 IANA 时区',
        title: '未添加关心的人',
        detail: '时区格式无效，例如应为 Asia/Singapore',
      );
    }

    // 检查是否已存在同名
    final existing = await PartnerService.getAll();
    if (existing.any((p) => p.nickname == nickname)) {
      return ToolExecutionResult.failure(
        toolName: 'create_partner',
        modelMessage: '$nickname 已经在你的关心列表里了，不需要重复添加',
        title: '没有重复添加',
        detail: '$nickname 已经在关心列表中',
        verified: true,
      );
    }

    final provisional = await PartnerService.add(
      nickname: nickname,
      type: type,
      city: city,
      note: note,
      timezoneId: timezoneId?.isEmpty == true ? null : timezoneId,
      timezoneSource: timezoneId?.isNotEmpty == true ? 'user_confirmed' : null,
      timezoneConfirmed: timezoneId?.isNotEmpty == true,
    );
    // 验证创建结果
    final verify = await PartnerService.getAll();
    final created = verify.where((p) => p.id == provisional.id).toList();
    if (created.isEmpty) {
      final rolledBack = await _rollbackCreatedPartner(provisional.id);
      return ToolExecutionResult.failure(
        toolName: 'create_partner',
        modelMessage: rolledBack
            ? '人物写入后校验失败，已回滚本次创建，请重试'
            : '人物写入后校验失败且自动回滚未完成，请检查关心列表',
        title: '未添加关心的人',
        detail: rolledBack ? '数据库校验失败，本次更改已撤销' : '需要检查是否留下未完整人物',
        entityId: provisional.id,
      );
    }
    final p = created.first;
    final createVerified =
        p.type == type &&
        (city == null || p.city == city) &&
        (timezoneId == null ||
            timezoneId.isEmpty ||
            (p.timezoneId == timezoneId && p.timezoneConfirmed)) &&
        (note == null || p.note == note);
    if (!createVerified) {
      final rolledBack = await _rollbackCreatedPartner(p.id);
      return ToolExecutionResult.failure(
        toolName: 'create_partner',
        modelMessage: rolledBack
            ? '人物写入后数据校验不一致，已回滚本次创建，请重试'
            : '人物写入后数据校验不一致且自动回滚未完成，请检查关心列表',
        title: '未完整添加关心的人',
        detail: rolledBack ? '数据库校验失败，本次更改已撤销' : '需要检查是否留下未完整人物',
        entityId: p.id,
      );
    }

    final typeLabel = _relationshipLabel(type);
    final locationInfo = <String>[
      if (p.city?.isNotEmpty == true) '城市已设为${p.city}',
      if (p.timezoneId?.isNotEmpty == true) '当地时区已确认 ${p.timezoneId}',
    ];

    final modelMessage =
        '已添加并回读验证 $nickname（$typeLabel），partner_id=${p.id}。${locationInfo.join('，')}。继续完成用户本轮已要求的其他操作，缺少非必要资料无需追问。';
    return ToolExecutionResult.success(
      toolName: 'create_partner',
      modelMessage: modelMessage,
      title: '已添加关心的人',
      detail:
          '$nickname · $typeLabel${p.city == null ? '' : ' · ${p.city}'}${p.timezoneId == null ? '' : ' · ${p.timezoneId}'}',
      entityId: p.id,
      verified: true,
    );
  }

  Future<bool> _rollbackCreatedPartner(String id) async {
    try {
      await PartnerService.deleteCreated(id);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---- 工具: 查看某人详情 ----
  Future<String> _toolGetPartnerDetail(Map<String, dynamic> args) async {
    final partnerName = args['partner_name'] as String? ?? '';

    final partners = await PartnerService.getAll();
    final partner = partners
        .where(
          (p) => args['partner_id'] != null
              ? p.id == args['partner_id']
              : p.nickname == partnerName,
        )
        .toList();
    if (partner.isEmpty) {
      return '未找到名为"$partnerName"的关心的人';
    }

    final p = partner.first;
    final days = DateTime.now().difference(p.createdAt).inDays;
    final parts = <String>[
      'ID=${p.id} $partnerName（${p.typeLabel}，添加于 $days 天前）',
    ];
    if (p.city != null && p.city!.isNotEmpty) {
      parts.add('城市: ${p.city}');
    } else {
      parts.add('城市: 未设置');
    }
    if (p.timezoneId?.isNotEmpty == true) {
      parts.add(
        '时区: ${p.timezoneId}${p.timezoneConfirmed ? '（已确认）' : '（待确认）'}',
      );
    } else {
      parts.add('时区: 未确认');
    }
    if (p.note != null && p.note!.isNotEmpty) {
      parts.add('描述: ${p.note}');
    }

    // 查询提醒配置
    final configs = await LocalReminderService.getConfigs(p.id);
    final enabled = configs.where((c) => c.enabled).toList();
    if (enabled.isNotEmpty) {
      final categories = enabled
          .map((c) {
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
                final mode = c.config['mode'] ?? 'daily_digest';
                final label = mode == 'weather_change' ? '天气突变监测' : '每日天气简报';
                return '$label（${c.timezoneMode == 'partner' ? 'Ta当地时间' : '你的当地时间'}）';
              default:
                return c.category;
            }
          })
          .join('、');
      parts.add('提醒: $categories');
    } else {
      parts.add('提醒: 暂无');
    }

    return parts.join('；');
  }

  // ---- 工具: 更新关心的人 ----
  Future<ToolExecutionResult> _toolUpdatePartner(
    Map<String, dynamic> args,
  ) async {
    final partnerName = args['partner_name'] as String? ?? '';
    final newNickname = args['new_nickname'] as String?;
    final newType = args['relationship'] as String?;
    final rawCity = args['city'] as String?;
    final city = rawCity?.trim().replaceAll(RegExp(r'[市县区]$'), '');
    final timezoneId = (args['timezone_id'] as String?)?.trim();
    final note = args['note'] as String?;

    if (timezoneId != null &&
        timezoneId.isNotEmpty &&
        !_isValidTimezoneId(timezoneId)) {
      return ToolExecutionResult.failure(
        toolName: 'update_partner',
        modelMessage: '时区 $timezoneId 无效，请先向用户确认正确的 IANA 时区',
        title: '信息未更新',
        detail: '时区格式无效，例如应为 Asia/Singapore',
      );
    }

    final partners = await PartnerService.getAll();
    final partner = partners
        .where(
          (p) => args['partner_id'] != null
              ? p.id == args['partner_id']
              : p.nickname == partnerName,
        )
        .toList();
    if (partner.isEmpty) {
      final message = '未找到名为"$partnerName"的关心的人';
      return ToolExecutionResult.failure(
        toolName: 'update_partner',
        modelMessage: message,
        title: '信息未更新',
        detail: message,
      );
    }

    final p = partner.first;
    final cityChanged =
        city != null &&
        city.trim().toLowerCase() != (p.city ?? '').trim().toLowerCase();
    final changes = <String>[];

    await PartnerService.update(
      p.id,
      nickname: newNickname,
      type: newType,
      city: city,
      note: note,
      timezoneId: timezoneId?.isEmpty == true ? null : timezoneId,
      timezoneSource: timezoneId?.isNotEmpty == true ? 'user_confirmed' : null,
      timezoneConfirmed: timezoneId?.isNotEmpty == true ? true : null,
      expectedUpdatedAt: p.updatedAt,
      clearLocation: city != null && city.isEmpty,
    );
    if (newNickname != null && newNickname != partnerName) {
      changes.add('名字改为$newNickname');
    }
    if (newType != null) {
      changes.add('关系改为${_relationshipLabel(newType)}');
    }
    if (cityChanged) {
      changes.add('城市改为$city');
      if (timezoneId == null || timezoneId.isEmpty) {
        changes.add('已按新城市重新解析时区');
      }
    }
    if (timezoneId?.isNotEmpty == true) {
      changes.add('当地时区确认为$timezoneId');
    }
    if (note != null) {
      changes.add('描述改为$note');
    }

    if (changes.isEmpty) {
      return ToolExecutionResult.failure(
        toolName: 'update_partner',
        modelMessage: '${p.nickname}的信息没有变化',
        title: '信息没有变化',
        detail: '没有收到需要修改的内容',
        entityId: p.id,
        verified: true,
      );
    }

    // 验证更新结果
    final verifyName = newNickname ?? partnerName;
    final verify = await PartnerService.getAll();
    final updated = verify.where((row) => row.id == p.id).toList();
    if (updated.isEmpty) {
      final rolledBack = await _rollbackUpdatedPartner(p);
      return ToolExecutionResult.failure(
        toolName: 'update_partner',
        modelMessage: rolledBack
            ? '更新后校验失败，已恢复修改前的信息，请重试'
            : '更新后校验失败且自动恢复未完成，请检查人物信息',
        title: '信息未更新',
        detail: rolledBack ? '数据库校验失败，本次更改已撤销' : '需要检查人物信息是否完整',
        entityId: p.id,
      );
    }

    final saved = updated.first;
    final verified =
        (newNickname == null || saved.nickname == newNickname) &&
        (newType == null || saved.type == newType) &&
        (city == null || saved.city == city) &&
        (timezoneId == null ||
            timezoneId.isEmpty ||
            (saved.timezoneId == timezoneId && saved.timezoneConfirmed)) &&
        (!cityChanged ||
            timezoneId?.isNotEmpty == true ||
            ((saved.timezoneId == null && !saved.timezoneConfirmed) ||
                saved.timezoneSource == 'city_selection')) &&
        (note == null || saved.note == (note.trim().isEmpty ? null : note));
    if (!verified) {
      final rolledBack = await _rollbackUpdatedPartner(p);
      return ToolExecutionResult.failure(
        toolName: 'update_partner',
        modelMessage: rolledBack
            ? '更新后数据校验不一致，已恢复修改前的信息，请重试'
            : '更新后数据校验不一致且自动恢复未完成，请检查人物信息',
        title: '信息未完全更新',
        detail: rolledBack ? '数据库校验失败，本次更改已撤销' : '需要检查人物信息是否完整',
        entityId: p.id,
      );
    }

    var reminderSyncFailed = false;
    var reminderSyncDeferred = false;
    if (cityChanged || timezoneId?.isNotEmpty == true) {
      if (!TimezoneService.isInitialized ||
          !NotificationService.isInitialized) {
        reminderSyncDeferred = true;
      } else {
        try {
          // Rebuild the full schedule so a city change cannot leave stale
          // notifications running in the previous timezone.
          await ReminderScheduler.scheduleAll();
        } catch (_) {
          reminderSyncFailed = true;
        }
      }
    }

    if (cityChanged && !saved.timezoneConfirmed) {
      final configs = await LocalReminderService.getConfigs(p.id);
      final affectedCount = configs
          .where((config) => config.enabled && config.timezoneMode == 'partner')
          .length;
      if (affectedCount > 0) {
        return ToolExecutionResult.partialSuccess(
          toolName: 'update_partner',
          modelMessage: reminderSyncFailed
              ? '已更新并验证$verifyName：${changes.join('、')}。有 $affectedCount 个当地时间提醒待确认，且旧通知同步失败；请检查提醒管理并确认新时区'
              : reminderSyncDeferred
              ? '已更新并验证$verifyName：${changes.join('、')}。有 $affectedCount 个当地时间提醒待确认；通知服务就绪后会同步暂停旧时区调度'
              : '已更新并验证$verifyName：${changes.join('、')}。有 $affectedCount 个按Ta当地时间执行的提醒会暂停调度，确认新时区后才能恢复',
          title: '人物信息已更新',
          detail: reminderSyncFailed || reminderSyncDeferred
              ? '$verifyName · 新时区待确认 · 通知待同步'
              : '$verifyName · 新时区待确认 · $affectedCount 个提醒待恢复',
          entityId: p.id,
          verified: true,
        );
      }
    }

    if (reminderSyncFailed || reminderSyncDeferred) {
      return ToolExecutionResult.partialSuccess(
        toolName: 'update_partner',
        modelMessage: reminderSyncFailed
            ? '已更新并验证$verifyName：${changes.join('、')}。提醒通知同步失败，将在下次启动时重试'
            : '已更新并验证$verifyName：${changes.join('、')}。通知服务尚未就绪，提醒会在下次启动时同步',
        title: '人物信息已更新',
        detail: '$verifyName · 提醒通知待同步',
        entityId: p.id,
        verified: true,
      );
    }

    return ToolExecutionResult.success(
      toolName: 'update_partner',
      modelMessage: '已更新并验证$verifyName：${changes.join('、')}',
      title: '人物信息已更新',
      detail: '$verifyName · ${changes.join(' · ')}',
      entityId: p.id,
      verified: true,
    );
  }

  Future<bool> _rollbackUpdatedPartner(Partner snapshot) async {
    try {
      await PartnerService.restoreSnapshot(snapshot);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _isValidTimezoneId(String timezoneId) {
    try {
      tz.getLocation(timezoneId);
      return true;
    } catch (_) {
      return false;
    }
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
      'update_reminder' => '修改提醒',
      'get_reminders' => '读取提醒',
      'get_capabilities' => '检查可用能力',
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
  Future<void> _sendChoiceMessage(String choice) => _sendText(choice);

  /// 处理 AI 回复（从 _sendMessage 中提取的公共逻辑）
  Future<void> _processAiResponse(
    String text, {
    required String requestId,
    bool isRetry = false,
    bool hideUserMessage = false,
    String hiddenMessageType = 'launch_prompt',
    bool recordConversationMemory = true,
    String? fallbackAssistantText,
  }) async {
    try {
      await AiService.chatWithTools(
        text,
        onToolCall: (name, args) async {
          if (!mounted) return '操作已取消';
          setState(() {
            _executingTool = name;
            _activityPhase = AiActivityPhase.executingTool;
          });
          _scrollToBottom();
          final result = await _executeTool(name, args);
          if (!mounted) return result.toModelContent();
          ChatHistoryWriteResult? milestoneRecord;
          if (result.milestone != null) {
            milestoneRecord = await ChatHistoryService.append(
              role: 'system',
              content: result.modelMessage,
              messageType: 'milestone',
              metadata: {
                'tool': result.toolName,
                'entity_id': result.entityId,
                'verified': result.verified,
                'milestone': result.milestone!.toMap(),
              },
            );
          }
          if (!mounted) return result.toModelContent();
          setState(() {
            if (result.milestone != null) {
              _messages.add(
                _ChatMessage(
                  id: milestoneRecord?.id,
                  role: 'system',
                  content: result.modelMessage,
                  milestone: result.milestone,
                ),
              );
            }
            _executingTool = null;
            _activityPhase = AiActivityPhase.waitingForReply;
          });
          _scrollToBottom();
          return result.toModelContent();
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
            } else {
              _messages.add(
                _ChatMessage(
                  role: 'assistant',
                  content: accumulated,
                  streaming: true,
                ),
              );
            }
            _activityPhase = AiActivityPhase.receivingReply;
          });
          _scrollToBottom();
        },
        requestId: requestId,
        hideUserMessage: hideUserMessage,
        userMessageType: hideUserMessage ? hiddenMessageType : 'message',
      );

      if (!mounted) return;

      final idx = _messages.lastIndexWhere((m) => m.streaming);
      if (idx >= 0) {
        final fullContent = _messages[idx].content;
        setState(() {
          _messages.removeAt(idx);
          _activityPhase = AiActivityPhase.revealingSegments;
        });

        if (fullContent.trim().isNotEmpty && recordConversationMemory) {
          _postConversationMemory(text, fullContent);
        }

        final parts = splitAssistantPresentationSegments(fullContent);

        if (parts.isEmpty) {
          if (fullContent.trim().isNotEmpty) {
            setState(() {
              _messages.add(
                _ChatMessage(role: 'assistant', content: fullContent.trim()),
              );
            });
          }
        } else {
          for (int i = 0; i < parts.length; i++) {
            if (i > 0) {
              await Future.delayed(segmentRevealDelay(parts[i]));
            }
            if (!mounted) break;
            setState(() {
              _messages.add(_ChatMessage(role: 'assistant', content: parts[i]));
            });
            _scrollToBottom();
          }
        }
      } else {
        setState(() => _activityPhase = AiActivityPhase.revealingSegments);
      }
      if (isRetry) await _appendRetrySuccessMilestone();
    } on AiChatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      final idx = _messages.lastIndexWhere((m) => m.streaming);
      if (idx >= 0) _messages.removeAt(idx);
      if (fallbackAssistantText != null) {
        await _appendAssistantFallback(
          requestId: requestId,
          content: fallbackAssistantText,
        );
      } else {
        setState(() {
          _messages.add(
            _ChatMessage(
              role: 'system',
              content: '',
              retryText: text,
              requestId: requestId,
            ),
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _executingTool = null;
          _activityPhase = AiActivityPhase.idle;
        });
      }
      _scrollToBottom();
    }
  }

  Future<void> _retryFailedMessage(_ChatMessage message) async {
    final text = message.retryText;
    final requestId = message.requestId;
    if (_sending || text == null || requestId == null) return;
    setState(() {
      _messages.remove(message);
      _sending = true;
      _activityPhase = AiActivityPhase.waitingForReply;
    });
    _scrollToBottom();
    await _processAiResponse(text, requestId: requestId, isRetry: true);
  }

  Future<void> _appendRetrySuccessMilestone() async {
    const milestone = ToolMilestone(
      status: ToolExecutionStatus.success,
      title: '已重新连接',
      detail: '刚才的请求已经继续完成',
    );
    final record = await ChatHistoryService.append(
      role: 'system',
      content: '网络重试成功，刚才的请求已经继续完成',
      messageType: 'milestone',
      metadata: const {
        'source': 'network_retry',
        'milestone': {
          'status': 'success',
          'title': '已重新连接',
          'detail': '刚才的请求已经继续完成',
        },
      },
    );
    if (!mounted) return;
    setState(() {
      _messages.add(
        _ChatMessage(
          id: record.id,
          role: 'system',
          content: '网络重试成功，刚才的请求已经继续完成',
          milestone: milestone,
        ),
      );
    });
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
                    onChanged: (v) =>
                        setDialogState(() => dontAskAgain = v ?? false),
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
    final conversationMessages = _messages
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .toList();

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('对话已总结并存入长期记忆')));
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

  void _focusComposer() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future<void>.delayed(TaAnimation.fast, () {
        if (mounted && _inputFocusNode.canRequestFocus) {
          _inputFocusNode.requestFocus();
        }
      });
    });
  }

  @override
  void dispose() {
    widget.draftNotifier?.removeListener(_consumeExternalDraft);
    _speech.cancel();
    _controller.dispose();
    AiService.cancelCurrentChat();
    _inputFocusNode.dispose();
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
          const ReminderHealthCard(),

          // ---- 消息列表 ----
          Expanded(child: _buildMessageList(theme)),

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
        TaSpacing.pagePadding,
        TaSpacing.sm,
        TaSpacing.pagePadding,
        TaSpacing.xs,
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
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerLow),
      child: Row(
        children: [
          Icon(
            Icons.psychology_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: TaSpacing.xs),
          Expanded(
            child: Text(
              '连接模型，和小念聊聊',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
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
              minimumSize: const Size(0, 44),
              tapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('连接', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ---- 消息列表 ----
  Widget _buildMessageList(ThemeData theme) {
    final activity = conversationActivityPresentation(
      _activityPhase,
      toolLabel: _executingTool == null
          ? null
          : _toolNameLabel(_executingTool!),
    );
    if (_historyError != null) {
      return Center(
        child: TextButton(onPressed: _init, child: Text(_historyError!)),
      );
    }
    if (_messages.isEmpty && !activity.showLeftBubble) {
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

    final snapshots = _messages
        .map(
          (message) => ConversationMessageSnapshot(
            role: message.role,
            content: message.content,
          ),
        )
        .toList(growable: false);
    final activeChoiceIndex = findLatestUnansweredChoiceIndex(snapshots);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: TaSpacing.pagePadding,
        vertical: TaSpacing.xs,
      ),
      itemCount:
          _messages.length +
          (activity.showLeftBubble ? 1 : 0) +
          (_hasOlder ? 1 : 0),
      itemBuilder: (context, itemIndex) {
        if (_hasOlder && itemIndex == 0) {
          return TextButton(
            onPressed: _loadingOlder ? null : _loadOlder,
            child: Text(_loadingOlder ? '正在读取…' : '查看更早的对话'),
          );
        }
        final index = itemIndex - (_hasOlder ? 1 : 0);
        if (index == _messages.length) {
          return _buildLeftActivityBubble(theme, label: activity.label);
        }
        final msg = _messages[index];
        if (msg.reminderOccurrence != null) {
          return ReminderFollowUpCard(
            occurrence: msg.reminderOccurrence!,
            onResponse: (response) => _respondToReminder(msg, response),
          );
        }
        if (msg.retryText != null) {
          return RetryMessageCard(onRetry: () => _retryFailedMessage(msg));
        }
        if (msg.milestone != null) {
          return MilestoneMessageCard(
            milestone: msg.milestone!,
            onDismiss: () => _dismissMessage(msg),
          );
        }
        if (msg.proactiveType != ProactiveType.none) {
          return _buildProactiveCard(
            msg,
            theme,
          ).animate().fadeIn(duration: TaAnimation.normal);
        }
        return _ChatBubble(
          message: msg,
          showChoices: index == activeChoiceIndex,
          choiceEnabled: !_sending,
          onChoiceSelected: (choice) => _sendChoiceMessage(choice),
        );
      },
    );
  }

  Future<void> _respondToReminder(
    _ChatMessage message,
    ReminderUserResponse response,
  ) async {
    final occurrence = message.reminderOccurrence;
    if (occurrence == null) return;
    final action = switch (response) {
      ReminderUserResponse.done => ReminderNotificationAction.done,
      ReminderUserResponse.snooze => ReminderNotificationAction.snooze,
      ReminderUserResponse.outdated => ReminderNotificationAction.outdated,
    };
    try {
      await NotificationService.respondToOccurrence(occurrence.id, action);
      final (title, detail) = switch (response) {
        ReminderUserResponse.done => ('已经记下', '这条提醒已处理'),
        ReminderUserResponse.snooze => ('稍后再提醒', '5 分钟后轻轻提醒你'),
        ReminderUserResponse.outdated => ('已收起提醒', '这条内容已过时'),
      };
      final milestone = ToolMilestone(
        status: ToolExecutionStatus.success,
        title: title,
        detail: detail,
      );
      final record = await ChatHistoryService.append(
        role: 'system',
        content: '$title：$detail',
        messageType: 'milestone',
        metadata: {
          'source': 'reminder_response',
          'occurrence_id': occurrence.id,
          'milestone': milestone.toMap(),
        },
      );
      if (!mounted) return;
      setState(() {
        _messages.remove(message);
        _messages.add(
          _ChatMessage(
            id: record.id,
            role: 'system',
            content: '$title：$detail',
            milestone: milestone,
          ),
        );
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂时没处理成功，请再试一次')));
    }
  }

  Future<void> _dismissMessage(_ChatMessage message) async {
    setState(() => _messages.remove(message));
    final id = message.id;
    if (id != null) await ChatHistoryService.hide(id);
  }

  Widget _buildLeftActivityBubble(ThemeData theme, {String? label}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: TaSpacing.xxs),
        padding: const EdgeInsets.symmetric(
          horizontal: TaSpacing.md,
          vertical: TaSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(TaRadius.md),
            topRight: Radius.circular(TaRadius.md),
            bottomLeft: Radius.circular(TaRadius.xs),
            bottomRight: Radius.circular(TaRadius.md),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TaThinkingDots(),
            if (label != null) ...[
              const SizedBox(width: TaSpacing.xs),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    ).animate().fadeIn(duration: TaAnimation.fast, curve: TaAnimation.curve);
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
              Icon(
                Icons.auto_awesome_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: TaSpacing.xs),
              Expanded(
                child: Text(msg.content, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
        ).animate().fadeIn(duration: TaAnimation.normal);
    }
  }

  // ---- 输入栏 ----
  Widget _buildInputBar(ThemeData theme) {
    final chips = _buildChips(theme);

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
        TaSpacing.xxs,
        TaSpacing.pagePadding,
        TaSpacing.xxs,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 快捷芯片
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: chips.length,
              separatorBuilder: (_, _) => const SizedBox(width: TaSpacing.xs),
              itemBuilder: (_, i) {
                final chip = chips[i];
                return AiQuickActionChip(
                  label: chip.$3,
                  icon: chip.$1,
                  iconColor: chip.$2,
                  onPressed: () => _handleChip(chip.$4),
                );
              },
            ),
          ),
          const SizedBox(height: TaSpacing.xxs),
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
                    focusNode: _inputFocusNode,
                    decoration: InputDecoration(
                      hintText: '问我任何关于关怀的问题...',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: TaSpacing.md,
                        vertical: TaSpacing.sm,
                      ),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 84,
                        maxWidth: 84,
                        minHeight: 40,
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AiImageInputButton(
                            onPressed: _sending ? null : _chooseImageSource,
                          ),
                          AiVoiceInputButton(
                            isListening: _isListening,
                            onPressed: _sending ? null : _toggleVoiceInput,
                          ),
                        ],
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
                  tooltip: _sending ? '停止本轮回复' : '发送',
                  onPressed: _sending
                      ? AiService.cancelCurrentChat
                      : _sendMessage,
                  icon: Icon(
                    _sending ? Icons.stop_rounded : Icons.send_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<(IconData, Color, String, String)> _buildChips(ThemeData theme) {
    final colors = theme.colorScheme;
    final chips = <(IconData, Color, String, String)>[
      (Icons.wb_sunny_rounded, colors.secondary, '今日天气', 'weather'),
    ];
    if (_isEvening) {
      chips.add((Icons.bedtime_rounded, colors.tertiary, '写句晚安语', 'goodnight'));
    } else {
      chips.add((
        Icons.wb_twilight_rounded,
        colors.secondary,
        '写句早安语',
        'goodmorning',
      ));
    }
    chips
      ..add((Icons.favorite_rounded, colors.primary, '关心建议', 'care'))
      ..add((
        Icons.restaurant_rounded,
        colors.secondary,
        '提醒吃饭',
        'remind_meal',
      ));
    return chips;
  }
}

// ============================================================
// 聊天气泡
// ============================================================

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.showChoices,
    required this.choiceEnabled,
    this.onChoiceSelected,
  });
  final _ChatMessage message;
  final bool showChoices;
  final bool choiceEnabled;
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

    if (message.localImagePath != null) {
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: TaSpacing.xxs),
          child: ChatImageBubble(
            localPath: message.localImagePath!,
            summary: message.content,
          ),
        ),
      ).animate().fadeIn(duration: TaAnimation.fast, curve: TaAnimation.curve);
    }

    // 流式消息：隐藏 ||| 分隔符和选择题标记，空内容时显示输入光标
    String displayContent = message.content;
    if (message.streaming) {
      displayContent = displayContent.replaceAll('|||', '');
    }
    // 移除选择题标记
    displayContent = displayContent
        .replaceAll(RegExp(r'\[选项:[^\]]+\]'), '')
        .trim();

    final choices = showChoices ? _parseChoices(message.content) : <String>[];

    if (displayContent.isEmpty && choices.isEmpty && !message.streaming) {
      return const SizedBox.shrink();
    }

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
                            color:
                                (isUser
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

  List<Widget> _buildChoiceButtons(
    ThemeData theme,
    bool isUser,
    List<String> choices,
  ) {
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
              onTap: choiceEnabled
                  ? () => onChoiceSelected?.call(choice)
                  : null,
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
    if (content.contains('酷热') || content.contains('高温')) {
      return 'assets/images/weather_heat.png';
    }
    if (content.contains('极寒') || content.contains('低温')) {
      return 'assets/images/weather_cold.png';
    }
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
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
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
                    Icon(
                      Icons.wb_sunny_rounded,
                      size: 24,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: TaSpacing.xs),
                    Text(
                      '天气关注',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: TaSpacing.xs),
                Text(
                  message.content,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (message.actionLabel != null) ...[
                  const SizedBox(height: TaSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: TaSpacing.sm,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: TaRadius.borderFull,
                      ),
                      child: Text(
                        message.actionLabel!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface,
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
              Image.asset(
                'assets/images/ai_empty_chat.png',
                width: 20,
                height: 20,
              ),
              const SizedBox(width: TaSpacing.xs),
              Text(
                '小念',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: TaSpacing.sm),
          Text(
            message.content,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
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
        border: Border.all(color: theme.colorScheme.secondaryContainer),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.favorite_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
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
