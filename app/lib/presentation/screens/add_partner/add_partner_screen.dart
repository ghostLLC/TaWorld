/// TaWorld 添加关心的人页面
///
/// 支持 GPS 定位（含权限引导）和城市选择器（省-市浏览 + 模糊搜索）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/design_tokens.dart';
import '../../widgets/widgets.dart';
import '../../../services/local/partner_service.dart';

/// 添加关心的人 — 选择关系类型、填写昵称，保存到本地
class AddPartnerScreen extends StatefulWidget {
  const AddPartnerScreen({super.key});

  @override
  State<AddPartnerScreen> createState() => _AddPartnerScreenState();
}

class _AddPartnerScreenState extends State<AddPartnerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  final _noteController = TextEditingController();

  String _selectedType = 'couple';
  bool _saving = false;
  Position? _position;
  bool _fetchingLocation = false;
  CitySelection? _selectedCity;

  static const _types = <_PartnerType>[
    _PartnerType('couple', '\u2764\uFE0F', '情侣', 'assets/images/type_couple.png'),
    _PartnerType('family', '\uD83C\uDFE0', '家人', 'assets/images/type_family.png'),
    _PartnerType('friend', '\uD83E\uDD1D', '朋友', 'assets/images/type_friend.png'),
  ];

  @override
  void dispose() {
    _nicknameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // ============================================================
  // 位置获取 + 权限引导
  // ============================================================

  Future<void> _getLocation() async {
    // 1. 检查位置服务是否开启
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      _showLocationServiceDialog();
      return;
    }

    // 2. 检查/请求权限
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      if (!mounted) return;
      _showPermissionDeniedDialog();
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      _showPermissionForeverDialog();
      return;
    }

    // 3. 权限OK，获取位置
    setState(() => _fetchingLocation = true);
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.low),
      );
      if (!mounted) return;
      setState(() => _position = position);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已获取位置: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('获取位置失败，请手动选择城市')),
      );
    } finally {
      if (mounted) setState(() => _fetchingLocation = false);
    }
  }

  /// 位置服务未开启 → 引导去系统设置
  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('位置服务未开启'),
        content: const Text('需要开启系统的位置服务才能获取位置信息，是否前往设置？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            child: const Text('去开启'),
          ),
        ],
      ),
    );
  }

  /// 权限被拒绝 → 再次请求或引导
  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要位置权限'),
        content: const Text('TaWorld 需要访问您的位置来提供天气服务。请在弹出的权限对话框中选择"允许"。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('暂不授权'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final p = await Geolocator.requestPermission();
              if (p == LocationPermission.whileInUse ||
                  p == LocationPermission.always) {
                _getLocation();
              }
            },
            child: const Text('再试一次'),
          ),
        ],
      ),
    );
  }

  /// 权限被永久拒绝 → 引导到应用设置页
  void _showPermissionForeverDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('位置权限已关闭'),
        content: const Text(
          '您之前拒绝了位置权限。如需开启，请前往系统设置 > 应用 > TaWorld > 权限 中手动开启位置权限。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('暂不开启'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 城市选择
  // ============================================================

  Future<void> _pickCity() async {
    final result = await showCityPicker(context);
    if (result != null && mounted) {
      setState(() => _selectedCity = result);
    }
  }

  // ============================================================
  // 保存
  // ============================================================

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      // 如果没有手动获取位置，尝试自动获取（静默）
      Position? position = _position;
      if (position == null) {
        try {
          final serviceOk = await Geolocator.isLocationServiceEnabled();
          if (serviceOk) {
            final perm = await Geolocator.checkPermission();
            if (perm == LocationPermission.whileInUse ||
                perm == LocationPermission.always) {
              position = await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                    accuracy: LocationAccuracy.low),
              );
            }
          }
        } catch (_) {}
      }

      await PartnerService.add(
        nickname: _nicknameController.text.trim(),
        type: _selectedType,
        note: _noteController.text.trim().isNotEmpty
            ? _noteController.text.trim()
            : null,
        latitude: position?.latitude,
        longitude: position?.longitude,
        city: _selectedCity?.city,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('添加成功')),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('添加失败，请重试')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('添加关心的人'),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: TaSpacing.page,
          children: [
            const SizedBox(height: TaSpacing.sm),

            // ---- 关系类型 ----
            Text(
              '选择关系',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: TaSpacing.xs),

            Row(
              children: [
                for (int i = 0; i < _types.length; i++) ...[
                  if (i > 0) const SizedBox(width: TaSpacing.xs),
                  Expanded(
                    child: _TypeCard(
                      type: _types[i],
                      selected: _selectedType == _types[i].value,
                      onTap: () =>
                          setState(() => _selectedType = _types[i].value),
                    ),
                  ),
                ],
              ],
            ).animate().fadeIn(
              duration: TaAnimation.normal,
              curve: TaAnimation.curve,
            ),

            const SizedBox(height: TaSpacing.lg),

            // ---- 昵称 ----
            TaTextField(
              controller: _nicknameController,
              label: '昵称',
              hint: '输入Ta的昵称',
              prefixIcon: Icons.person_outline_rounded,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return '请输入昵称';
                }
                return null;
              },
            ).animate().fadeIn(
              delay: 100.ms,
              duration: TaAnimation.normal,
              curve: TaAnimation.curve,
            ),

            const SizedBox(height: TaSpacing.md),

            // ---- 备注 ----
            TaTextField(
              controller: _noteController,
              label: '备注（可选）',
              hint: '关于Ta的一些备注...',
              prefixIcon: Icons.notes_rounded,
              maxLines: 3,
            ).animate().fadeIn(
              delay: 200.ms,
              duration: TaAnimation.normal,
              curve: TaAnimation.curve,
            ),

            const SizedBox(height: TaSpacing.md),

            // ---- 获取位置（可选）----
            Row(
              children: [
                Expanded(
                  child: _position == null
                      ? Text(
                          '位置信息（可选）',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      : Text(
                          '已获取: ${_position!.latitude.toStringAsFixed(4)}, ${_position!.longitude.toStringAsFixed(4)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                ),
                TextButton.icon(
                  onPressed: _fetchingLocation ? null : _getLocation,
                  icon: _fetchingLocation
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded),
                  label: Text(_fetchingLocation ? '获取中...' : '获取我的位置'),
                ),
              ],
            ).animate().fadeIn(
              delay: 250.ms,
              duration: TaAnimation.normal,
              curve: TaAnimation.curve,
            ),

            const SizedBox(height: TaSpacing.sm),

            // ---- 城市选择器 ----
            InkWell(
              onTap: _pickCity,
              borderRadius: TaRadius.borderXs,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: TaSpacing.md,
                  vertical: TaSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  borderRadius: TaRadius.borderXs,
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_city_rounded,
                        size: 20,
                        color: _selectedCity != null
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: TaSpacing.xs),
                    Expanded(
                      child: Text(
                        _selectedCity != null
                            ? _selectedCity!.displayText
                            : '选择所在城市（可选）',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _selectedCity != null
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (_selectedCity != null)
                      GestureDetector(
                        onTap: () => setState(() => _selectedCity = null),
                        child: Icon(Icons.close_rounded,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    const SizedBox(width: TaSpacing.xs),
                    Icon(Icons.chevron_right_rounded,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ).animate().fadeIn(
              delay: 300.ms,
              duration: TaAnimation.normal,
              curve: TaAnimation.curve,
            ),

            const SizedBox(height: TaSpacing.xl),

            // ---- 保存按钮 ----
            TaButton(
              onPressed: _save,
              text: '保存',
              icon: Icons.check_rounded,
              loading: _saving,
            ).animate().fadeIn(
              delay: 350.ms,
              duration: TaAnimation.normal,
              curve: TaAnimation.curve,
            ),

            const SizedBox(height: TaSpacing.xxl),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 私有组件
// ============================================================

/// 关系类型数据
class _PartnerType {
  const _PartnerType(this.value, this.emoji, this.label, this.asset);

  final String value;
  final String emoji;
  final String label;
  final String asset;
}

/// 可点击选中的类型卡片
class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final _PartnerType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: TaAnimation.fast,
      curve: TaAnimation.curve,
      child: TaCard(
        padding: const EdgeInsets.symmetric(
          vertical: TaSpacing.md,
          horizontal: TaSpacing.xs,
        ),
        onTap: onTap,
        color: selected
            ? TaLightColors.primaryContainer
            : theme.colorScheme.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              type.asset,
              width: 48,
              height: 48,
            ),
            const SizedBox(height: TaSpacing.xxs),
            Text(
              type.label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected
                    ? TaLightColors.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
