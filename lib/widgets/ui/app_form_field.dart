import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/theme.dart';

/// A single text input, independently bordered and rounded. No shared card
/// to clip against and no border state left for the app's default input
/// theme to leak through - every variant (enabled/focused/error/disabled)
/// is nulled explicitly, so this is always exactly the border you see drawn
/// on the [Container] around it, never two.
///
/// The one field widget every create/edit screen in the app builds its
/// forms out of - profile and snippet editors alike - so the two never
/// drift into different-looking inputs by accident.
class AppFormField extends StatelessWidget {
  const AppFormField({
    super.key,
    required this.controller,
    this.label,
    this.hint = '',
    this.icon,
    this.action = TextInputAction.next,
    this.keyboardType,
    this.inputFormatters,
    this.obscure = false,
    this.validator,
    this.suffix,
    this.minLines,
    this.maxLines = 1,
    this.monospace = false,
    this.autofocus = false,
    this.readOnly = false,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? label;
  final String hint;
  final IconData? icon;
  final TextInputAction action;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscure;
  final FormFieldValidator<String>? validator;
  final Widget? suffix;
  final int? minLines;
  final int maxLines;
  final bool monospace;
  final bool autofocus;
  final bool readOnly;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: context.colors.fieldDecoration,
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        textInputAction: action,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        obscureText: obscure,
        validator: validator,
        minLines: minLines,
        maxLines: obscure ? 1 : maxLines,
        autofocus: autofocus,
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
        style: monospace
            ? context.colors.monoStyle.copyWith(
                color: context.colors.textPrimary,
                fontSize: AppTheme.font12,
              )
            : TextStyle(
                fontSize: AppTheme.font15,
                color: context.colors.textPrimary,
              ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(
            color: context.colors.textTertiary,
            fontSize: monospace ? AppTheme.font12 : AppTheme.font14,
          ),
          prefixIcon: icon != null
              ? Icon(
                  icon,
                  size: AppTheme.icon18,
                  color: context.colors.textTertiary,
                )
              : null,
          suffixIcon: suffix,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.space14,
            vertical: AppTheme.space14,
          ),
          labelStyle: TextStyle(
            color: context.colors.textTertiary,
            fontSize: AppTheme.font13,
          ),
        ),
      ),
    );
  }
}

/// A bordered text field with a trailing "add" button, committing on submit
/// or on tap - the shape every quick-add row (tags, fallback hosts, ...)
/// shares instead of hand-rolling its own border.
class AppInlineAddField extends StatelessWidget {
  const AppInlineAddField({
    super.key,
    required this.controller,
    required this.hint,
    required this.addTooltip,
    required this.onSubmit,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String hint;
  final String addTooltip;
  final VoidCallback onSubmit;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: context.colors.fieldDecoration,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.done,
              keyboardType: keyboardType,
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              onSubmitted: (_) => onSubmit(),
              style: TextStyle(
                fontSize: AppTheme.font14,
                color: context.colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  color: context.colors.textTertiary,
                  fontSize: AppTheme.font14,
                ),
                filled: false,
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.space14,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: addTooltip,
            icon: Icon(
              PhosphorIconsRegular.plus,
              size: AppTheme.icon18,
              color: context.colors.primary,
            ),
            onPressed: onSubmit,
          ),
        ],
      ),
    );
  }
}

/// Faint bordered placeholder for an empty list section - same box language
/// as the input below it, so the section reads as one piece.
class AppEmptyHint extends StatelessWidget {
  const AppEmptyHint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space14,
        vertical: AppTheme.space12,
      ),
      decoration: context.colors.fieldDecoration,
      child: Text(
        text,
        style: TextStyle(
          color: context.colors.textTertiary,
          fontSize: AppTheme.font13,
        ),
      ),
    );
  }
}
