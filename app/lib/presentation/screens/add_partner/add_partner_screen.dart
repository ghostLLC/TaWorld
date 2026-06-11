/// TaWorld 添加关心的人页面
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';

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

  static const _types = <_PartnerType>[
    _PartnerType('couple', '\u2764\uFE0F', '情侣'),
    _PartnerType('family', '\uD83C\uDFE0', '家人'),
    _PartnerType('friend', '\uD83E\uDD1D', '朋友'),
  ];

  @override
  void dispose() {
    _nicknameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _getLocation() async {
    setState(() => _fetchingLocation = true);
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      );
      if (!mounted) return;
      setState(() => _position = position);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已获取位置: ${position.latitude.toStringAsFixed(2)}, ${position.longitude.toStringAsFixed(2)}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('获取位置失败，可继续保存')),
      );
    } finally {
      if (mounted) setState(() => _fetchingLocation = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      // Try to get current position if not already fetched
      Position? position = _position;
      if (position == null) {
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
          );
        } catch (_) {
          // Location not available, continue without it
        }
      }

      await PartnerService.add(
        nickname: _nicknameController.text.trim(),
        type: _selectedType,
        note: _noteController.text.trim().isNotEmpty
            ? _noteController.text.trim()
            : null,
        latitude: position?.latitude,
        longitude: position?.longitude,
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
                      onTap: () => setState(() => _selectedType = _types[i].value),
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
              hint: '关于Ta的一些备注…',
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
                          '已获取位置: ${_position!.latitude.toStringAsFixed(2)}, ${_position!.longitude.toStringAsFixed(2)}',
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded),
                  label: Text(_fetchingLocation ? '获取中…' : '获取我的位置'),
                ),
              ],
            ).animate().fadeIn(
              delay: 250.ms,
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
              delay: 300.ms,
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
  const _PartnerType(this.value, this.emoji, this.label);

  final String value;
  final String emoji;
  final String label;
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
            Text(
              type.emoji,
              style: const TextStyle(fontSize: 28),
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
