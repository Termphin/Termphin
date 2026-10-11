import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../models/port_forwarding_rule.dart';
import '../../models/ssh_key.dart';
import '../../models/ssh_profile.dart';
import '../../providers/anonymize_provider.dart';
import '../../providers/profiles_provider.dart';
import '../../providers/ssh_keys_provider.dart';
import '../../screens/keys/key_form_screen.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/app/identity_anonymizer.dart';
import '../../services/sftp/cancel_token.dart';
import '../../services/ssh/ssh_link.dart';
import '../../services/ssh/ssh_session_manager.dart';
import '../../services/storage/group_storage.dart';
import '../../theme/theme.dart';
import '../../utils/group_match.dart';
import '../terminal/port_forwarding_rule_sheet.dart';
import '../terminal/port_forwarding_rule_tile.dart';
import '../ui/add_row_card.dart';
import '../ui/app_card.dart';
import '../ui/app_divider.dart';
import '../ui/app_form_field.dart';
import '../ui/app_notifications.dart';
import '../ui/app_sheet.dart';
import '../ui/avatar_picker.dart';
import '../ui/empty_state.dart';
import '../ui/group_picker_field.dart';
import '../ui/large_title_scaffold.dart';
import '../ui/section_header.dart';
import '../ui/settings_controls.dart';
import 'jump_host_sheet.dart';

enum _KeySource { keyManager, manual }

typedef ConnectionTest =
    Future<void> Function(SshProfile profile, CancelToken cancel);

/// What "Test connection" runs. A provider so a test can stand in for the
/// network.
final connectionTestProvider = Provider<ConnectionTest>(
  (ref) =>
      (profile, cancel) =>
          SshSessionManager.instance.testConnection(profile, cancel: cancel),
);

class ProfileFormDialog extends ConsumerStatefulWidget {
  const ProfileFormDialog({
    super.key,
    this.profile,
    this.prefill,
    this.initialGroup,
  });

  final SshProfile? profile;
  final SshLink? prefill;
  final String? initialGroup;

  @override
  ConsumerState<ProfileFormDialog> createState() => _ProfileFormDialogState();
}

class _ProfileFormDialogState extends ConsumerState<ProfileFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _passphraseCtrl;
  late final TextEditingController _privateKeyCtrl;

  /// Null on a new machine until one is picked: guessing "password" because
  /// a username was typed put people on a method they never chose.
  AuthMethod? _authMethod;
  bool _authMissing = false;
  _KeySource _keySource = _KeySource.keyManager;
  bool _isSaving = false;
  bool _hidePassword = true;
  bool _hidePassphrase = true;
  bool _showManualEntry = false;
  String? _privateKeyContent;

  List<SshKey> _availableKeys = [];
  bool _keysLoading = false;
  String? _selectedKeyId;
  CancelToken? _testCancel;

  /// Null until a test has run; then either success or the failure's text.
  ({bool ok, String message})? _testResult;

  List<PortForwardingRule> _forwardingRules = [];

  String _group = GroupStorage.defaultGroup;

  List<String> _fallbackHosts = [];
  bool _mainHostFirst = true;
  final _fallbackHostInputCtrl = TextEditingController();

  String? _jumpHostProfileId;

  String? _iconName;
  String? _colorHex;

  @override
  void initState() {
    super.initState();
    unawaited(AnalyticsService.instance.screen(AnalyticsScreen.profileForm));
    final p = widget.profile;
    final link = widget.prefill;
    _nameCtrl = TextEditingController(text: p?.name ?? link?.host ?? '');
    _hostCtrl = TextEditingController(text: p?.host ?? link?.host ?? '');
    _portCtrl = TextEditingController(text: '${p?.port ?? link?.port ?? 22}');
    _userCtrl = TextEditingController(text: p?.username ?? link?.user ?? '');
    _passwordCtrl = TextEditingController(text: p?.password ?? '');
    _passphraseCtrl = TextEditingController(text: p?.passphrase ?? '');
    _privateKeyCtrl = TextEditingController(text: p?.privateKey ?? '');

    _authMethod = p?.authMethod;
    _privateKeyContent = p?.privateKey;

    if (p?.sshKeyId != null) {
      _keySource = _KeySource.keyManager;
      _selectedKeyId = p!.sshKeyId;
    } else if (p?.privateKey != null) {
      _keySource = _KeySource.manual;
      _showManualEntry = true;
    }

    if (_authMethod == AuthMethod.privateKey) _loadKeys();

    _forwardingRules = List.from(p?.portForwardings ?? []);
    _group = p?.group ?? widget.initialGroup ?? GroupStorage.defaultGroup;
    _fallbackHosts = List.from(p?.fallbackHosts ?? []);
    _mainHostFirst = p?.mainHostFirst ?? true;
    _jumpHostProfileId = p?.jumpHostProfileId;
    _iconName = p?.iconName;
    _colorHex = p?.colorHex;
  }

  Future<void> _loadKeys() async {
    setState(() => _keysLoading = true);
    final keys = await ref.read(sshKeyStorageProvider).loadKeys();
    if (mounted) {
      setState(() {
        _availableKeys = keys;
        _keysLoading = false;
      });
    }
  }

  /// Opens the full key screen - any type, or an import - named after this
  /// machine, and picks what it made.
  Future<void> _createKey() async {
    final key = await showKeyFormScreen(
      context,
      initialGroup: _group,
      initialName: _effectiveName,
    );
    if (key == null || !mounted) return;
    setState(() {
      _availableKeys = [..._availableKeys, key];
      _selectedKeyId = key.id;
      _keySource = _KeySource.keyManager;
      _showManualEntry = false;
    });
  }

  @override
  void dispose() {
    _testCancel?.cancel();
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passwordCtrl.dispose();
    _passphraseCtrl.dispose();
    _privateKeyCtrl.dispose();
    _fallbackHostInputCtrl.dispose();
    super.dispose();
  }

  /// A name is optional: left empty, the machine is called by its host, the
  /// way a quick add names it.
  String get _effectiveName {
    final name = _nameCtrl.text.trim();
    return name.isEmpty ? _hostCtrl.text.trim() : name;
  }

  /// The profile as the fields describe it right now, saved or not.
  SshProfile _draftProfile() {
    final now = DateTime.now();
    return SshProfile(
      id: widget.profile?.id ?? 'draft',
      name: _effectiveName,
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 22,
      username: _userCtrl.text.trim(),
      authMethod: _authMethod!,
      password: _authMethod == AuthMethod.password ? _passwordCtrl.text : null,
      privateKey:
          _authMethod == AuthMethod.privateKey &&
              _keySource == _KeySource.manual
          ? _privateKeyContent
          : null,
      passphrase: _authMethod == AuthMethod.privateKey
          ? _passphraseCtrl.text
          : null,
      sshKeyId:
          _authMethod == AuthMethod.privateKey &&
              _keySource == _KeySource.keyManager
          ? _selectedKeyId
          : null,
      createdAt: widget.profile?.createdAt ?? now,
      fallbackHosts: _fallbackHosts,
      mainHostFirst: _mainHostFirst,
      jumpHostProfileId: _jumpHostProfileId,
    );
  }

  /// The fields, and that a sign-in method was picked - which no field of
  /// the form can say for itself.
  bool _validate() {
    final fieldsOk = _formKey.currentState!.validate();
    setState(() => _authMissing = _authMethod == null);
    // The picker is usually below the fold, so the missing choice is also
    // said where it cannot be scrolled away from.
    if (fieldsOk && _authMissing) {
      AppNotifications.error(
        context,
        Translations.of(context).profileForm.chooseAuth,
      );
    }
    return fieldsOk && _authMethod != null;
  }

  /// Tapping again while it runs stops it.
  Future<void> _testConnection() async {
    final running = _testCancel;
    if (running != null) {
      running.cancel();
      return;
    }
    if (!_validate()) return;
    final t = Translations.of(context);
    final cancel = CancelToken();
    setState(() {
      _testCancel = cancel;
      _testResult = null;
    });
    ({bool ok, String message})? result;
    try {
      await ref.read(connectionTestProvider)(_draftProfile(), cancel);
      result = (ok: true, message: t.profileForm.testSucceeded);
    } on TransferCancelled {
      result = null;
    } catch (error) {
      result = (ok: false, message: error.toString());
    }
    if (!mounted) return;
    setState(() {
      _testCancel = null;
      _testResult = result;
    });
  }

  Future<void> _save() async {
    if (!_validate()) return;
    setState(() => _isSaving = true);

    final notifier = ref.read(profilesProvider.notifier);
    final port = int.tryParse(_portCtrl.text.trim()) ?? 22;

    final effectiveSshKeyId =
        (_authMethod == AuthMethod.privateKey &&
            _keySource == _KeySource.keyManager)
        ? _selectedKeyId
        : null;
    final effectivePrivateKey =
        (_authMethod == AuthMethod.privateKey &&
            _keySource == _KeySource.manual)
        ? _privateKeyContent
        : null;

    try {
      if (widget.profile == null) {
        await notifier.addProfile(
          name: _effectiveName,
          host: _hostCtrl.text.trim(),
          port: port,
          username: _userCtrl.text.trim(),
          authMethod: _authMethod!,
          password: _authMethod == AuthMethod.password
              ? _passwordCtrl.text
              : null,
          privateKey: effectivePrivateKey,
          passphrase: _authMethod == AuthMethod.privateKey
              ? _passphraseCtrl.text
              : null,
          sshKeyId: effectiveSshKeyId,
          portForwardings: _forwardingRules,
          group: _group,
          iconName: _iconName,
          colorHex: _colorHex,
          fallbackHosts: _fallbackHosts,
          mainHostFirst: _mainHostFirst,
          jumpHostProfileId: _jumpHostProfileId,
        );
      } else {
        await notifier.updateProfile(
          widget.profile!,
          name: _effectiveName,
          host: _hostCtrl.text.trim(),
          port: port,
          username: _userCtrl.text.trim(),
          authMethod: _authMethod!,
          password: _authMethod == AuthMethod.password
              ? _passwordCtrl.text
              : null,
          privateKey: effectivePrivateKey,
          passphrase: _authMethod == AuthMethod.privateKey
              ? _passphraseCtrl.text
              : null,
          sshKeyId: effectiveSshKeyId,
          portForwardings: _forwardingRules,
          group: _group,
          iconName: _iconName,
          colorHex: _colorHex,
          fallbackHosts: _fallbackHosts,
          mainHostFirst: _mainHostFirst,
          jumpHostProfileId: _jumpHostProfileId,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      AppNotifications.error(
        context,
        Translations.of(context).profileForm.saveFailed(error: e.toString()),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _addFallbackHost(Translations t) {
    final entry = _fallbackHostInputCtrl.text.trim();
    if (entry.isEmpty) return;
    if (entry.contains(' ') || entry == _hostCtrl.text.trim()) {
      AppNotifications.error(context, t.profileForm.fallbackHostInvalid);
      return;
    }
    if (_fallbackHosts.contains(entry)) return;
    setState(() {
      _fallbackHosts.add(entry);
      _fallbackHostInputCtrl.clear();
    });
  }

  Future<void> _showRuleEditor(
    Translations t, {
    PortForwardingRule? existing,
  }) async {
    final rule = await showPortForwardingRuleSheet(
      context: context,
      title: existing == null
          ? t.portForwarding.addRule
          : t.portForwarding.editRule,
      existing: existing,
    );
    if (rule == null || !mounted) return;
    setState(() {
      // An edit keeps the rule's id, so it replaces in place instead of
      // landing at the end as a near-duplicate.
      final at = _forwardingRules.indexWhere((r) => r.id == rule.id);
      if (at >= 0) {
        _forwardingRules[at] = rule;
      } else {
        _forwardingRules.add(rule);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.profile == null;
    final t = Translations.of(context);
    return Scaffold(
      backgroundColor: context.colors.backgroundPrimary,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          isNew ? t.profileForm.newTitle : t.profileForm.editTitle,
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
                : TextButton(
                    onPressed: () {
                      if (_authMethod == AuthMethod.privateKey &&
                          _keySource == _KeySource.manual) {
                        _privateKeyContent = _privateKeyCtrl.text.trim();
                      }
                      _save();
                    },
                    child: Text(
                      t.common.save,
                      style: TextStyle(
                        color: context.colors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ContentGutter(
          builder: (context, gutter) => Form(
            key: _formKey,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                isNew ? 16 : 8,
                20,
                40,
              ).add(gutter),
              children: [
                SectionHeader(t.profileForm.avatar),
                const SizedBox(height: 10),
                _buildAvatarSection(),

                const SizedBox(height: 24),
                SectionHeader(t.groups.groupTitle),
                const SizedBox(height: 10),
                GroupPickerField(
                  group: _group,
                  onChanged: (g) => setState(() => _group = g),
                ),

                const SizedBox(height: 24),
                SectionHeader(t.profileForm.connection),
                const SizedBox(height: 10),
                AppFormField(
                  controller: _nameCtrl,
                  label: t.common.name,
                  hint: t.profileForm.nameHint,
                  icon: PhosphorIconsFill.tag,
                  action: TextInputAction.next,
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: AppFormField(
                        controller: _hostCtrl,
                        label: t.profileForm.host,
                        hint: t.profileForm.hostHint,
                        icon: PhosphorIconsFill.hardDrives,
                        action: TextInputAction.next,
                        keyboardType: TextInputType.url,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? t.common.required
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 92,
                      child: AppFormField(
                        controller: _portCtrl,
                        label: t.profileForm.port,
                        hint: t.profileForm.portHint,
                        action: TextInputAction.next,
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          return (n == null || n <= 0 || n > 65535)
                              ? t.common.invalid
                              : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AppFormField(
                  controller: _userCtrl,
                  label: t.profileForm.username,
                  hint: t.profileForm.usernameHint,
                  icon: PhosphorIconsFill.user,
                  action: TextInputAction.next,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? t.common.required
                      : null,
                ),

                const SizedBox(height: 24),
                SectionHeader(
                  t.profileForm.fallbackHosts,
                  hint: t.profileForm.fallbackHostsHint,
                ),
                const SizedBox(height: 10),
                _buildFallbackHostsSection(t),

                const SizedBox(height: 24),
                SectionHeader(
                  t.profileForm.jumpHost,
                  hint: t.profileForm.jumpHostHint,
                ),
                const SizedBox(height: 10),
                _buildJumpHostSection(t),

                const SizedBox(height: 24),
                SectionHeader(t.profileForm.authentication),
                const SizedBox(height: 10),
                _AuthMethodPicker(
                  selected: _authMethod,
                  onSelected: (method) {
                    setState(() {
                      _authMethod = method;
                      _authMissing = false;
                    });
                    if (method == AuthMethod.privateKey &&
                        _availableKeys.isEmpty &&
                        !_keysLoading) {
                      _loadKeys();
                    }
                  },
                ),
                if (_authMissing) ...[
                  const SizedBox(height: 8),
                  Text(
                    t.profileForm.chooseAuth,
                    style: context.colors.uiSmall.copyWith(
                      color: context.colors.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),

                if (_authMethod == AuthMethod.password)
                  AppFormField(
                    controller: _passwordCtrl,
                    label: t.profileForm.password,
                    icon: PhosphorIconsFill.lock,
                    obscure: _hidePassword,
                    action: TextInputAction.done,
                    validator: (v) =>
                        (v == null || v.isEmpty) ? t.common.required : null,
                    suffix: IconButton(
                      tooltip: _hidePassword
                          ? t.common.showPassword
                          : t.common.hidePassword,
                      icon: Icon(
                        _hidePassword
                            ? PhosphorIconsFill.eyeSlash
                            : PhosphorIconsFill.eye,
                        size: 20,
                        color: context.colors.textTertiary,
                      ),
                      onPressed: () =>
                          setState(() => _hidePassword = !_hidePassword),
                    ),
                  ),

                if (_authMethod == AuthMethod.privateKey) _buildKeySection(),
                const SizedBox(height: 16),
                _buildConnectionTest(t),

                const SizedBox(height: 24),
                _buildPortForwardingSection(t),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarSection() => AvatarPicker(
    iconName: _iconName,
    colorHex: _colorHex,
    onIconChanged: (id) => setState(() => _iconName = id),
    onColorChanged: (hex) => setState(() => _colorHex = hex),
  );

  Widget _buildFallbackHostsSection(Translations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_fallbackHosts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppEmptyHint(text: t.profileForm.fallbackHostsEmpty),
          )
        else
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: context.colors.surfaceCard,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: context.colors.surfaceBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _fallbackHosts.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    decoration: i == 0
                        ? null
                        : BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: context.colors.surfaceBorder,
                              ),
                            ),
                          ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: context.colors.textTertiary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _fallbackHosts[i],
                            style: context.colors.monoStyle.copyWith(
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            PhosphorIconsRegular.arrowUp,
                            size: 16,
                          ),
                          onPressed: i == 0
                              ? null
                              : () => setState(() {
                                  final entry = _fallbackHosts.removeAt(i);
                                  _fallbackHosts.insert(i - 1, entry);
                                }),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            PhosphorIconsRegular.arrowDown,
                            size: 16,
                          ),
                          onPressed: i == _fallbackHosts.length - 1
                              ? null
                              : () => setState(() {
                                  final entry = _fallbackHosts.removeAt(i);
                                  _fallbackHosts.insert(i + 1, entry);
                                }),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            PhosphorIconsRegular.x,
                            size: 16,
                            color: context.colors.error,
                          ),
                          onPressed: () =>
                              setState(() => _fallbackHosts.removeAt(i)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        AppInlineAddField(
          controller: _fallbackHostInputCtrl,
          hint: t.profileForm.fallbackHostHint,
          addTooltip: t.profileForm.addFallbackHost,
          keyboardType: TextInputType.url,
          onSubmit: () => _addFallbackHost(t),
        ),
        if (_fallbackHosts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SettingsSwitchRow(
              label: t.profileForm.mainHostFirst,
              subtitle: t.profileForm.mainHostFirstHint,
              value: _mainHostFirst,
              onChanged: (value) => setState(() => _mainHostFirst = value),
            ),
          ),
      ],
    );
  }

  /// The profiles this one may be pointed at.
  ///
  /// Itself is out, and so is anything whose own chain already comes back
  /// here - picking one of those would build a loop that could only be
  /// discovered by trying to connect through it.
  List<SshProfile> _jumpHostCandidates(List<SshProfile> profiles) {
    final editing = widget.profile?.id;
    final byId = {for (final profile in profiles) profile.id: profile};

    bool reachesEditedProfile(SshProfile candidate) {
      var hop = candidate;
      // Bounded by the profile count: a chain longer than that has already
      // revisited something.
      for (var step = 0; step < profiles.length; step++) {
        if (hop.id == editing) return true;
        final next = hop.jumpHostProfileId;
        if (next == null) return false;
        final resolved = byId[next];
        if (resolved == null) return false;
        hop = resolved;
      }
      return true;
    }

    final valid = [
      for (final profile in profiles)
        if (profile.id != editing && !reachesEditedProfile(profile)) profile,
    ];
    final sameGroup = valid.where((p) => isSameGroup(p.group, _group));
    final otherGroup = valid.where((p) => !isSameGroup(p.group, _group));
    return [...sameGroup, ...otherGroup];
  }

  Widget _buildJumpHostSection(Translations t) {
    final profiles = ref.watch(profilesProvider);
    final candidates = _jumpHostCandidates(profiles);
    final anonymize = ref.watch(anonymizeProvider);
    // A profile whose jump host was deleted keeps pointing at it, and the
    // connection says so rather than quietly going direct. The picker shows
    // the same thing instead of looking unset.
    final selected = profiles
        .where((profile) => profile.id == _jumpHostProfileId)
        .firstOrNull;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: context.colors.surfaceBorder),
      ),
      // The tile paints its ink on the nearest Material, which without this
      // is the one behind the card - so the splash lands under the fill and
      // never shows.
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          leading: Icon(
            PhosphorIconsRegular.arrowBendRightUp,
            color: context.colors.textSecondary,
          ),
          title: Text(
            selected == null
                ? t.profileForm.jumpHostNone
                : anonymize
                ? IdentityAnonymizer.name(selected.id)
                : selected.name,
          ),
          subtitle: selected == null
              ? null
              : Text(
                  jumpHostAddress(selected, anonymize: anonymize),
                  style: context.colors.monoSmall,
                ),
          trailing: Icon(
            PhosphorIconsFill.caretRight,
            color: context.colors.textTertiary,
          ),
          onTap: () => _pickJumpHost(t, candidates),
        ),
      ),
    );
  }

  Future<void> _pickJumpHost(
    Translations t,
    List<SshProfile> candidates,
  ) async {
    if (candidates.isEmpty) {
      AppNotifications.info(context, t.profileForm.jumpHostNoCandidates);
      return;
    }
    final picked = await showAppSheet<String>(
      context: context,
      handle: false,
      builder: (ctx) => JumpHostSheetContent(
        candidates: candidates,
        group: _group,
        selectedId: _jumpHostProfileId,
        onPick: (id) => Navigator.of(ctx).pop(id ?? ''),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _jumpHostProfileId = picked.isEmpty ? null : picked);
  }

  Widget _buildConnectionTest(Translations t) {
    final testing = _testCancel != null;
    final result = _testResult;
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _testConnection,
          icon: testing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(PhosphorIconsRegular.plugsConnected, size: 18),
          label: Text(
            testing
                ? t.profileForm.testingConnection
                : t.profileForm.testConnection,
          ),
        ),
        if (result != null) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                result.ok
                    ? PhosphorIconsRegular.checkCircle
                    : PhosphorIconsFill.warningCircle,
                size: 18,
                color: result.ok ? colors.success : colors.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.message,
                  style: colors.uiSmall.copyWith(
                    color: result.ok ? colors.success : colors.error,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildKeySection() {
    if (_keysLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final t = Translations.of(context);

    final sameGroupKeys = _availableKeys
        .where((key) => isSameGroup(key.group, _group))
        .toList();
    final otherGroupKeys = _availableKeys
        .where((key) => !isSameGroup(key.group, _group))
        .toList();
    final hasKeySplit = sameGroupKeys.isNotEmpty && otherGroupKeys.isNotEmpty;

    Widget buildKeyCard(SshKey key) {
      final selected =
          _selectedKeyId == key.id && _keySource == _KeySource.keyManager;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _KeyCard(
          sshKey: key,
          selected: selected,
          onTap: () => setState(() {
            _selectedKeyId = key.id;
            _keySource = _KeySource.keyManager;
            _showManualEntry = false;
          }),
          onCopyPubkey: () async {
            await Clipboard.setData(ClipboardData(text: key.publicKeyOpenSSH));
            if (mounted) {
              AppNotifications.success(context, t.common.keyCopied);
            }
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_availableKeys.isNotEmpty) ...[
          for (final key in sameGroupKeys) buildKeyCard(key),
          if (hasKeySplit)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 10),
              child: SectionHeader(t.groups.otherGroups),
            ),
          for (final key in otherGroupKeys) buildKeyCard(key),
          const SizedBox(height: 4),
        ],

        AddRowCard(label: t.profileForm.createKey, onTap: _createKey),
        const SizedBox(height: 8),

        GestureDetector(
          onTap: () => setState(() {
            _showManualEntry = !_showManualEntry;
            if (_showManualEntry) _keySource = _KeySource.manual;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _showManualEntry
                  ? context.colors.primary.withValues(alpha: 0.08)
                  : context.colors.surfaceCard,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(
                color: _showManualEntry
                    ? context.colors.primary.withValues(alpha: 0.4)
                    : context.colors.surfaceBorder,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  PhosphorIconsFill.pencilSimple,
                  size: 18,
                  color: _showManualEntry
                      ? context.colors.primary
                      : context.colors.textTertiary,
                ),
                const SizedBox(width: 10),
                Text(
                  t.profileForm.enterKeyManually,
                  style: TextStyle(
                    color: _showManualEntry
                        ? context.colors.primary
                        : context.colors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Icon(
                  _showManualEntry
                      ? PhosphorIconsFill.caretUp
                      : PhosphorIconsFill.caretDown,
                  size: 20,
                  color: context.colors.textTertiary,
                ),
              ],
            ),
          ),
        ),

        if (_showManualEntry) ...[
          const SizedBox(height: 8),
          AppFormField(
            controller: _privateKeyCtrl,
            minLines: 5,
            maxLines: 10,
            monospace: true,
            hint: t.keys.privateKeyHint,
            action: TextInputAction.newline,
            validator: (v) {
              if (_authMethod == AuthMethod.privateKey &&
                  _keySource == _KeySource.manual &&
                  (v == null || v.trim().isEmpty)) {
                return t.profileForm.privateKeyRequired;
              }
              return null;
            },
            onChanged: (v) => _privateKeyContent = v.trim(),
          ),
        ],

        const SizedBox(height: 12),
        AppFormField(
          controller: _passphraseCtrl,
          label: t.profileForm.passphrase,
          hint: t.common.optional,
          icon: PhosphorIconsFill.shield,
          obscure: _hidePassphrase,
          action: TextInputAction.done,
          suffix: IconButton(
            tooltip: _hidePassphrase
                ? t.common.showPassword
                : t.common.hidePassword,
            icon: Icon(
              _hidePassphrase
                  ? PhosphorIconsFill.eyeSlash
                  : PhosphorIconsFill.eye,
              size: 20,
              color: context.colors.textTertiary,
            ),
            onPressed: () => setState(() => _hidePassphrase = !_hidePassphrase),
          ),
        ),
      ],
    );
  }

  Widget _buildPortForwardingSection(Translations t) {
    final rules = List<PortForwardingRule>.from(_forwardingRules)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(t.portForwarding.title),
        const SizedBox(height: 10),
        if (rules.isEmpty)
          EmptyStateHint(
            icon: PhosphorIconsRegular.arrowsLeftRight,
            text: t.portForwarding.noRulesYet,
            padding: const EdgeInsets.only(bottom: 12),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard.fields(
              children: [
                for (final (i, rule) in rules.indexed) ...[
                  if (i > 0) const AppDivider(),
                  PortForwardingRuleTile(
                    rule: rule,
                    onTap: () => _showRuleEditor(t, existing: rule),
                    onDelete: () =>
                        setState(() => _forwardingRules.remove(rule)),
                  ),
                ],
              ],
            ),
          ),
        AddRowCard(
          label: t.portForwarding.addRule,
          onTap: () => _showRuleEditor(t),
        ),
      ],
    );
  }
}

/// Group of three tappable auth-method rows sharing one border. None of the
/// rows paint their own full-bleed background, so no clipping is needed to
/// keep a divider or a selected row's fill from overhanging the corners.
class _AuthMethodPicker extends StatelessWidget {
  const _AuthMethodPicker({required this.selected, required this.onSelected});

  final AuthMethod? selected;
  final ValueChanged<AuthMethod> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    const rows = [
      (AuthMethod.none, PhosphorIconsFill.lockOpen),
      (AuthMethod.password, PhosphorIconsFill.lock),
      (AuthMethod.privateKey, PhosphorIconsFill.key),
    ];
    String labelFor(AuthMethod method) => switch (method) {
      AuthMethod.none => t.profileForm.noAuth,
      AuthMethod.password => t.profileForm.password,
      AuthMethod.privateKey => t.profileForm.sshKey,
    };
    String hintFor(AuthMethod method) => switch (method) {
      AuthMethod.none => t.profileForm.noAuthHint,
      AuthMethod.password => t.profileForm.passwordHint,
      AuthMethod.privateKey => t.profileForm.sshKeyHint,
    };
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: context.colors.surfaceBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              decoration: i == 0
                  ? null
                  : BoxDecoration(
                      border: Border(
                        top: BorderSide(color: context.colors.surfaceBorder),
                      ),
                    ),
              child: _AuthMethodRow(
                icon: rows[i].$2,
                label: labelFor(rows[i].$1),
                hint: hintFor(rows[i].$1),
                selected: selected == rows[i].$1,
                onTap: () => onSelected(rows[i].$1),
              ),
            ),
        ],
      ),
    );
  }
}

class _KeyCard extends StatelessWidget {
  const _KeyCard({
    required this.sshKey,
    required this.selected,
    required this.onTap,
    required this.onCopyPubkey,
  });

  final SshKey sshKey;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onCopyPubkey;

  String get _typeLabel => sshKey.keyType.label;

  Color _typeColor(BuildContext context) => switch (sshKey.keyType) {
    SshKeyType.ed25519 => context.colors.success,
    SshKeyType.rsa2048 || SshKeyType.rsa4096 => context.colors.primary,
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppTheme.interactiveDuration,
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: selected
              ? context.colors.primary.withValues(alpha: 0.08)
              : context.colors.surfaceCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(
            color: selected
                ? context.colors.primary.withValues(alpha: 0.5)
                : context.colors.surfaceBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: AppTheme.interactiveDuration,
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? context.colors.primary
                    : context.colors.primary.invisible,
                border: Border.all(
                  color: selected
                      ? context.colors.primary
                      : context.colors.surfaceBorder,
                  width: 2,
                ),
              ),
              child: selected
                  ? Icon(
                      PhosphorIconsRegular.check,
                      size: 12,
                      color: context.colors.onPrimary,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Text(
                    sshKey.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? context.colors.textPrimary
                          : context.colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _typeColor(context).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                    ),
                    child: Text(
                      _typeLabel,
                      style: TextStyle(
                        color: _typeColor(context),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(PhosphorIconsFill.copy, size: 16),
              color: context.colors.textTertiary,
              tooltip: Translations.of(context).keys.copyPublicKey,
              onPressed: onCopyPubkey,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthMethodRow extends StatelessWidget {
  const _AuthMethodRow({
    required this.icon,
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected
                  ? context.colors.primary
                  : context.colors.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected
                          ? context.colors.textPrimary
                          : context.colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hint,
                    style: context.colors.uiSmall.copyWith(
                      color: context.colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: AppTheme.interactiveDuration,
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? context.colors.primary
                    : context.colors.primary.invisible,
                border: Border.all(
                  color: selected
                      ? context.colors.primary
                      : context.colors.surfaceBorder,
                  width: 2,
                ),
              ),
              child: selected
                  ? Icon(
                      PhosphorIconsRegular.check,
                      size: 10,
                      color: context.colors.onPrimary,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
