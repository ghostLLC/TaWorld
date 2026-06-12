/// TaWorld AI 关怀助手对话页面
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../services/ai_service.dart';


/// AI 对话页面
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _sending = false;
  bool _hasApiKey = true;

  @override
  void initState() {
    super.initState();
    _checkApiKey();
    _loadHistory();
  }

  Future<void> _checkApiKey() async {
    final has = await AiService.hasApiKey();
    if (!mounted) return;
    setState(() => _hasApiKey = has);
  }

  Future<void> _loadHistory() async {
    try {
      final history = await AiService.getChatHistory();
      if (!mounted) return;
      setState(() {
        for (final row in history) {
          _messages.add(_ChatMessage(
            role: row['role'] as String,
            content: row['content'] as String,
          ));
        }
      });
      _scrollToBottom();
    } catch (_) {
      // Silently ignore history load failures; the user can still chat.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _messages.add(_ChatMessage(role: 'user', content: text));
      _controller.clear();
      _sending = true;
    });
    _scrollToBottom();

    try {
      final reply = await AiService.chat(text);
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(role: 'assistant', content: reply));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
          role: 'assistant',
          content: '抱歉，网络好像出了点问题：$e',
        ));
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
      _scrollToBottom();
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除对话记录'),
        content: const Text('确定清除所有对话记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await AiService.clearChatHistory();
      if (mounted) {
        setState(() => _messages.clear());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('对话记录已清除')),
        );
      }
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: TaSpacing.xs),
            const Text('AI 关怀助手'),
          ],
        ),
        centerTitle: true,
        actions: [
          if (_messages.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'clear') _clearHistory();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep_rounded, size: 20),
                      SizedBox(width: 8),
                      Text('清除对话记录'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // API Key 未配置提示
          if (!_hasApiKey)
            Container(
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
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: TaSpacing.xs),
                  Expanded(
                    child: Text(
                      'AI 服务未配置，请先设置 API Key',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await context.push(Routes.apiKeys);
                      _checkApiKey();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: TaSpacing.sm),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('去配置'),
                  ),
                ],
              ),
            ),

          // 消息列表
          Expanded(
            child: _messages.isEmpty
                ? _buildWelcome(theme)
                : ListView.builder(
                    controller: _scrollController,
                    padding: TaSpacing.page,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return _ChatBubble(
                        message: msg,
                        isLast: index == _messages.length - 1,
                      );
                    },
                  ),
          ),

          // 加载指示器
          if (_sending)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: TaSpacing.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: TaSpacing.xs),
                  Text(
                    'AI 正在思考...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

          // 输入框
          Container(
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
              TaSpacing.sm,
              TaSpacing.pagePadding,
              TaSpacing.sm + MediaQuery.of(context).padding.bottom,
            ),
            child: Row(
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
                    gradient: TaGradients.primary,
                    borderRadius: TaRadius.borderFull,
                  ),
                  child: IconButton(
                    onPressed: _sending ? null : _sendMessage,
                    icon: const Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcome(ThemeData theme) {
    return Center(
      child: Padding(
        padding: TaSpacing.page,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: TaGradients.primary,
                borderRadius: TaRadius.borderLg,
              ),
              child: const Icon(
                Icons.smart_toy_rounded,
                size: 40,
                color: Colors.white,
              ),
            ).animate().scale(duration: 500.ms, curve: TaAnimation.bounce),
            const SizedBox(height: TaSpacing.md),
            Text(
              'AI 关怀助手',
              style: theme.textTheme.headlineMedium,
            ).animate().fadeIn(delay: 300.ms),
            const SizedBox(height: TaSpacing.xs),
            Text(
              '我可以帮你生成温暖的关怀语，\n也可以回答关于 APP 使用的任何问题。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 500.ms),
            const SizedBox(height: TaSpacing.lg),
            // 快捷问题
            Wrap(
              spacing: TaSpacing.xs,
              runSpacing: TaSpacing.xs,
              alignment: WrapAlignment.center,
              children: [
                '怎么关心对方更好？',
                '帮我写一句晚安语',
                '天气不好怎么提醒？',
              ]
                  .map((q) => ActionChip(
                        label: Text(q),
                        onPressed: () {
                          _controller.text = q;
                          _sendMessage();
                        },
                      ))
                  .toList(),
            ).animate().fadeIn(delay: 700.ms),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({required this.role, required this.content});
  final String role;
  final String content;
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, this.isLast = false});

  final _ChatMessage message;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == 'user';

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
        child: Text(
          message.content,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isUser
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    ).animate().fadeIn(
          duration: TaAnimation.fast,
          curve: TaAnimation.curve,
        );
  }
}
