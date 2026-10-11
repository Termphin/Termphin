import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';

/// Asks for one line of text - a new name, a folder, a file. Returns the
/// trimmed text when [confirmLabel] is pressed or the field is submitted and
/// [validator] (if any) accepts it; null when cancelled.
///
/// [obscureText] is for a secret - a passphrase - which is hidden as it is
/// typed and returned exactly as typed: a space at either end of one is
/// part of it.
///
/// The controller is disposed a frame late: the dialog's exit transition can
/// still rebuild the field for a frame after the route is popped, and
/// disposing synchronously would trip "TextEditingController used after
/// being disposed".
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initialValue = '',
  String? labelText,
    String? hintText,
  FormFieldValidator<String>? validator,
  bool obscureText = false,
}) async {
  final t = Translations.of(context);
  final controller = TextEditingController(text: initialValue);
  final formKey = GlobalKey<FormState>();

  void submit(BuildContext ctx) {
    if (formKey.currentState?.validate() ?? false) {
            Navigator.of(
        ctx,
      ).pop(obscureText ? controller.text : controller.text.trim());
    }
  }

  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
                    autofocus: true,
          obscureText: obscureText,
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          decoration: InputDecoration(labelText: labelText, hintText: hintText),
          validator: validator,
          onFieldSubmitted: (_) => submit(ctx),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(t.common.cancel),
        ),
        TextButton(onPressed: () => submit(ctx), child: Text(confirmLabel)),
      ],
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  return result;
}
