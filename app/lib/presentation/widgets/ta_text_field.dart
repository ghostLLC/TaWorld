/// TaWorld 输入框组件
library;

import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';

/// 统一输入框
///
/// 内置圆角、暖色填充、focus 动画。
/// 支持密码模式、前缀/后缀图标。
class TaTextField extends StatefulWidget {
  const TaTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.onChanged,
    this.maxLines = 1,
    this.enabled = true,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final bool enabled;
  final bool autofocus;

  @override
  State<TaTextField> createState() => _TaTextFieldState();
}

class _TaTextFieldState extends State<TaTextField> {
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: TaSpacing.xs),
        ],
        TextFormField(
          controller: widget.controller,
          obscureText: _obscured,
          keyboardType: widget.keyboardType,
          validator: widget.validator,
          onChanged: widget.onChanged,
          maxLines: widget.maxLines,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: widget.prefixIcon != null
                ? Icon(widget.prefixIcon, size: TaSizes.iconMd)
                : null,
            suffixIcon: widget.obscureText
                ? IconButton(
                    icon: Icon(
                      _obscured
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: TaSizes.iconMd,
                    ),
                    onPressed: () => setState(() => _obscured = !_obscured),
                  )
                : widget.suffixIcon,
          ),
        ),
      ],
    );
  }
}
