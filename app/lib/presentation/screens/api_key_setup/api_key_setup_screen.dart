/// TaWorld API Key 管理页面
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:dio/dio.dart';

import '../../../app/design_tokens.dart';
import '../../widgets/widgets.dart';
import '../../../services/ai_service.dart';
import '../../../services/weather_service.dart';

class ApiKeySetupScreen extends StatefulWidget {
  const ApiKeySetupScreen({super.key});

  @override
  State<ApiKeySetupScreen> createState() => _ApiKeySetupScreenState();
}

class _ApiKeySetupScreenState extends State<ApiKeySetupScreen> {
  final _aiKeyController = TextEditingController();
  final _weatherKeyController = TextEditingController();
  bool _aiKeyVisible = false;
  bool _weatherKeyVisible = false;
  bool _aiConfigured = false;
  bool _weatherConfigured = false;
  String? _aiTestResult;
  String? _weatherTestResult;
  bool _aiTesting = false;
  bool _weatherTesting = false;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  @override
  void dispose() {
    _aiKeyController.dispose();
    _weatherKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadKeys() async {
    final aiKey = await AiService.getApiKey();
    final weatherKey = await WeatherService.getApiKey();
    setState(() {
      _aiConfigured = aiKey != null && aiKey.isNotEmpty;
      _weatherConfigured = weatherKey != null && weatherKey.isNotEmpty;
      if (_aiConfigured) {
        _aiKeyController.text = aiKey!;
      }
      if (_weatherConfigured) {
        _weatherKeyController.text = weatherKey!;
      }
    });
  }

  Future<void> _saveAiKey() async {
    final key = _aiKeyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 API Key')),
      );
      return;
    }
    await AiService.setApiKey(key);
    setState(() => _aiConfigured = true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('DeepSeek API Key 已保存')),
    );
  }

  Future<void> _saveWeatherKey() async {
    final key = _weatherKeyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 API Key')),
      );
      return;
    }
    await WeatherService.setApiKey(key);
    setState(() => _weatherConfigured = true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('和风天气 API Key 已保存')),
    );
  }

  Future<void> _testAiKey() async {
    final key = _aiKeyController.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _aiTesting = true;
      _aiTestResult = null;
    });
    try {
      final dio = Dio();
      final response = await dio.post(
        'https://api.deepseek.com/v1/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': 'deepseek-chat',
          'max_tokens': 5,
          'messages': [
            {'role': 'user', 'content': 'Hi'},
          ],
        },
      );
      setState(() {
        _aiTestResult = response.statusCode == 200 ? '连接成功' : '连接失败';
      });
    } catch (e) {
      setState(() => _aiTestResult = '连接失败：${e.toString().substring(0, e.toString().length.clamp(0, 50))}');
    } finally {
      setState(() => _aiTesting = false);
    }
  }

  Future<void> _testWeatherKey() async {
    final key = _weatherKeyController.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _weatherTesting = true;
      _weatherTestResult = null;
    });
    try {
      final dio = Dio();
      final response = await dio.get(
        'https://devapi.qweather.com/v7/weather/now',
        queryParameters: {
          'location': '101010100', // 北京
          'key': key,
        },
      );
      setState(() {
        _weatherTestResult = response.data['code'] == '200' ? '连接成功' : 'Key 无效';
      });
    } catch (e) {
      setState(() => _weatherTestResult = '连接失败');
    } finally {
      setState(() => _weatherTesting = false);
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
                        Icon(Icons.psychology_rounded,
                            color: theme.colorScheme.primary, size: 24),
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
                      obscureText: !_aiKeyVisible,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _aiKeyVisible
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _aiKeyVisible = !_aiKeyVisible),
                      ),
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
                          child: TaButton(
                            onPressed: _saveAiKey,
                            text: '保存',
                          ),
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

              const SizedBox(height: TaSpacing.lg),

              // ---- QWeather ----
              TaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.cloud_rounded,
                            color: TaLightColors.tertiary, size: 24),
                        const SizedBox(width: TaSpacing.xs),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '和风天气',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '用于天气查询和天气提醒',
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
                                color: _weatherConfigured
                                    ? TaLightColors.success
                                    : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _weatherConfigured ? '已配置' : '未配置',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: TaSpacing.md),
                    TaTextField(
                      controller: _weatherKeyController,
                      label: 'API Key',
                      hint: '输入和风天气 Key',
                      obscureText: !_weatherKeyVisible,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _weatherKeyVisible
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 20,
                        ),
                        onPressed: () => setState(
                            () => _weatherKeyVisible = !_weatherKeyVisible),
                      ),
                    ),
                    const SizedBox(height: TaSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: TaButton(
                            onPressed:
                                _weatherTesting ? null : _testWeatherKey,
                            text: '测试连接',
                            loading: _weatherTesting,
                          ),
                        ),
                        const SizedBox(width: TaSpacing.sm),
                        Expanded(
                          child: TaButton(
                            onPressed: _saveWeatherKey,
                            text: '保存',
                          ),
                        ),
                      ],
                    ),
                    if (_weatherTestResult != null) ...[
                      const SizedBox(height: TaSpacing.xs),
                      Text(
                        _weatherTestResult!,
                        style: TextStyle(
                          color: _weatherTestResult == '连接成功'
                              ? TaLightColors.success
                              : theme.colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: TaSpacing.xs),
                    Text(
                      '申请地址：dev.qweather.com（免费版每日1000次）',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(
                  delay: 200.ms, duration: TaAnimation.normal),

              const SizedBox(height: TaSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
