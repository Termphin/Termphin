import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/ssh_key.dart';
import '../../providers/ssh_keys_provider.dart';
import '../../services/storage/group_storage.dart';
import '../../services/storage/ssh_key_storage.dart';
import '../../theme/theme.dart';
import '../../widgets/groups/group_picker_field.dart';
import '../../widgets/ssh/public_key_dialog.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_form_field.dart';
import '../../widgets/ui/app_notifications.dart';
import '../../widgets/ui/large_title_scaffold.dart';
import '../../widgets/ui/section_header.dart';

/// Opens the create/edit screen for [existing] (or a new key if null).
///
/// Completes with the key a create or import made, so a caller that asked
/// for one - the machine form - can pick it straight away.
Future<SshKey?> showKeyFormScreen(
  BuildContext context, {
  String? initialGroup,
  String? initialName,
  SshKey? existing,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<SshKey>(
      builder: (_) => KeyFormScreen(
        initialGroup: initialGroup,
        initialName: initialName,
        existing: existing,
      ),
      fullscreenDialog: true,
    ),
  );
}

class KeyFormScreen extends ConsumerStatefulWidget {
  const KeyFormScreen({
    super.key,
    this.initialGroup,
    this.initialName,
    this.existing,
  });

  final String? initialGroup;
  final String? initialName;
  final SshKey? existing;

  @override
  ConsumerState<KeyFormScreen> createState() => _KeyFormScreenState();
}

enum _KeyFormType { ed25519, rsa2048, rsa4096, import }

class _KeyFormScreenState extends ConsumerState<KeyFormScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _pemCtrl;
  late final TextEditingController _passphraseCtrl;
  late String _group;
  _KeyFormType _selectedType = _KeyFormType.ed25519;
  String? _selectedFileName;
  bool _readingFile = false;
  bool _isSaving = false;

  /// Whether the pasted key needs a passphrase, read off the key itself rather
  /// than asked for on every import.
  bool _pemIsEncrypted = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl = TextEditingController(
      text: existing?.name ?? widget.initialName ?? '',
    );
    _pemCtrl = TextEditingController();
    _passphraseCtrl = TextEditingController();
    _group =
        existing?.group ?? widget.initialGroup ?? GroupStorage.defaultGroup;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pemCtrl.dispose();
    _passphraseCtrl.dispose();
    super.dispose();
  }

  /// Whether the form holds enough to save: for an import, that also means a
  /// passphrase if the pasted key is encrypted, since an encrypted key cannot
  /// be read at all without one and saving would only repeat the failure the
  /// user just saw.
  bool get _canSave {
    if (_isSaving) return false;
    final nameTrimmed = _nameCtrl.text.trim();
    if (nameTrimmed.isEmpty) return false;

    if (_isEditing) return true;

    if (_selectedType == _KeyFormType.import) {
      if (_pemCtrl.text.trim().isEmpty) return false;
      if (_pemIsEncrypted && _passphraseCtrl.text.isEmpty) return false;
      return true;
    }

    return true;
  }

  void _onPemChanged(String value) {
    final encrypted = SshKeyStorage.isEncryptedPem(value.trim());
    if (encrypted == _pemIsEncrypted) return;
    setState(() => _pemIsEncrypted = encrypted);
  }

  /// Reads a key file into [_pemCtrl], rejecting it past 1 MiB. A file whose
  /// length is unknown passes the first check; the streamed read below
  /// enforces the cap regardless.
  Future<void> _pickKeyFile() async {
    final t = Translations.of(context);
    setState(() => _readingFile = true);
    try {
      final result = await FilePicker.pickFiles(type: FileType.any);
      if (result.isEmpty) return;
      final file = result.single;
      if ((await file.length() ?? 0) > 1024 * 1024) {
        throw _KeyFileReadException(t.keys.keyFileTooLarge);
      }
      final stream = file.readAsByteStream();
      final builder = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        if (builder.length + chunk.length > 1024 * 1024) {
          throw _KeyFileReadException(t.keys.keyFileTooLarge);
        }
        builder.add(chunk);
      }
      final pem = utf8.decode(builder.takeBytes()).trim();
      if (pem.isEmpty) {
        throw _KeyFileReadException(t.keys.keyFileEmpty);
      }
      if (!mounted) return;
      setState(() {
        _selectedFileName = file.name;
        _pemCtrl.text = pem;
        _pemIsEncrypted = SshKeyStorage.isEncryptedPem(pem);
        if (_nameCtrl.text.trim().isEmpty) {
          _nameCtrl.text = file.name.replaceFirst(
            RegExp(r'\.(pem|key)$', caseSensitive: false),
            '',
          );
        }
      });
    } on _KeyFileReadException catch (error) {
      if (!mounted) return;
      AppNotifications.error(context, error.message);
    } catch (error) {
      if (!mounted) return;
      AppNotifications.error(
        context,
        t.keys.keyFileReadFailed(error: '$error'),
      );
    } finally {
      if (mounted) {
        setState(() => _readingFile = false);
      }
    }
  }

  /// Generates or imports the key depending on [_selectedType]. An import
  /// that turns out to be encrypted only reveals that once the key has been
  /// read, so this is also where the passphrase field first appears.
  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _isSaving = true);
    final storage = ref.read(sshKeyStorageProvider);
    final t = Translations.of(context);

    try {
      if (_isEditing) {
        final updated = widget.existing!.copyWith(
          name: _nameCtrl.text.trim(),
          group: _group,
          updatedAt: DateTime.now(),
        );
        await storage.updateKey(updated);
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }

      final SshKey key;
      switch (_selectedType) {
        case _KeyFormType.ed25519:
          key = await storage.generateEd25519(
            _nameCtrl.text.trim(),
            group: _group,
          );
        case _KeyFormType.rsa2048:
          key = await storage.generateRsa(
            _nameCtrl.text.trim(),
            2048,
            group: _group,
          );
        case _KeyFormType.rsa4096:
          key = await storage.generateRsa(
            _nameCtrl.text.trim(),
            4096,
            group: _group,
          );
        case _KeyFormType.import:
          key = await storage.importFromPem(
            _nameCtrl.text.trim(),
            _pemCtrl.text.trim(),
            group: _group,
            passphrase: _passphraseCtrl.text,
          );
      }

      if (!mounted) return;

      if (_selectedType == _KeyFormType.import) {
        AppNotifications.success(context, t.keys.importSuccess(name: key.name));
        Navigator.of(context).pop(key);
      } else {
        setState(() => _isSaving = false);
        await showPublicKeyDialog(context, key);
        if (!mounted) return;
        Navigator.of(context).pop(key);
      }
    } on KeyImportException catch (error) {
      if (!mounted) return;
      setState(() => _pemIsEncrypted = true);
      switch (error.reason) {
        case KeyImportFailure.wrongPassphrase:
          _passphraseCtrl.clear();
          AppNotifications.error(context, t.keys.importWrongPassphrase);
        case KeyImportFailure.passphraseRequired:
          AppNotifications.error(context, t.keys.importPassphraseRequired);
      }
    } catch (error) {
      if (!mounted) return;
      final message = _selectedType == _KeyFormType.import
          ? t.keys.importFailed(error: '$error')
          : t.keys.generateFailed(error: '$error');
      AppNotifications.error(context, message);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  IconData _keyTypeIcon(SshKeyType type) => switch (type) {
    SshKeyType.ed25519 => PhosphorIconsFill.sparkle,
    SshKeyType.rsa2048 => PhosphorIconsFill.lock,
    SshKeyType.rsa4096 => PhosphorIconsFill.shieldCheck,
  };

  String _keyTypeLabel(Translations t, SshKeyType type) => switch (type) {
    SshKeyType.ed25519 => t.keys.keyTypeEd25519,
    SshKeyType.rsa2048 => t.keys.keyTypeRsa2048,
    SshKeyType.rsa4096 => t.keys.keyTypeRsa4096,
  };

  String _keyTypeSubtitle(Translations t, SshKeyType type) => switch (type) {
    SshKeyType.ed25519 => t.keys.keyTypeEd25519Subtitle,
    SshKeyType.rsa2048 => t.keys.keyTypeRsa2048Subtitle,
    SshKeyType.rsa4096 => t.keys.keyTypeRsa4096Subtitle,
  };

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return Scaffold(
      backgroundColor: context.colors.backgroundPrimary,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          _isEditing ? t.keys.editKeyTitle : t.keys.newKeyTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        leading: IconButton(
          tooltip: t.common.close,
          icon: const Icon(PhosphorIconsRegular.x),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppTheme.space12),
            child: _isSaving
                ? const SizedBox(
                    width: AppTheme.icon20,
                    height: AppTheme.icon20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : ListenableBuilder(
                    listenable: Listenable.merge([
                      _nameCtrl,
                      _pemCtrl,
                      _passphraseCtrl,
                    ]),
                    builder: (context, _) => TextButton(
                      onPressed: _canSave ? _save : null,
                      child: Text(
                        t.common.save,
                        style: TextStyle(
                          color: _canSave
                              ? context.colors.primary
                              : context.colors.textTertiary,
                          fontWeight: FontWeight.w700,
                          fontSize: AppTheme.font15,
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
              AppTheme.space20,
              _isEditing ? AppTheme.space8 : AppTheme.space16,
              AppTheme.space20,
              AppTheme.space40,
            ).add(gutter),
            children: [
              SectionHeader(t.groups.groupTitle),
              const SizedBox(height: AppTheme.space10),
              GroupPickerField(
                group: _group,
                onChanged: (group) => setState(() => _group = group),
              ),
              const SizedBox(height: AppTheme.space20),
              AppFormField(
                key: const ValueKey('keyNameField'),
                controller: _nameCtrl,
                label: t.keys.keyNameLabel,
                hint: t.keys.keyNameHint,
                icon: PhosphorIconsFill.key,
                action: TextInputAction.next,
                autofocus: !_isEditing,
              ),
              const SizedBox(height: AppTheme.space24),
              SectionHeader(t.keys.keyTypeLabel),
              const SizedBox(height: AppTheme.space10),
              if (_isEditing) ...[
                _KeyTypeOption(
                  icon: _keyTypeIcon(widget.existing!.keyType),
                  label: _keyTypeLabel(t, widget.existing!.keyType),
                  subtitle: _keyTypeSubtitle(t, widget.existing!.keyType),
                  isSelected: false,
                  onTap: null,
                ),
              ] else ...[
                _KeyTypeOption(
                  key: const ValueKey('keyTypeOption:ed25519'),
                  icon: PhosphorIconsFill.sparkle,
                  label: t.keys.keyTypeEd25519,
                  subtitle: t.keys.keyTypeEd25519Subtitle,
                  isSelected: _selectedType == _KeyFormType.ed25519,
                  onTap: () =>
                      setState(() => _selectedType = _KeyFormType.ed25519),
                ),
                const SizedBox(height: AppTheme.space8),
                _KeyTypeOption(
                  key: const ValueKey('keyTypeOption:rsa2048'),
                  icon: PhosphorIconsFill.lock,
                  label: t.keys.keyTypeRsa2048,
                  subtitle: t.keys.keyTypeRsa2048Subtitle,
                  isSelected: _selectedType == _KeyFormType.rsa2048,
                  onTap: () =>
                      setState(() => _selectedType = _KeyFormType.rsa2048),
                ),
                const SizedBox(height: AppTheme.space8),
                _KeyTypeOption(
                  key: const ValueKey('keyTypeOption:rsa4096'),
                  icon: PhosphorIconsFill.shieldCheck,
                  label: t.keys.keyTypeRsa4096,
                  subtitle: t.keys.keyTypeRsa4096Subtitle,
                  isSelected: _selectedType == _KeyFormType.rsa4096,
                  onTap: () =>
                      setState(() => _selectedType = _KeyFormType.rsa4096),
                ),
                const SizedBox(height: AppTheme.space8),
                _KeyTypeOption(
                  key: const ValueKey('keyTypeOption:import'),
                  icon: PhosphorIconsFill.fileArrowUp,
                  label: t.keys.keyTypeImport,
                  subtitle: t.keys.keyTypeImportSubtitle,
                  isSelected: _selectedType == _KeyFormType.import,
                  onTap: () =>
                      setState(() => _selectedType = _KeyFormType.import),
                ),
                if (_selectedType == _KeyFormType.import) ...[
                  const SizedBox(height: AppTheme.space16),
                  OutlinedButton.icon(
                    onPressed: _readingFile ? null : _pickKeyFile,
                    icon: _readingFile
                        ? const SizedBox.square(
                            dimension: AppTheme.icon16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            PhosphorIconsFill.fileArrowUp,
                            size: AppTheme.icon18,
                          ),
                    label: Text(t.keys.selectPrivateKeyFile),
                  ),
                  if (_selectedFileName != null) ...[
                    const SizedBox(height: AppTheme.space8),
                    Text(
                      t.keys.selectedFile(name: _selectedFileName!),
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.colors.success,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppTheme.space12),
                  AppFormField(
                    key: const ValueKey('keyPemField'),
                    controller: _pemCtrl,
                    label: t.keys.privateKeyLabel,
                    hint: t.keys.privateKeyHint,
                    minLines: 6,
                    maxLines: 14,
                    monospace: true,
                    keyboardType: TextInputType.multiline,
                    action: TextInputAction.newline,
                    onChanged: _onPemChanged,
                  ),
                  if (_pemIsEncrypted) ...[
                    const SizedBox(height: AppTheme.space12),
                    AppFormField(
                      key: const ValueKey('keyPassphraseField'),
                      controller: _passphraseCtrl,
                      label: t.keys.keyPassphraseLabel,
                      hint: t.keys.keyPassphraseHint,
                      obscure: true,
                      action: TextInputAction.done,
                    ),
                    const SizedBox(height: AppTheme.space6),
                    Text(
                      t.keys.keyPassphraseNote,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.colors.textTertiary,
                      ),
                    ),
                  ],
                ],
                if (_isSaving) ...[
                  const SizedBox(height: AppTheme.space20),
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.space16,
                      vertical: AppTheme.space12,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox.square(
                          dimension: AppTheme.icon16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.colors.primary,
                          ),
                        ),
                        const SizedBox(width: AppTheme.space10),
                        Text(
                          t.keys.generating,
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: AppTheme.font14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyFileReadException implements Exception {
  const _KeyFileReadException(this.message);

  final String message;
}

class _KeyTypeOption extends StatelessWidget {
  const _KeyTypeOption({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      elevated: true,
      selected: isSelected,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space16,
        vertical: AppTheme.space14,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: isSelected
                ? context.colors.primary
                : context.colors.textSecondary,
            size: AppTheme.icon22,
          ),
          const SizedBox(width: AppTheme.space14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: AppTheme.font14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppTheme.space2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.colors.textTertiary,
                    fontSize: AppTheme.font12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
