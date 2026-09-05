/// TaWorld API Key 管理页面
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import '../../../app/design_tokens.dart';
import '../../widgets/widgets.dart';
import '../../../services/ai_service.dart';
import '../../../services/ai_model_catalog.dart';

class ApiKeySetupScreen extends StatefulWidget {
  const ApiKeySetupScreen({super.key});

  @override
  State<ApiKeySetupScreen> createState() => _ApiKeySetupScreenState();
}

class _ApiKeySetupScreenState extends State<ApiKeySetupScreen> {
  final _aiKeyController = TextEditingController();
  bool _aiConfigured = false;
  String? _aiTestResult;
  bool _aiTesting = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  @override
  void dispose() {
    _aiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadKeys() async {
    String? aiKey;
    try {
      aiKey = await AiService.getApiKey();
    } catch (_) {
      if (mounted) setState(() => _aiTestResult = '密钥暂时无法读取，请重新输入或稍后重试');
      return;
    }
    if (!mounted) return;
    setState(() {
      _aiConfigured = aiKey != null && aiKey.isNotEmpty;
      if (_aiConfigured) {
        _aiKeyController.text = aiKey!;
      }
    });
  }

  Future<void> _saveAiKey() async {
    if (_saving) return;
    final key = _aiKeyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入 API Key')));
      return;
    }
    setState(() => _saving = true);
    try {
      await AiService.setApiKey(key);
      if (!mounted) return;
      setState(() => _aiConfigured = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('API Key 已安全保存')));
      context.pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('密钥未能安全保存，请重试')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testAiKey() async {
    final key = _aiKeyController.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _aiTesting = true;
      _aiTestResult = null;
    });
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 40),
        ),
      );
      final response = await dio.post(
        'https://api.deepseek.com/v1/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': AiModelCatalog.primary,
          'max_tokens': 5,
          'messages': [
            {'role': 'user', 'content': 'Hi'},
          ],
        },
      );
      if (!mounted) return;
      setState(() {
        _aiTestResult = response.statusCode == 200
            ? '主对话模型连接成功；图片模型需单独发送图片验证'
            : '连接失败';
      });
    } on DioException catch (error) {
      if (!mounted) return;
      final status = error.response?.statusCode;
      setState(
        () => _aiTestResult = status == 401 || status == 403
            ? '密钥无效或无权限'
            : status == 429
            ? '额度不足或请求过多'
            : status == 404
            ? '当前账号不支持 ${AiModelCatalog.primary}'
            : '网络请求未完成，请重试',
      );
    } catch (_) {
      if (mounted) setState(() => _aiTestResult = '测试未完成，请稍后重试');
    } finally {
      if (mounted) setState(() => _aiTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('API Key 管理')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: TaSpacing.page,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: TaSpacing.md),

              Text(
                '外部服务配置',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: TaSpacing.xs),
              Text(
                '以下 API Key 由你自己申请和保管，数据直接从手机发送到对应服务，不经过任何中间服务器。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: TaSpacing.lg),

              // ---- DeepSeek AI ----
              TaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.psychology_rounded,
                          color: theme.colorScheme.primary,
                          size: 24,
                        ),
                        const SizedBox(width: TaSpacing.xs),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'DeepSeek AI',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '用于 AI 对话和关怀建议',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _aiConfigured
                                    ? TaLightColors.success
                                    : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _aiConfigured ? '已配置' : '未配置',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: TaSpacing.md),
                    TaTextField(
                      controller: _aiKeyController,
                      label: 'API Key',
                      hint: 'sk-...',
                      prefixIcon: Icons.key_rounded,
                    ),
                    const SizedBox(height: TaSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: TaButton(
                            onPressed: _aiTesting ? null : _testAiKey,
                            text: '测试连接',
                            loading: _aiTesting,
                          ),
                        ),
                        const SizedBox(width: TaSpacing.sm),
                        Expanded(
                          child: TaButton(onPressed: _saveAiKey, text: '保存'),
                        ),
                      ],
                    ),
                    if (_aiTestResult != null) ...[
                      const SizedBox(height: TaSpacing.xs),
                      Text(
                        _aiTestResult!,
                        style: TextStyle(
                          color: _aiTestResult == '连接成功'
                              ? TaLightColors.success
                              : theme.colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: TaSpacing.xs),
                    Text(
                      '申请地址：platform.deepseek.com',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: TaAnimation.normal),

              const SizedBox(height: TaSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
