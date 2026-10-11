import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/snippet.dart';
import '../../providers/snippets_provider.dart';
import '../../services/storage/group_storage.dart';
import '../../theme/theme.dart';
import '../../widgets/ui/app_form_field.dart';
import '../../widgets/ui/app_sheet.dart';
import '../../widgets/ui/group_picker_field.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/section_header.dart';

/// Opens the create/edit screen for [existing] (or a new snippet if null).
Future<void> showSnippetFormScreen(
  BuildContext context, {
  Snippet? existing,
  String? initialGroup,
}) {
  return pushAppForm<void>(
    context,
    builder: (_) =>
        SnippetFormScreen(existing: existing, initialGroup: initialGroup),
  );
}

class SnippetFormScreen extends ConsumerStatefulWidget {
  const SnippetFormScreen({super.key, this.existing, this.initialGroup});

  final Snippet? existing;
  final String? initialGroup;

  @override
  ConsumerState<SnippetFormScreen> createState() => _SnippetFormScreenState();
}

/// There is no delete in this form's app bar: a snippet is deleted from its
/// card on the list, the same way a machine is, so there is one place that
/// asks. The save button listens to the name and command controllers
/// directly rather than calling `setState` from each field's `onChanged`:
/// both it and the arguments section change on every keystroke, and
/// rebuilding the whole screen for that would rebuild every input on it -
/// the one being typed into included - once per character. The arguments
/// section itself only shows once the command actually mentions a
/// placeholder, since an empty section would just be a question about
/// something that isn't there yet.
class _SnippetFormScreenState extends ConsumerState<SnippetFormScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _commandCtrl;
  late String _group;
  bool _isSaving = false;

  /// One controller per placeholder the command has ever mentioned while
  /// this screen was open. Kept rather than rebuilt as the command is
  /// edited, so deleting a `{{token}}` and typing it back does not lose the
  /// default that was already entered for it.
  final Map<String, TextEditingController> _defaultCtrls = {};

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _commandCtrl = TextEditingController(text: existing?.command ?? '');
    _group =
        existing?.group ?? widget.initialGroup ?? GroupStorage.defaultGroup;
    existing?.defaults.forEach((name, value) {
      _defaultCtrls[name] = TextEditingController(text: value);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _commandCtrl.dispose();
    for (final ctrl in _defaultCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  bool get _canSave =>
      _nameCtrl.text.trim().isNotEmpty && _commandCtrl.text.trim().isNotEmpty;

  List<String> get _placeholders => Snippet.placeholdersIn(_commandCtrl.text);

  TextEditingController _defaultCtrlFor(String name) =>
      _defaultCtrls.putIfAbsent(name, TextEditingController.new);

  /// Only the placeholders the command actually has right now, and only the
  /// ones given a value - a blank field is "no default", not an empty one.
  Map<String, String> get _defaults => {
    for (final name in _placeholders)
      if ((_defaultCtrls[name]?.text ?? '').isNotEmpty)
        name: _defaultCtrls[name]!.text,
  };

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _isSaving = true);
    final notifier = ref.read(snippetsProvider.notifier);
    final existing = widget.existing;
    if (existing == null) {
      await notifier.addSnippet(
        name: _nameCtrl.text.trim(),
        command: _commandCtrl.text,
        group: _group,
        defaults: _defaults,
      );
    } else {
      await notifier.updateSnippet(
        existing,
        name: _nameCtrl.text.trim(),
        command: _commandCtrl.text,
        group: _group,
        defaults: _defaults,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final isEditing = widget.existing != null;

    return Scaffold(
      backgroundColor: context.colors.backgroundPrimary,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          isEditing ? t.snippets.editTitle : t.snippets.newTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        leading: IconButton(
          tooltip: t.common.close,
          icon: const Icon(PhosphorIconsRegular.x),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : ListenableBuilder(
                    listenable: Listenable.merge([_nameCtrl, _commandCtrl]),
                    builder: (context, _) => TextButton(
                      onPressed: _canSave ? _save : null,
                      child: Text(
                        t.common.save,
                        style: TextStyle(
                          color: _canSave
                              ? context.colors.primary
                              : context.colors.textTertiary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ContentGutter(
          builder: (context, gutter) => ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              isEditing ? 8 : 16,
              20,
              40,
            ).add(gutter),
            children: [
              SectionHeader(t.groups.groupTitle),
              const SizedBox(height: 10),
              GroupPickerField(
                group: _group,
                onChanged: (group) => setState(() => _group = group),
              ),
              const SizedBox(height: 20),
              SectionHeader(
                t.snippets.commandSection,
                hint: t.snippets.placeholderHint,
              ),
              const SizedBox(height: 10),
              AppFormField(
                key: const ValueKey('snippetNameField'),
                controller: _nameCtrl,
                label: t.snippets.nameHint,
                icon: PhosphorIconsFill.tag,
                action: TextInputAction.next,
                autofocus: !isEditing,
              ),
              const SizedBox(height: 10),
              AppFormField(
                key: const ValueKey('snippetCommandField'),
                controller: _commandCtrl,
                label: t.snippets.commandHint,
                minLines: 6,
                maxLines: 12,
                monospace: true,
                keyboardType: TextInputType.multiline,
                action: TextInputAction.newline,
              ),

              ListenableBuilder(
                listenable: _commandCtrl,
                builder: (context, _) {
                  final placeholders = _placeholders;
                  if (placeholders.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 24),
                      SectionHeader(
                        t.snippets.argumentsTitle,
                        hint: t.snippets.argumentsHint,
                      ),
                      const SizedBox(height: 10),
                      for (final name in placeholders) ...[
                        AppFormField(
                          key: ValueKey('snippetDefaultField:$name'),
                          controller: _defaultCtrlFor(name),
                          label: name,
                          icon: PhosphorIconsFill.bracketsCurly,
                          monospace: true,
                          action: TextInputAction.next,
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
