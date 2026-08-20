import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';

class OnboardingPromptBubble extends StatelessWidget {
  const OnboardingPromptBubble({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    this.enabled = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: TaSpacing.xxs),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: TaSpacing.md,
          vertical: TaSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(TaRadius.md),
            topRight: Radius.circular(TaRadius.md),
            bottomLeft: Radius.circular(TaRadius.xs),
            bottomRight: Radius.circular(TaRadius.md),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text('先来告诉我一个你在意的人吧：', style: theme.textTheme.bodyMedium),
            ),
            const SizedBox(width: TaSpacing.xxs),
            SizedBox(
              width: 92,
              child: TextField(
                key: const ValueKey('onboarding-inline-input'),
                controller: controller,
                focusNode: focusNode,
                autofocus: enabled,
                enabled: enabled,
                maxLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (value) {
                  final trimmed = value.trim();
                  if (trimmed.isNotEmpty) onSubmitted(trimmed);
                },
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '名字',
                  contentPadding: const EdgeInsets.only(bottom: 2),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
