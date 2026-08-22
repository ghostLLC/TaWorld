import 'package:flutter/material.dart';

/// Quiet image affordance placed inside the conversational input field.
class AiImageInputButton extends StatelessWidget {
  const AiImageInputButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '发送图片',
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      iconSize: 21,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        Icons.add_photo_alternate_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
