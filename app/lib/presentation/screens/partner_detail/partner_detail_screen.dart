/// TaWorld 关心的人 — 详情/编辑页
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../../app/design_tokens.dart';
import '../../widgets/widgets.dart';
import '../../../data/city_data.dart';
import '../../../services/local/partner_service.dart';
import '../../../services/local/local_reminder_service.dart';
import '../../../services/weather_service.dart';
import '../../../services/care_suggestion_service.dart';
import '../../../data/models/partner.dart';

/// 关心的人详情/编辑页
class PartnerDetailScreen extends StatefulWidget {
  const PartnerDetailScreen({super.key, required this.partnerId});

  final String partnerId;

  @override
  State<PartnerDetailScreen> createState() => _PartnerDetailScreenState();
}

class _PartnerDetailScreenState extends State<PartnerDetailScreen> {
  Partner? _partner;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  String? _suggestion;

  late final TextEditingController _nicknameController;
  late final TextEditingController _noteController;
  CitySelection? _selectedCity;
  CitySelection? _originalCity; // 编辑前的城市，用于取消恢复
  String _selectedType = 'couple';

  static const _types = <_PartnerType>[
    _PartnerType('couple', '\u2764\uFE0F', '情侣', 'assets/images/type_couple.png'),
    _PartnerType('family', '\uD83C\uDFE0', '家人', 'assets/images/type_family.png'),
    _PartnerType('friend', '\uD83E\uDD1D', '朋友', 'assets/images/type_friend.png'),
  ];

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController();
    _noteController = TextEditingController();
    _loadPartner();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadPartner() async {
    setState(() => _loading = true);
    try {
      final partner = await PartnerService.getById(widget.partnerId);
      if (!mounted) return;
      setState(() {
        _partner = partner;
        if (partner != null) {
          _nicknameController.text = partner.nickname;
          _noteController.text = partner.note ?? '';
          _selectedCity = partner.city != null && partner.city!.isNotEmpty
              ? CitySelection(
                  city: partner.city!,
                  province: provinceOf(partner.city!),
                )
              : null;
          _originalCity = _selectedCity;
          _selectedType = partner.type;
        }
        _loading = false;
      });
      // 异步加载关怀建议（不阻塞 UI）
      _loadSuggestion(partner);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// 异步加载关怀建议（AI 优先，本地兜底）
  Future<void> _loadSuggestion(Partner? partner) async {
    if (partner == null) return;
    try {
      // 并行获取：提醒配置 + 天气
      final configs = await LocalReminderService.getConfigs(partner.id);
      WeatherResult? weather;
      if (partner.latitude != null && partner.longitude != null) {
        weather = await WeatherService.getCurrentWeather(
          partner.longitude!, partner.latitude!,
        );
      } else if (partner.city != null && partner.city!.isNotEmpty) {
        weather = await WeatherService.getCurrentWeatherByCity(partner.city!);
      }

      final hint = await CareSuggestionService.generate(
        partner: partner,
        configs: configs,
        weather: weather,
      );

      if (!mounted) return;
      setState(() => _suggestion = hint);
    } catch (_) {
      // 建议加载失败不影响主流程
    }
  }

  void _enterEditMode() {
    if (_partner == null) return;
    setState(() {
      _editing = true;
      _nicknameController.text = _partner!.nickname;
      _noteController.text = _partner!.note ?? '';
      _selectedType = _partner!.type;
      _originalCity = _selectedCity;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
      if (_partner != null) {
        _nicknameController.text = _partner!.nickname;
        _noteController.text = _partner!.note ?? '';
        _selectedType = _partner!.type;
        _selectedCity = _originalCity;
      }
    });
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (image == null) return;

    // 复制到 App 私有目录
    final appDir = await getApplicationDocumentsDirectory();
    final avatarDir = Directory('${appDir.path}/avatars');
    if (!await avatarDir.exists()) {
      await avatarDir.create(recursive: true);
    }
    final ext = p.extension(image.path);
    final destPath = '${avatarDir.path}/partner_${widget.partnerId}$ext';
    await File(image.path).copy(destPath);

    await PartnerService.update(widget.partnerId, avatarPath: destPath);
    _loadPartner();
  }

  Future<void> _save() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('昵称不能为空')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await PartnerService.update(
        widget.partnerId,
        nickname: nickname,
        type: _selectedType,
        note: _noteController.text.trim().isNotEmpty
            ? _noteController.text.trim()
            : null,
        city: _selectedCity?.city,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存成功')),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存失败，请重试')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认解除'),
        content: Text('确定要解除与「${_partner?.nickname ?? ''}」的关系吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: TaLightColors.error,
            ),
            child: const Text('确认解除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);

    try {
      await PartnerService.dissolve(widget.partnerId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已解除关系')),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('操作失败，请重试')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('详情')),
        body: const TaLoading(message: '加载中...'),
      );
    }

    if (_partner == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('详情')),
        body: const TaEmptyState(
          icon: Icons.person_off_rounded,
          title: '未找到该联系人',
          subtitle: '该联系人可能已被删除',
        ),
      );
    }

    final partner = _partner!;
    final days = PartnerService.daysSince(partner.createdAt);

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? '编辑资料' : partner.nickname),
        centerTitle: true,
        actions: [
          if (!_editing)
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              tooltip: '编辑',
              onPressed: _enterEditMode,
            )
          else
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: '取消',
              onPressed: _cancelEdit,
            ),
        ],
      ),
      body: ListView(
        padding: TaSpacing.page,
        children: [
          const SizedBox(height: TaSpacing.md),

          // ---- 头像（可点击更换） ----
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  TaAvatar.xl(
                    name: partner.nickname,
                    imageUrl: partner.avatarPath,
                    showBorder: true,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.camera_alt_rounded,
                        color: theme.colorScheme.onPrimary,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: TaAnimation.normal),

          const SizedBox(height: TaSpacing.xs),

          Center(
            child: Text(
              '点击更换头像',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          const SizedBox(height: TaSpacing.md),

          // ---- 昵称 / 编辑昵称 ----
          if (!_editing) ...[
            Center(
              child: Text(
                partner.nickname,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: TaSpacing.xs),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: TaSpacing.sm,
                  vertical: TaSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: TaRadius.borderXs,
                ),
                child: Text(
                  partner.typeLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: TaSpacing.xs),
            Center(
              child: Text(
                '已陪伴 $days 天',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ] else ...[
            TaTextField(
              controller: _nicknameController,
              label: '昵称',
              hint: '输入Ta的昵称',
              prefixIcon: Icons.person_outline_rounded,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '请输入昵称';
                return null;
              },
            ).animate().fadeIn(duration: TaAnimation.fast),
          ],

          const SizedBox(height: TaSpacing.lg),

          // ---- 编辑：关系类型选择 ----
          if (_editing) ...[
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
            ).animate().fadeIn(duration: TaAnimation.fast),
            const SizedBox(height: TaSpacing.lg),
          ],

          // ---- 备注 / 编辑备注 ----
          if (!_editing) ...[
            if (partner.note != null && partner.note!.isNotEmpty) ...[
              TaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.notes_rounded,
                          size: TaSizes.iconSm,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: TaSpacing.xs),
                        Text(
                          '备注',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: TaSpacing.xs),
                    Text(
                      partner.note!,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ).animate().fadeIn(
                delay: 100.ms,
                duration: TaAnimation.normal,
              ),
            ],
            // 城市显示
            if (_selectedCity != null) ...[
              const SizedBox(height: TaSpacing.sm),
              TaCard(
                child: Row(
                  children: [
                    Icon(
                      Icons.location_city_rounded,
                      size: TaSizes.iconSm,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: TaSpacing.xs),
                    Text(
                      '所在城市: ${_selectedCity!.displayText}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ).animate().fadeIn(
                delay: 150.ms,
                duration: TaAnimation.normal,
              ),
            ],
          ] else ...[
            TaTextField(
              controller: _noteController,
              label: '备注（可选）',
              hint: '关于Ta的一些备注...',
              prefixIcon: Icons.notes_rounded,
              maxLines: 3,
            ).animate().fadeIn(
              delay: 100.ms,
              duration: TaAnimation.fast,
            ),
            const SizedBox(height: TaSpacing.md),
            InkWell(
              onTap: () async {
                final result = await showCityPicker(context);
                if (result != null) {
                  setState(() => _selectedCity = result);
                }
              },
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
              delay: 150.ms,
              duration: TaAnimation.fast,
            ),
          ],

          const SizedBox(height: TaSpacing.xl),

          // ---- 统计信息 ----
          if (!_editing)
            TaCard.outlined(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatItem(
                    icon: Icons.calendar_today_rounded,
                    value: '$days',
                    label: '陪伴天数',
                  ),
                  _StatItem(
                    icon: Icons.favorite_rounded,
                    value: partner.typeLabel,
                    label: '关系类型',
                  ),
                ],
              ),
            ).animate().fadeIn(
              delay: 200.ms,
              duration: TaAnimation.normal,
            ),

          const SizedBox(height: TaSpacing.lg),

          // ---- 关怀建议提示卡片 ----
          if (!_editing && _suggestion != null)
            _CareSuggestionCard(
              suggestion: _suggestion!,
              onRefresh: () {
                setState(() => _suggestion = null);
                _loadSuggestion(_partner);
              },
            ).animate().fadeIn(
              delay: 300.ms,
              duration: TaAnimation.slow,
            ),

          const SizedBox(height: TaSpacing.xl),

          // ---- 编辑模式：保存按钮 ----
          if (_editing)
            TaButton(
              onPressed: _save,
              text: '保存修改',
              icon: Icons.check_rounded,
              loading: _saving,
            ).animate().fadeIn(
              delay: 200.ms,
              duration: TaAnimation.fast,
            ),

          // ---- 非编辑模式：提醒配置入口 ----
          if (!_editing) ...[
            SizedBox(
              width: double.infinity,
              child: TaButton(
                onPressed: () {
                  context.push(
                    '/reminders/config/${partner.id}',
                  );
                },
                text: '管理提醒',
                icon: Icons.notifications_active_rounded,
              ),
            ).animate().fadeIn(
              delay: 300.ms,
              duration: TaAnimation.normal,
            ),
            const SizedBox(height: TaSpacing.md),
          ],

          // ---- 解除关系按钮 ----
          Center(
            child: TextButton.icon(
              onPressed: _saving ? null : _confirmDelete,
              icon: Icon(
                Icons.heart_broken_rounded,
                color: TaLightColors.error,
                size: TaSizes.iconSm,
              ),
              label: Text(
                '解除关系',
                style: TextStyle(
                  color: TaLightColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ).animate().fadeIn(
            delay: 400.ms,
            duration: TaAnimation.normal,
          ),

          const SizedBox(height: TaSpacing.xxl),
        ],
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

/// 统计条目
class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: theme.colorScheme.primary, size: TaSizes.iconMd),
        const SizedBox(height: TaSpacing.xxs),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 关怀建议提示卡片
///
/// 半透明、柔和的便签风格，像朋友在旁边轻声提醒。
/// 不可复制、不可直接发送，只作灵感参考。
class _CareSuggestionCard extends StatelessWidget {
  const _CareSuggestionCard({
    required this.suggestion,
    required this.onRefresh,
  });

  final String suggestion;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        TaSpacing.md, TaSpacing.sm, TaSpacing.xs, TaSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: TaRadius.borderMd,
        border: Border.all(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 柔和的灵感图标
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.tips_and_updates_outlined,
              size: 18,
              color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: TaSpacing.xs),
          // 建议文案
          Expanded(
            child: Text(
              suggestion,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
                height: 1.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          // 换一条
          IconButton(
            icon: Icon(
              Icons.refresh_rounded,
              size: 18,
              color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.4),
            ),
            tooltip: '换一条',
            onPressed: onRefresh,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}
