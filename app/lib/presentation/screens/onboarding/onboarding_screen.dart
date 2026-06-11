/// TaWorld 首次引导页
///
/// 用户第一次打开应用时展示的欢迎界面。
/// 收集用户昵称后创建本地用户，然后跳转至首页。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../widgets/widgets.dart';
import '../../../services/local/local_user_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nicknameController = TextEditingController();
  bool _loading = false;
  bool _canSubmit = false;

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  void _onNicknameChanged(String value) {
    final canSubmit = value.trim().isNotEmpty;
    if (canSubmit != _canSubmit) {
      setState(() => _canSubmit = canSubmit);
    }
  }

  Future<void> _onStart() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) return;

    setState(() => _loading = true);

    try {
      await LocalUserService.createUser(nickname: nickname);
      if (!mounted) return;
      context.go(Routes.home);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: TaSpacing.page,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ---- 顶部装饰图标 ----
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

                // ---- 应用名称 ----
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

                // ---- 副标题 ----
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

                // ---- 昵称输入 ----
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

                // ---- 开始按钮 ----
                SizedBox(
                  width: double.infinity,
                  child: TaButton(
                    onPressed: _loading ? null : _onStart,
                    text: '开始关怀之旅',
                    icon: Icons.favorite_rounded,
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

  /// 顶部装饰性渐变圆形图标
  Widget _buildHeroIcon(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: TaGradients.warm,
        boxShadow: TaShadows.lg,
      ),
      child: Icon(
        Icons.favorite_rounded,
        size: 56,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
