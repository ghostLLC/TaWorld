/// TaWorld 关心的人 — 详情/编辑页
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../../widgets/widgets.dart';
import '../../../services/local/partner_service.dart';
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

  late final TextEditingController _nicknameController;
  late final TextEditingController _noteController;
  String _selectedType = 'couple';

  static const _types = <_PartnerType>[
    _PartnerType('couple', '\u2764\uFE0F', '情侣'),
    _PartnerType('family', '\uD83C\uDFE0', '家人'),
    _PartnerType('friend', '\uD83E\uDD1D', '朋友'),
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
          _selectedType = partner.type;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _enterEditMode() {
    if (_partner == null) return;
    setState(() {
      _editing = true;
      _nicknameController.text = _partner!.nickname;
      _noteController.text = _partner!.note ?? '';
      _selectedType = _partner!.type;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
      if (_partner != null) {
        _nicknameController.text = _partner!.nickname;
        _noteController.text = _partner!.note ?? '';
        _selectedType = _partner!.type;
      }
    });
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

          // ---- 头像 ----
          Center(
            child: TaAvatar.xl(
              name: partner.nickname,
              imageUrl: partner.avatarPath,
              showBorder: true,
            ),
          ).animate().fadeIn(duration: TaAnimation.normal),

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
