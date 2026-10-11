import 'package:flutter/material.dart';

import '../../app.dart';
import '../../i18n/strings.g.dart';
import '../../services/ssh/ssh_prompts.dart';
import '../../theme/theme.dart';

/// Puts a keyboard-interactive round in front of the user.
///
/// This is how a 2FA code, a PAM password or an expired-password change
/// reaches the person who can answer it. Like the host key prompt it is
/// raised from the SSH layer, so it goes through the root navigator; with no
/// navigator there is nobody to ask and the round is cancelled rather than
/// answered with blanks, which is what used to lock these servers out.
Future<List<String>?> showKeyboardInteractivePrompt(
  KeyboardInteractiveRequest request,
) async {
  final context = navigatorKey.currentContext;
  if (context == null) return null;
  return showDialog<List<String>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _KeyboardInteractiveDialog(request: request),
  );
}

class _KeyboardInteractiveDialog extends StatefulWidget {
  const _KeyboardInteractiveDialog({required this.request});

  final KeyboardInteractiveRequest request;

  @override
  State<_KeyboardInteractiveDialog> createState() =>
      _KeyboardInteractiveDialogState();
}

/// The server says whether an answer is a secret. Honour it rather than
/// assuming: a one-time code is often echoed, and a hidden field makes it
/// needlessly hard to type.
class _KeyboardInteractiveDialogState
    extends State<_KeyboardInteractiveDialog> {
  bool _answered = false;

  late final List<TextEditingController> _controllers = [
    for (final _ in widget.request.questions) TextEditingController(),
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  /// The dialog answers once. A second tap - Cancel hit twice, or hit as the
  /// route is already going - would pop a navigator with nothing left on it,
  /// which throws rather than doing nothing.
  void _close(List<String>? answers) {
    if (_answered || !mounted) return;
    _answered = true;
    Navigator.of(context).pop(answers);
  }

  void _submit() =>
      _close([for (final controller in _controllers) controller.text]);

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final request = widget.request;
    final heading = request.name.trim();
    final instruction = request.instruction.trim();

    return AlertDialog(
      title: Text(heading.isEmpty ? t.keyboardInteractive.title : heading),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (instruction.isNotEmpty) ...[
              Text(instruction, style: colors.uiStyle),
              const SizedBox(height: AppTheme.spaceLg),
            ],
            for (var i = 0; i < request.questions.length; i++) ...[
              if (i > 0) const SizedBox(height: AppTheme.spaceMd),
              TextField(
                controller: _controllers[i],
                autofocus: i == 0,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                obscureText: !request.questions[i].echo,
                textInputAction: i == request.questions.length - 1
                    ? TextInputAction.done
                    : TextInputAction.next,
                onSubmitted: i == request.questions.length - 1
                    ? (_) => _submit()
                    : null,
                decoration: InputDecoration(
                  labelText: request.questions[i].prompt.trim().isEmpty
                      ? t.keyboardInteractive.fallbackPrompt
                      : request.questions[i].prompt.trim(),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => _close(null), child: Text(t.common.cancel)),
        TextButton(
          onPressed: _submit,
          child: Text(t.keyboardInteractive.submit),
        ),
      ],
    );
  }
}
