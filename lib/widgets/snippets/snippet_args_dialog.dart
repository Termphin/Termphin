import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../models/snippet.dart';
import '../../theme/theme.dart';

/// Asks for [snippet]'s `{{placeholder}}` values and completes with them, or
/// with null when cancelled.
///
/// The one form for a snippet's arguments, whoever runs it - the snippet
/// picker and a snippet key on the toolbar both open this. Each field starts
/// on the snippet's saved default, selected, so Enter takes it as it is and
/// typing replaces it; Enter on the last field runs.
Future<Map<String, String>?> showSnippetArgsDialog(
  BuildContext context,
  Snippet snippet,
) {
  return showDialog<Map<String, String>>(
    context: context,
    builder: (_) => SnippetArgsDialog(snippet: snippet),
  );
}

class SnippetArgsDialog extends StatefulWidget {
  const SnippetArgsDialog({super.key, required this.snippet});

  final Snippet snippet;

  @override
  State<SnippetArgsDialog> createState() => _SnippetArgsDialogState();
}

class _SnippetArgsDialogState extends State<SnippetArgsDialog> {
  late final List<String> _names = widget.snippet.placeholders;
  final _controllers = <String, TextEditingController>{};
  final _focusNodes = <String, FocusNode>{};

  @override
  void initState() {
    super.initState();
    for (final name in _names) {
      final value = widget.snippet.defaultFor(name);
      _controllers[name] = TextEditingController(text: value)
        ..selection = TextSelection(baseOffset: 0, extentOffset: value.length);
      _focusNodes[name] = FocusNode();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _run() {
    Navigator.of(
      context,
    ).pop({for (final name in _names) name: _controllers[name]!.text});
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      borderSide: BorderSide(color: colors.surfaceBorder),
    );

    return AlertDialog(
      title: Text(widget.snippet.name),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.snippet.command,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: colors.monoStyle.copyWith(
                fontSize: 12,
                color: colors.textTertiary,
              ),
            ),
            const SizedBox(height: 16),
            for (final (index, name) in _names.indexed) ...[
              TextField(
                key: ValueKey('snippetArgField:$name'),
                controller: _controllers[name],
                focusNode: _focusNodes[name],
                autofocus: index == 0,
                textInputAction: index == _names.length - 1
                    ? TextInputAction.done
                    : TextInputAction.next,
                onSubmitted: (_) {
                  if (index == _names.length - 1) {
                    _run();
                  } else {
                    _focusNodes[_names[index + 1]]?.requestFocus();
                  }
                },
                style: TextStyle(fontSize: 15, color: colors.textPrimary),
                decoration: InputDecoration(
                  labelText: name,
                  labelStyle: const TextStyle(fontSize: 13),
                  filled: true,
                  fillColor: colors.fieldFill,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: border,
                  enabledBorder: border,
                  focusedBorder: border.copyWith(
                    borderSide: BorderSide(color: colors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.common.cancel),
        ),
        FilledButton(
          key: const ValueKey('snippetArgsRun'),
          onPressed: _run,
          child: Text(t.snippets.run),
        ),
      ],
    );
  }
}
