import 'package:flutter/material.dart';

/// A labeled wrapper around a child widget.
class AppField extends StatelessWidget {
  final String label;
  final Widget child;
  final String? hint;
  final Widget? trailing;

  const AppField({
    super.key,
    required this.label,
    required this.child,
    this.hint,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const Spacer(),
            ?trailing,
          ],
        ),
        const SizedBox(height: 6),
        child,
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }
}

class AppInput extends StatefulWidget {
  final String label;
  final TextEditingController? controller;
  final String? initialValue;
  final String? hint;
  final String? errorText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final int? maxLines;

  const AppInput({
    super.key,
    required this.label,
    this.controller,
    this.initialValue,
    this.hint,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
    this.maxLines = 1,
  });

  @override
  State<AppInput> createState() => _AppInputState();
}

class _AppInputState extends State<AppInput> {
  TextEditingController? _internal;

  TextEditingController get _effectiveController {
    if (widget.controller != null) return widget.controller!;
    return _internal ??= TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _internal?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppField(
      label: widget.label,
      hint: widget.hint,
      child: TextField(
        controller: _effectiveController,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        maxLines: widget.maxLines,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          hintText: widget.hint,
          errorText: widget.errorText,
          errorMaxLines: 3,
        ),
      ),
    );
  }
}

class AppTextarea extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final String? initialValue;
  final String? hint;
  final int minLines;
  final ValueChanged<String>? onChanged;

  const AppTextarea({
    super.key,
    required this.label,
    this.controller,
    this.initialValue,
    this.hint,
    this.minLines = 4,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppInput(
      label: label,
      controller: controller,
      initialValue: initialValue,
      hint: hint,
      maxLines: null,
      onChanged: onChanged,
    );
  }
}

class AppSelect extends StatelessWidget {
  final String label;
  final List<({String value, String label})> options;
  final String? value;
  final ValueChanged<String?>? onChanged;
  final String? hint;

  const AppSelect({
    super.key,
    required this.label,
    required this.options,
    this.value,
    this.onChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return AppField(
      label: label,
      hint: hint,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(),
        items: [
          for (final opt in options)
            DropdownMenuItem(value: opt.value, child: Text(opt.label)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}