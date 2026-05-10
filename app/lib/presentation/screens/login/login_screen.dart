/// TaWorld 登录页面
///
/// 参考页面实现 — 展示如何使用设计系统组件。
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../services/auth_service.dart';
import '../../widgets/widgets.dart';

/// 登录页面
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dio = createDioClient();
      final response = await dio.post(ApiEndpoints.login, data: {
        'phone': _phoneController.text.trim(),
        'password': _passwordController.text,
      });

      final data = response.data;
      if (data['code'] == 0) {
        await AuthService.saveTokens(
          accessToken: data['data']['access_token'],
          refreshToken: data['data']['refresh_token'],
        );
        if (mounted) context.go(Routes.home);
      } else {
        setState(() => _error = data['message']);
      }
    } on DioException catch (e) {
      final msg = e.response?.data?['message'] ?? '网络连接失败，请稍后重试';
      setState(() => _error = msg.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: TaSpacing.page,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: TaSpacing.xxxl),

                // ---- Logo 区域 ----
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: TaGradients.primary,
                          borderRadius: TaRadius.borderLg,
                          boxShadow: TaShadows.md,
                        ),
                        child: const Icon(
                          Icons.favorite_rounded,
                          size: 40,
                          color: Colors.white,
                        ),
                      ).animate().scale(
                            delay: 200.ms,
                            duration: 600.ms,
                            curve: TaAnimation.bounce,
                          ),
                      const SizedBox(height: TaSpacing.md),
                      Text(
                        'Ta的世界',
                        style: theme.textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ).animate().fadeIn(delay: 400.ms, duration: 500.ms),
                      const SizedBox(height: TaSpacing.xs),
                      Text(
                        '让关怀自然发生',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ).animate().fadeIn(delay: 600.ms, duration: 500.ms),
                    ],
                  ),
                ),

                const SizedBox(height: TaSpacing.xxl),

                // ---- 表单 ----
                TaTextField(
                  controller: _phoneController,
                  label: '手机号',
                  hint: '请输入手机号',
                  prefixIcon: Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    if (v == null || v.isEmpty) return '请输入手机号';
                    if (v.length < 11) return '手机号格式不正确';
                    return null;
                  },
                ).animate().fadeIn(delay: 700.ms).slideX(begin: -0.05),

                const SizedBox(height: TaSpacing.md),

                TaTextField(
                  controller: _passwordController,
                  label: '密码',
                  hint: '请输入密码',
                  prefixIcon: Icons.lock_rounded,
                  obscureText: true,
                  validator: (v) {
                    if (v == null || v.isEmpty) return '请输入密码';
                    if (v.length < 6) return '密码至少6位';
                    return null;
                  },
                ).animate().fadeIn(delay: 800.ms).slideX(begin: -0.05),

                // ---- 错误提示 ----
                if (_error != null) ...[
                  const SizedBox(height: TaSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(TaSpacing.sm),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withValues(alpha: 0.1),
                      borderRadius: TaRadius.borderSm,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: TaSizes.iconSm,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: TaSpacing.xs),
                        Expanded(
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: TaSpacing.lg),

                // ---- 登录按钮 ----
                TaButton(
                  onPressed: _login,
                  text: '登录',
                  loading: _loading,
                  icon: Icons.login_rounded,
                ).animate().fadeIn(delay: 900.ms),

                const SizedBox(height: TaSpacing.md),

                // ---- 注册入口 ----
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '还没有账号？',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.push(Routes.register),
                      child: const Text('立即注册'),
                    ),
                  ],
                ).animate().fadeIn(delay: 1000.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
