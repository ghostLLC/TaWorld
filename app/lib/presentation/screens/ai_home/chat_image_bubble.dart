import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';

class ChatImageBubble extends StatelessWidget {
  const ChatImageBubble({
    super.key,
    required this.localPath,
    required this.summary,
  });

  final String localPath;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final file = File(localPath);
    return Semantics(
      label: '用户发送的图片：$summary',
      child: Container(
        constraints: const BoxConstraints(maxWidth: 288),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.primaryContainer.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colors.primary.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: colors.primary.withValues(alpha: 0.07),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 288 / 184,
              child: file.existsSync()
                  ? Image.file(
                      file,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, _, _) => const _MissingImage(),
                    )
                  : const _MissingImage(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                TaSpacing.sm,
                TaSpacing.xs,
                TaSpacing.sm,
                TaSpacing.sm,
              ),
              child: Text(
                summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onPrimaryContainer.withValues(alpha: 0.82),
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingImage extends StatelessWidget {
  const _MissingImage();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerHighest.withValues(alpha: 0.72),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 6),
            Text(
              '图片文件暂不可用',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
