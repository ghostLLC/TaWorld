/// TaWorld 头像组件
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';

/// 统一头像组件
///
/// 支持网络图片、占位符、尺寸变体。
class TaAvatar extends StatelessWidget {
  const TaAvatar({
    super.key,
    this.url,
    this.size = TaSizes.avatarMd,
    this.name,
    this.showBorder = false,
  });

  /// 小号头像
  const TaAvatar.small({super.key, this.url, this.name, this.showBorder = false})
      : size = TaSizes.avatarSm;

  /// 大号头像
  const TaAvatar.large({super.key, this.url, this.name, this.showBorder = false})
      : size = TaSizes.avatarLg;

  /// 超大号头像（个人中心）
  const TaAvatar.xl({super.key, this.url, this.name, this.showBorder = false})
      : size = TaSizes.avatarXl;

  final String? url;
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
        child: url != null && url!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                placeholder: (_, __) => _Placeholder(
                  initial: initial,
                  size: size,
                ),
                errorWidget: (_, __, ___) => _Placeholder(
                  initial: initial,
                  size: size,
                ),
              )
            : _Placeholder(initial: initial, size: size),
      ),
    );
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
