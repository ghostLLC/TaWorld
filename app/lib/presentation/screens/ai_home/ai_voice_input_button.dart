import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';

/// Compact voice affordance for the conversational input bar.
///
/// The resting state stays visually quiet; the listening state uses a warm
/// tint and equalizer glyph instead of adding another persistent label.
class AiVoiceInputButton extends StatelessWidget {
  const AiVoiceInputButton({
    super.key,
    required this.isListening,
    required this.onPressed,
  });

  final bool isListening;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isListening
            ? colors.primary.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: TaRadius.borderFull,
        border: Border.all(
          color: isListening
              ? colors.primary.withValues(alpha: 0.32)
              : Colors.transparent,
        ),
      ),
      child: IconButton(
        tooltip: isListening ? '停止语音输入' : '语音输入',
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        iconSize: 21,
        visualDensity: VisualDensity.compact,
        icon: Icon(
          isListening ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
          color: isListening ? colors.primary : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}
