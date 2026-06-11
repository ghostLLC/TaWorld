/// TaWorld 头像组件
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';

/// 统一头像组件
///
/// 支持本地文件图片、占位符、尺寸变体。
class TaAvatar extends StatelessWidget {
  const TaAvatar({
    super.key,
    this.imageUrl,
    this.size = TaSizes.avatarMd,
    this.name,
    this.showBorder = false,
  });

  /// 小号头像
  const TaAvatar.small({super.key, this.imageUrl, this.name, this.showBorder = false})
      : size = TaSizes.avatarSm;

  /// 大号头像
  const TaAvatar.large({super.key, this.imageUrl, this.name, this.showBorder = false})
      : size = TaSizes.avatarLg;

  /// 超大号头像（个人中心）
  const TaAvatar.xl({super.key, this.imageUrl, this.name, this.showBorder = false})
      : size = TaSizes.avatarXl;

  final String? imageUrl;
  final double size;
  final String? name;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = (name ?? '?').characters.first.toUpperCase();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: showBorder
            ? Border.all(color: theme.colorScheme.primary, width: 2)
            : null,
        boxShadow: TaShadows.sm,
      ),
      child: ClipOval(
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? _buildImage(initial, size)
            : _Placeholder(initial: initial, size: size),
      ),
    );
  }

  Widget _buildImage(String initial, double size) {
    // 本地文件路径
    final file = File(imageUrl!);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (_, _, _) => _Placeholder(initial: initial, size: size),
      );
    }
    // 路径无效，显示占位符
    return _Placeholder(initial: initial, size: size);
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.initial, required this.size});

  final String initial;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: TaGradients.warm,
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: theme.colorScheme.primary,
            fontSize: size * 0.4,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
