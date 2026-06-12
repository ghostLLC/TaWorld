/// TaWorld 首次引导页
///
/// 用户第一次打开应用时展示的欢迎界面。
/// 分两步：1) 设置昵称 2) 可选配置 API Key
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../widgets/widgets.dart';
import '../../../services/local/local_user_service.dart';
import '../../../services/ai_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0; // 0 = 昵称, 1 = API Key
  final _nicknameController = TextEditingController();
  final _deepseekKeyController = TextEditingController();
  bool _loading = false;
  bool _canSubmit = false;
  bool _savingKeys = false;

  @override
  void dispose() {
    _nicknameController.dispose();
    _deepseekKeyController.dispose();
    super.dispose();
  }

  void _onNicknameChanged(String value) {
    final canSubmit = value.trim().isNotEmpty;
    if (canSubmit != _canSubmit) {
      setState(() => _canSubmit = canSubmit);
    }
  }

  Future<void> _onNicknameNext() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) return;

    setState(() => _loading = true);

    try {
      await LocalUserService.createUser(nickname: nickname);
      if (!mounted) return;
      setState(() {
        _step = 1;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('创建失败，请重试：$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _onFinish() async {
    setState(() => _savingKeys = true);

    try {
      final deepseekKey = _deepseekKeyController.text.trim();

      if (deepseekKey.isNotEmpty) {
        await AiService.setApiKey(deepseekKey);
      }
    } catch (_) {
      // 保存失败不影响进入主页
    }

    if (!mounted) return;
    setState(() => _savingKeys = false);
    context.go(Routes.home);
  }

  Future<void> _skipApiKeys() async {
    context.go(Routes.home);
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_step == 0) {
      return _buildNicknameStep(context);
    } else {
      return _buildApiKeyStep(context);
    }
  }

  Widget _buildNicknameStep(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: TaSpacing.page,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeroIcon(context)
                    .animate()
                    .fadeIn(
                      duration: TaAnimation.slow,
                      curve: TaAnimation.curveOut,
                    )
                    .scale(
                      begin: const Offset(0.8, 0.8),
                      end: const Offset(1.0, 1.0),
                      duration: TaAnimation.slow,
                      curve: TaAnimation.curveOut,
                    ),

                const SizedBox(height: TaSpacing.xl),

                Text(
                  'Ta的世界',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: 1.2,
                  ),
                )
                    .animate()
                    .fadeIn(
                      duration: TaAnimation.normal,
                      delay: const Duration(milliseconds: 200),
                      curve: TaAnimation.curveOut,
                    )
                    .slideY(
                      begin: 0.15,
                      end: 0,
                      duration: TaAnimation.normal,
                      delay: const Duration(milliseconds: 200),
                      curve: TaAnimation.curveOut,
                    ),

                const SizedBox(height: TaSpacing.xs),

                Text(
                  '记录你的每一份关心',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w400,
                  ),
                )
                    .animate()
                    .fadeIn(
                      duration: TaAnimation.normal,
                      delay: const Duration(milliseconds: 350),
                      curve: TaAnimation.curveOut,
                    )
                    .slideY(
                      begin: 0.15,
                      end: 0,
                      duration: TaAnimation.normal,
                      delay: const Duration(milliseconds: 350),
                      curve: TaAnimation.curveOut,
                    ),

                const SizedBox(height: TaSpacing.xxl),

                SizedBox(
                  width: double.infinity,
                  child: TaTextField(
                    controller: _nicknameController,
                    label: '你的昵称',
                    hint: '输入一个你喜欢的名字',
                    prefixIcon: Icons.person_outline_rounded,
                    onChanged: _onNicknameChanged,
                  ),
                )
                    .animate()
                    .fadeIn(
                      duration: TaAnimation.normal,
                      delay: const Duration(milliseconds: 500),
                      curve: TaAnimation.curveOut,
                    )
                    .slideY(
                      begin: 0.2,
                      end: 0,
                      duration: TaAnimation.normal,
                      delay: const Duration(milliseconds: 500),
                      curve: TaAnimation.curveOut,
                    ),

                const SizedBox(height: TaSpacing.xl),

                SizedBox(
                  width: double.infinity,
                  child: TaButton(
                    onPressed: _loading ? null : _onNicknameNext,
                    text: '下一步',
                    icon: Icons.arrow_forward_rounded,
                    loading: _loading,
                    enabled: _canSubmit && !_loading,
                    gradient: TaGradients.primary,
                  ),
                )
                    .animate()
                    .fadeIn(
                      duration: TaAnimation.normal,
                      delay: const Duration(milliseconds: 650),
                      curve: TaAnimation.curveOut,
                    )
                    .slideY(
                      begin: 0.2,
                      end: 0,
                      duration: TaAnimation.normal,
                      delay: const Duration(milliseconds: 650),
                      curve: TaAnimation.curveOut,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildApiKeyStep(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: TaSpacing.page,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 步骤指示器
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StepDot(active: true),
                      const SizedBox(width: TaSpacing.xs),
                      _StepDot(active: false),
                    ],
                  ),
                ).animate().fadeIn(duration: TaAnimation.fast),

                const SizedBox(height: TaSpacing.lg),

                Center(
                  child: Text(
                    '配置 AI 服务（可选）',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ).animate().fadeIn(delay: 100.ms),

                const SizedBox(height: TaSpacing.xs),

                Center(
                  child: Text(
                    '配置 DeepSeek API Key 后可解锁 AI 关怀建议功能\n天气查询已使用免费开源服务，无需配置',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ).animate().fadeIn(delay: 200.ms),

                const SizedBox(height: TaSpacing.xl),

                // DeepSeek API Key
                TaCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Image.asset(
                            'assets/images/ai_config_illustration.png',
                            width: 40,
                            height: 40,
                          ),
                          const SizedBox(width: TaSpacing.xs),
                          Expanded(
                            child: Text(
                              'DeepSeek API Key',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: TaSpacing.xs),
                      Text(
                        '用于 AI 关怀助手功能，帮你生成温暖的关怀语',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: TaSpacing.sm),
                      TaTextField(
                        controller: _deepseekKeyController,
                        hint: 'sk-...',
                        prefixIcon: Icons.key_rounded,
                        obscureText: true,
                      ),
                      const SizedBox(height: TaSpacing.xs),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _openUrl(
                            'https://platform.deepseek.com/api_keys',
                          ),
                          icon: const Icon(Icons.open_in_new_rounded, size: 16),
                          label: const Text('获取 API Key'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: TaSpacing.sm,
                              vertical: TaSpacing.xxs,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 300.ms, duration: TaAnimation.normal),

                const SizedBox(height: TaSpacing.xl),

                // 按钮组
                SizedBox(
                  width: double.infinity,
                  child: TaButton(
                    onPressed: _savingKeys ? null : _onFinish,
                    text: '保存并开始',
                    icon: Icons.check_rounded,
                    loading: _savingKeys,
                    gradient: TaGradients.primary,
                  ),
                ).animate().fadeIn(delay: 500.ms),

                const SizedBox(height: TaSpacing.sm),

                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _savingKeys ? null : _skipApiKeys,
                    child: Text(
                      '跳过，稍后在设置中配置',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: 600.ms),

                const SizedBox(height: TaSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroIcon(BuildContext context) {
    return Image.asset(
      'assets/images/onboarding_mascot.png',
      width: 120,
      height: 120,
    );
  }
}

/// 步骤指示器圆点
class _StepDot extends StatelessWidget {
  const _StepDot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: TaAnimation.fast,
      width: active ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: active
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
      ),
    );
  }
}
