///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'strings.g.dart';

// Path: <root>
typedef TranslationsEn = Translations; // ignore: unused_element
class Translations with BaseTranslations<AppLocale, Translations> {
	/// Returns the current translations of the given [context].
	///
	/// Usage:
	/// final t = Translations.of(context);
	static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <en>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	dynamic operator[](String key) => _meta.getTranslation(key);

	late final Translations _root = this; // ignore: unused_field

	Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

	// Translations
	late final Translations$nav$en nav = Translations$nav$en.internal(_root);
	late final Translations$errorReports$en errorReports = Translations$errorReports$en.internal(_root);
	late final Translations$common$en common = Translations$common$en.internal(_root);
	late final Translations$lock$en lock = Translations$lock$en.internal(_root);
	late final Translations$profiles$en profiles = Translations$profiles$en.internal(_root);
	late final Translations$profileForm$en profileForm = Translations$profileForm$en.internal(_root);
	late final Translations$keys$en keys = Translations$keys$en.internal(_root);
	late final Translations$terminal$en terminal = Translations$terminal$en.internal(_root);
	late final Translations$sftp$en sftp = Translations$sftp$en.internal(_root);
	late final Translations$editor$en editor = Translations$editor$en.internal(_root);
	late final Translations$settings$en settings = Translations$settings$en.internal(_root);
	late final Translations$exportScreen$en exportScreen = Translations$exportScreen$en.internal(_root);
	late final Translations$connection$en connection = Translations$connection$en.internal(_root);
	late final Translations$connectionLog$en connectionLog = Translations$connectionLog$en.internal(_root);
	late final Translations$groups$en groups = Translations$groups$en.internal(_root);
	late final Translations$portForwarding$en portForwarding = Translations$portForwarding$en.internal(_root);
	late final Translations$notifications$en notifications = Translations$notifications$en.internal(_root);
	late final Translations$linkPreview$en linkPreview = Translations$linkPreview$en.internal(_root);
	late final Translations$session$en session = Translations$session$en.internal(_root);
	late final Translations$snippets$en snippets = Translations$snippets$en.internal(_root);
	late final Translations$toolbar$en toolbar = Translations$toolbar$en.internal(_root);
	late final Translations$actionDock$en actionDock = Translations$actionDock$en.internal(_root);
	late final Translations$share$en share = Translations$share$en.internal(_root);
	late final Translations$terminalSearch$en terminalSearch = Translations$terminalSearch$en.internal(_root);
	late final Translations$commandPalette$en commandPalette = Translations$commandPalette$en.internal(_root);
	late final Translations$background$en background = Translations$background$en.internal(_root);
	late final Translations$analyticsConsent$en analyticsConsent = Translations$analyticsConsent$en.internal(_root);
	late final Translations$onboarding$en onboarding = Translations$onboarding$en.internal(_root);
	late final Translations$serverGuide$en serverGuide = Translations$serverGuide$en.internal(_root);
	late final Translations$whatsNew$en whatsNew = Translations$whatsNew$en.internal(_root);
	late final Translations$hostKey$en hostKey = Translations$hostKey$en.internal(_root);
	late final Translations$keyboardInteractive$en keyboardInteractive = Translations$keyboardInteractive$en.internal(_root);
	late final Translations$manual$en manual = Translations$manual$en.internal(_root);
	late final Translations$tagMigration$en tagMigration = Translations$tagMigration$en.internal(_root);
	late final Translations$selection$en selection = Translations$selection$en.internal(_root);
	late final Translations$globalSearch$en globalSearch = Translations$globalSearch$en.internal(_root);
}

// Path: nav
class Translations$nav$en {
	Translations$nav$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Home'
	String get home => 'Home';

	/// en: 'Snippets'
	String get snippets => 'Snippets';

	/// en: 'Keys'
	String get keys => 'Keys';

	/// en: 'Settings'
	String get settings => 'Settings';

	/// en: 'Collapse sidebar'
	String get collapseSidebar => 'Collapse sidebar';

	/// en: 'Expand sidebar'
	String get expandSidebar => 'Expand sidebar';
}

// Path: errorReports
class Translations$errorReports$en {
	Translations$errorReports$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'No errors recorded'
	String get empty => 'No errors recorded';

	/// en: 'When Termphin runs into an error, it shows up here so you can send it to us.'
	String get emptySubtitle => 'When Termphin runs into an error, it shows up here so you can send it to us.';

	/// en: 'Kept on this device only. Nothing is sent until you send it.'
	String get privacy => 'Kept on this device only. Nothing is sent until you send it.';

	/// en: 'Send by email'
	String get sendEmail => 'Send by email';

	/// en: 'Share'
	String get share => 'Share';

	/// en: 'Clear'
	String get clear => 'Clear';

	/// en: 'Clear error reports?'
	String get clearTitle => 'Clear error reports?';

	/// en: 'Every recorded error is removed from this device.'
	String get clearMessage => 'Every recorded error is removed from this device.';

	/// en: '{count} times'
	String repeated({required Object count}) => '${count} times';

	/// en: 'Termphin error report'
	String get emailSubject => 'Termphin error report';
}

// Path: common
class Translations$common$en {
	Translations$common$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Add'
	String get add => 'Add';

	/// en: 'Cancel'
	String get cancel => 'Cancel';

	/// en: 'Save'
	String get save => 'Save';

	/// en: 'Delete'
	String get delete => 'Delete';

	/// en: 'Rename'
	String get rename => 'Rename';

	/// en: 'Import'
	String get import => 'Import';

	/// en: 'Export'
	String get export => 'Export';

	/// en: 'Done'
	String get done => 'Done';

	/// en: 'Copy'
	String get copy => 'Copy';

	/// en: 'Discard'
	String get discard => 'Discard';

	/// en: 'Required'
	String get required => 'Required';

	/// en: 'Invalid'
	String get invalid => 'Invalid';

	/// en: 'optional'
	String get optional => 'optional';

	/// en: 'Reset'
	String get reset => 'Reset';

	/// en: 'Edit'
	String get edit => 'Edit';

	/// en: 'Retry'
	String get retry => 'Retry';

	/// en: 'Back'
	String get back => 'Back';

	/// en: 'Refresh'
	String get refresh => 'Refresh';

	/// en: 'Show password'
	String get showPassword => 'Show password';

	/// en: 'Hide password'
	String get hidePassword => 'Hide password';

	/// en: 'Close'
	String get close => 'Close';

	/// en: 'Disable'
	String get disable => 'Disable';

	/// en: 'Name'
	String get name => 'Name';

	/// en: 'Public key copied.'
	String get keyCopied => 'Public key copied.';

	/// en: 'Copied.'
	String get copied => 'Copied.';

	/// en: 'Generate'
	String get generate => 'Generate';

	/// en: 'Paste'
	String get paste => 'Paste';

	/// en: 'Share'
	String get share => 'Share';

	/// en: 'Allow'
	String get allow => 'Allow';

	/// en: 'Allowed'
	String get allowed => 'Allowed';

	/// en: 'just now'
	String get justNow => 'just now';

	/// en: '{minutes}m ago'
	String minutesAgo({required Object minutes}) => '${minutes}m ago';

	/// en: '{hours}h ago'
	String hoursAgo({required Object hours}) => '${hours}h ago';

	/// en: '{days}d ago'
	String daysAgo({required Object days}) => '${days}d ago';

	/// en: 'Duplicate'
	String get duplicate => 'Duplicate';

	/// en: 'Select all'
	String get selectAll => 'Select all';

	/// en: 'Clear selection'
	String get clearSelection => 'Clear selection';

	/// en: 'Clear all'
	String get clearAll => 'Clear all';

	/// en: 'Clear search'
	String get clearSearch => 'Clear search';

	/// en: 'Undo'
	String get undo => 'Undo';
}

// Path: lock
class Translations$lock$en {
	Translations$lock$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Incorrect PIN'
	String get incorrectPin => 'Incorrect PIN';

	/// en: 'Set PIN'
	String get setPin => 'Set PIN';

	/// en: 'Confirm PIN'
	String get confirmPin => 'Confirm PIN';

	/// en: 'PINs don't match - try again'
	String get pinMismatch => 'PINs don\'t match - try again';

	/// en: 'Authenticate to open Termphin'
	String get authenticateReason => 'Authenticate to open Termphin';

	/// en: 'Enter your PIN'
	String get enterPin => 'Enter your PIN';

	/// en: 'Checking…'
	String get checking => 'Checking…';

	/// en: '(one) {Incorrect PIN. One more try before a short wait.} (other) {Incorrect PIN. {count} more tries before a short wait.}'
	String incorrectPinTriesLeft({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Incorrect PIN. One more try before a short wait.',
		other: 'Incorrect PIN. ${count} more tries before a short wait.',
	);

	/// en: 'Too many attempts. Try again in {time}.'
	String tooManyAttempts({required Object time}) => 'Too many attempts. Try again in ${time}.';

	/// en: '4 to 6 digits'
	String get pinLengthHint => '4 to 6 digits';

	/// en: 'Next'
	String get pinNext => 'Next';
}

// Path: profiles
class Translations$profiles$en {
	Translations$profiles$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Termphin'
	String get title => 'Termphin';

	/// en: 'Machines'
	String get machines => 'Machines';

	/// en: 'Keys'
	String get keys => 'Keys';

	/// en: 'Your machines'
	String get machinesHeading => 'Your machines';

	/// en: 'Connect to your SSH servers'
	String get machinesSubtitle => 'Connect to your SSH servers';

	/// en: 'No machines yet Tap + to add one'
	String get emptyMachines => 'No machines yet\nTap + to add one';

	/// en: 'Delete profile?'
	String get deleteTitle => 'Delete profile?';

	/// en: 'Are you sure you want to delete "{name}"?'
	String deleteConfirm({required Object name}) => 'Are you sure you want to delete "${name}"?';

	/// en: 'Profile deleted.'
	String get deleted => 'Profile deleted.';

	/// en: 'Machine Profile'
	String get addMachine => 'Machine Profile';

	/// en: 'Public key "{name}" copied.'
	String keyCopied({required Object name}) => 'Public key "${name}" copied.';

	/// en: 'Search machines…'
	String get searchHint => 'Search machines…';

	/// en: 'Recent'
	String get sortRecent => 'Recent';

	/// en: 'A-z'
	String get sortAZ => 'A-z';

	/// en: 'Z-a'
	String get sortZA => 'Z-a';

	/// en: 'No results for "{query}"'
	String noResults({required Object query}) => 'No results for "${query}"';

	/// en: 'Connections'
	String get connections => 'Connections';

	/// en: 'Close all'
	String get closeAll => 'Close all';

	/// en: 'All machines'
	String get allMachines => 'All machines';

	/// en: 'Add machine'
	String get addMachineButton => 'Add machine';

	/// en: 'Add your first machine'
	String get addFirstMachine => 'Add your first machine';

	/// en: 'No machines yet'
	String get emptyMachinesTitle => 'No machines yet';

	/// en: 'Add a server you can SSH into to start your first session.'
	String get emptyMachinesSubtitle => 'Add a server you can SSH into to start your first session.';

	/// en: 'More actions'
	String get moreActions => 'More actions';

	/// en: 'Sort machines'
	String get sortMachines => 'Sort machines';

	/// en: 'Return to {name}'
	String returnToSession({required Object name}) => 'Return to ${name}';

	/// en: 'No server yet?'
	String get noServerYet => 'No server yet?';

	/// en: 'user@host'
	String get quickAddHint => 'user@host';

	/// en: 'Add this machine'
	String get quickAddTooltip => 'Add this machine';

	/// en: 'Type it the way you would after ssh, like user@server.'
	String get quickAddInvalid => 'Type it the way you would after ssh, like user@server.';
}

// Path: profileForm
class Translations$profileForm$en {
	Translations$profileForm$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'New Machine'
	String get newTitle => 'New Machine';

	/// en: 'Edit Machine'
	String get editTitle => 'Edit Machine';

	/// en: 'Connection'
	String get connection => 'Connection';

	/// en: 'e.g. Production'
	String get nameHint => 'e.g. Production';

	/// en: 'Host'
	String get host => 'Host';

	/// en: '192.168.1.1'
	String get hostHint => '192.168.1.1';

	/// en: 'Port'
	String get port => 'Port';

	/// en: '22'
	String get portHint => '22';

	/// en: 'Username'
	String get username => 'Username';

	/// en: 'root'
	String get usernameHint => 'root';

	/// en: 'Authentication'
	String get authentication => 'Authentication';

	/// en: 'No authentication'
	String get noAuth => 'No authentication';

	/// en: 'Password'
	String get password => 'Password';

	/// en: 'SSH Key'
	String get sshKey => 'SSH Key';

	/// en: 'Passphrase'
	String get passphrase => 'Passphrase';

	/// en: 'Enter key manually'
	String get enterKeyManually => 'Enter key manually';

	/// en: 'Private key is required.'
	String get privateKeyRequired => 'Private key is required.';

	/// en: 'Could not save: {error}'
	String saveFailed({required Object error}) => 'Could not save: ${error}';

	/// en: 'Avatar'
	String get avatar => 'Avatar';

	/// en: 'Fallback addresses'
	String get fallbackHosts => 'Fallback addresses';

	/// en: 'Tried in order if the host above doesn't answer, e.g. a Tailscale IP or a LAN address.'
	String get fallbackHostsHint => 'Tried in order if the host above doesn\'t answer, e.g. a Tailscale IP or a LAN address.';

	/// en: 'host or host:port'
	String get fallbackHostHint => 'host or host:port';

	/// en: 'Add address'
	String get addFallbackHost => 'Add address';

	/// en: 'No fallback addresses yet.'
	String get fallbackHostsEmpty => 'No fallback addresses yet.';

	/// en: 'Always try the main address first'
	String get mainHostFirst => 'Always try the main address first';

	/// en: 'Turn off to start with the address that worked last time.'
	String get mainHostFirstHint => 'Turn off to start with the address that worked last time.';

	/// en: 'Enter a host, optionally as host:port.'
	String get fallbackHostInvalid => 'Enter a host, optionally as host:port.';

	/// en: 'Jump host'
	String get jumpHost => 'Jump host';

	/// en: 'Connect through another profile first, the way OpenSSH's ProxyJump does. The session with this host stays end-to-end encrypted - the jump host moves the bytes, it cannot read them.'
	String get jumpHostHint => 'Connect through another profile first, the way OpenSSH\'s ProxyJump does. The session with this host stays end-to-end encrypted - the jump host moves the bytes, it cannot read them.';

	/// en: 'Connect directly'
	String get jumpHostNone => 'Connect directly';

	/// en: 'No other profile can be used here yet.'
	String get jumpHostNoCandidates => 'No other profile can be used here yet.';

	/// en: 'Filled in from the link. Check it before saving.'
	String get linkPrefilled => 'Filled in from the link. Check it before saving.';

	/// en: 'That link is not a valid ssh:// address.'
	String get linkInvalid => 'That link is not a valid ssh:// address.';

	/// en: 'Test connection'
	String get testConnection => 'Test connection';

	/// en: 'Connecting… tap to stop'
	String get testingConnection => 'Connecting… tap to stop';

	/// en: 'It works - the server let you in.'
	String get testSucceeded => 'It works - the server let you in.';

	/// en: 'The server lets anyone in with just the username. Rare - mostly test machines.'
	String get noAuthHint => 'The server lets anyone in with just the username. Rare - mostly test machines.';

	/// en: 'The account's password on the server. The simplest way to start; it is stored encrypted on this device.'
	String get passwordHint => 'The account\'s password on the server. The simplest way to start; it is stored encrypted on this device.';

	/// en: 'A key pair: the private half stays on this device, the public half goes into ~/.ssh/authorized_keys on the server. Safer than a password, and nothing to type.'
	String get sshKeyHint => 'A key pair: the private half stays on this device, the public half goes into ~/.ssh/authorized_keys on the server. Safer than a password, and nothing to type.';

	/// en: 'Create a new key'
	String get createKey => 'Create a new key';

	/// en: 'Choose how to sign in to this machine.'
	String get chooseAuth => 'Choose how to sign in to this machine.';
}

// Path: keys
class Translations$keys$en {
	Translations$keys$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'SSH Keys'
	String get title => 'SSH Keys';

	/// en: 'Generate, import and manage your SSH keys'
	String get subtitle => 'Generate, import and manage your SSH keys';

	/// en: 'All keys'
	String get allKeys => 'All keys';

	/// en: 'No SSH keys yet'
	String get emptyTitle => 'No SSH keys yet';

	/// en: 'Tap + to generate or import a key.'
	String get emptySubtitle => 'Tap + to generate or import a key.';

	/// en: 'Delete key?'
	String get deleteTitle => 'Delete key?';

	/// en: 'Delete "{name}"? This cannot be undone.'
	String deleteConfirm({required Object name}) => 'Delete "${name}"? This cannot be undone.';

	/// en: 'Rename key'
	String get renameTitle => 'Rename key';

	/// en: 'Copy public key'
	String get copyPublicKey => 'Copy public key';

	/// en: 'Key created'
	String get keyCreatedTitle => 'Key created';

	/// en: 'Add this public key to your server's ~/.ssh/authorized_keys:'
	String get keyCreatedInstructions => 'Add this public key to your server\'s ~/.ssh/authorized_keys:';

	/// en: 'Import key (PEM)'
	String get importTitle => 'Import key (PEM)';

	/// en: 'Key name'
	String get keyNameLabel => 'Key name';

	/// en: 'e.g. my-laptop'
	String get keyNameHint => 'e.g. my-laptop';

	/// en: 'Private key (PEM)'
	String get privateKeyLabel => 'Private key (PEM)';

	/// en: '-----BEGIN OPENSSH PRIVATE KEY----- ...'
	String get privateKeyHint => '-----BEGIN OPENSSH PRIVATE KEY-----\n...';

	/// en: 'Key passphrase'
	String get keyPassphraseLabel => 'Key passphrase';

	/// en: 'This key is encrypted'
	String get keyPassphraseHint => 'This key is encrypted';

	/// en: 'Used only to read the key. Termphin does not store it - enter it again on the profile that uses this key.'
	String get keyPassphraseNote => 'Used only to read the key. Termphin does not store it - enter it again on the profile that uses this key.';

	/// en: 'Choose key file'
	String get selectPrivateKeyFile => 'Choose key file';

	/// en: 'Selected: {name}'
	String selectedFile({required Object name}) => 'Selected: ${name}';

	/// en: 'The key file is too large.'
	String get keyFileTooLarge => 'The key file is too large.';

	/// en: 'The selected file is empty.'
	String get keyFileEmpty => 'The selected file is empty.';

	/// en: 'Could not read key file: {error}'
	String keyFileReadFailed({required Object error}) => 'Could not read key file: ${error}';

	/// en: 'Key "{name}" imported.'
	String importSuccess({required Object name}) => 'Key "${name}" imported.';

	/// en: 'Add SSH Key'
	String get addKey => 'Add SSH Key';

	/// en: 'Generate Ed25519'
	String get generateEd25519 => 'Generate Ed25519';

	/// en: 'Fast, secure modern key'
	String get generateEd25519Subtitle => 'Fast, secure modern key';

	/// en: 'Generate RSA 2048'
	String get generateRsa2048 => 'Generate RSA 2048';

	/// en: 'Compatible with most servers'
	String get generateRsa2048Subtitle => 'Compatible with most servers';

	/// en: 'Generate RSA 4096'
	String get generateRsa4096 => 'Generate RSA 4096';

	/// en: 'Stronger RSA (takes longer)'
	String get generateRsa4096Subtitle => 'Stronger RSA (takes longer)';

	/// en: 'Import private key'
	String get importPem => 'Import private key';

	/// en: 'Choose a key file or paste PEM'
	String get importPemSubtitle => 'Choose a key file or paste PEM';

	/// en: 'Key "{name}" deleted.'
	String deleted({required Object name}) => 'Key "${name}" deleted.';

	/// en: 'Import failed: {error}'
	String importFailed({required Object error}) => 'Import failed: ${error}';

	/// en: 'That passphrase does not open this key.'
	String get importWrongPassphrase => 'That passphrase does not open this key.';

	/// en: 'This key is encrypted. Enter its passphrase to import it.'
	String get importPassphraseRequired => 'This key is encrypted. Enter its passphrase to import it.';

	/// en: 'Failed to generate key: {error}'
	String generateFailed({required Object error}) => 'Failed to generate key: ${error}';

	/// en: 'New key'
	String get newKeyTitle => 'New key';

	/// en: 'Edit key'
	String get editKeyTitle => 'Edit key';

	/// en: 'Key type'
	String get keyTypeLabel => 'Key type';

	/// en: 'Ed25519'
	String get keyTypeEd25519 => 'Ed25519';

	/// en: 'RSA 2048'
	String get keyTypeRsa2048 => 'RSA 2048';

	/// en: 'RSA 4096'
	String get keyTypeRsa4096 => 'RSA 4096';

	/// en: 'Import existing key'
	String get keyTypeImport => 'Import existing key';

	/// en: 'Fast and modern. The right choice unless a server demands otherwise.'
	String get keyTypeEd25519Subtitle => 'Fast and modern. The right choice unless a server demands otherwise.';

	/// en: 'Widely compatible with older servers.'
	String get keyTypeRsa2048Subtitle => 'Widely compatible with older servers.';

	/// en: 'Stronger RSA, slower to generate.'
	String get keyTypeRsa4096Subtitle => 'Stronger RSA, slower to generate.';

	/// en: 'Paste a private key or pick a file.'
	String get keyTypeImportSubtitle => 'Paste a private key or pick a file.';

	/// en: 'Generating key...'
	String get generating => 'Generating key...';

	/// en: 'Key is in use'
	String get inUseTitle => 'Key is in use';

	/// en: '(one) {1 machine uses this key and will stop connecting:} (other) {{count} machines use this key and will stop connecting:}'
	String inUseBody({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '1 machine uses this key and will stop connecting:',
		other: '${count} machines use this key and will stop connecting:',
	);

	/// en: 'Delete anyway'
	String get deleteAnyway => 'Delete anyway';
}

// Path: terminal
class Translations$terminal$en {
	Translations$terminal$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Select device to connect'
	String get selectDevice => 'Select device to connect';

	/// en: 'Hide suggestion'
	String get suggestionDismiss => 'Hide suggestion';

	/// en: 'New session'
	String get newSession => 'New session';

	/// en: 'Terminal'
	String get switchToTerminal => 'Terminal';

	/// en: 'SFTP Browser'
	String get switchToSftp => 'SFTP Browser';

	/// en: 'Terminal'
	String get modeTerminal => 'Terminal';

	/// en: 'Files'
	String get modeFiles => 'Files';

	/// en: 'Disconnect'
	String get disconnect => 'Disconnect';

	/// en: 'Failed to connect.'
	String get connectFailed => 'Failed to connect.';

	/// en: 'Paste'
	String get paste => 'Paste';

	/// en: 'Open in Browser'
	String get openInBrowser => 'Open in Browser';

	/// en: 'Scroll to bottom'
	String get scrollToBottom => 'Scroll to bottom';

	/// en: 'Search devices…'
	String get searchDevices => 'Search devices…';

	/// en: 'No devices found'
	String get noDevices => 'No devices found';

	/// en: 'Remote host copied to clipboard.'
	String get remoteCopied => 'Remote host copied to clipboard.';

	/// en: 'Split screen with…'
	String get splitWith => 'Split screen with…';

	/// en: 'Split screen with'
	String get splitWithTitle => 'Split screen with';

	/// en: 'New connection'
	String get splitNewConnection => 'New connection';

	/// en: 'Move out of split'
	String get unsplit => 'Move out of split';

	/// en: 'Resize split'
	String get splitDivider => 'Resize split';
}

// Path: sftp
class Translations$sftp$en {
	Translations$sftp$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Delete?'
	String get deleteTitle => 'Delete?';

	/// en: 'Are you sure you want to delete {filename}?'
	String deleteConfirm({required Object filename}) => 'Are you sure you want to delete ${filename}?';

	/// en: 'Delete {count} items?'
	String deleteSelectedTitle({required Object count}) => 'Delete ${count} items?';

	/// en: 'Are you sure you want to delete {count} selected items?'
	String deleteSelectedConfirm({required Object count}) => 'Are you sure you want to delete ${count} selected items?';

	/// en: 'Open in Editor'
	String get openInEditor => 'Open in Editor';

	/// en: 'Download'
	String get download => 'Download';

	/// en: '{filename} saved'
	String downloadComplete({required Object filename}) => '${filename} saved';

	/// en: 'Delete failed: {error}'
	String deleteFailed({required Object error}) => 'Delete failed: ${error}';

	/// en: 'Rename failed: {error}'
	String renameFailed({required Object error}) => 'Rename failed: ${error}';

	/// en: '{done} of {total}'
	String transferBytes({required Object done, required Object total}) => '${done} of ${total}';

	/// en: '{rate}/s'
	String transferRate({required Object rate}) => '${rate}/s';

	/// en: '{current} of {total}'
	String transferItemCount({required Object current, required Object total}) => '${current} of ${total}';

	/// en: 'Scanning folder… {count} items'
	String transferScanning({required Object count}) => 'Scanning folder… ${count} items';

	/// en: 'Download cancelled'
	String get downloadCancelled => 'Download cancelled';

	/// en: 'Upload cancelled'
	String get uploadCancelled => 'Upload cancelled';

	/// en: 'Preview'
	String get preview => 'Preview';

	/// en: 'File too large to preview ({size}). Use Download instead.'
	String fileTooLarge({required Object size}) => 'File too large to preview (${size}).\nUse Download instead.';

	/// en: 'File too large to open in the editor ({size}). Use Download instead.'
	String fileTooLargeToEdit({required Object size}) => 'File too large to open in the editor (${size}).\nUse Download instead.';

	/// en: 'Could not decode image'
	String get imageDecodeError => 'Could not decode image';

	/// en: 'Upload'
	String get uploadAction => 'Upload';

	/// en: 'New folder'
	String get newFolder => 'New folder';

	/// en: 'New file'
	String get newFile => 'New file';

	/// en: 'New folder'
	String get newFolderTitle => 'New folder';

	/// en: 'New file'
	String get newFileTitle => 'New file';

	/// en: 'Folder name'
	String get folderNameHint => 'Folder name';

	/// en: 'File name'
	String get fileNameHint => 'File name';

	/// en: 'Create'
	String get create => 'Create';

	/// en: 'Create failed: {error}'
	String createFailed({required Object error}) => 'Create failed: ${error}';

	/// en: 'Replace file?'
	String get overwriteTitle => 'Replace file?';

	/// en: '{filename} already exists on the server. Replace it?'
	String overwriteConfirm({required Object filename}) => '${filename} already exists on the server. Replace it?';

	/// en: 'Replace'
	String get overwrite => 'Replace';

	/// en: 'Sort by'
	String get sortBy => 'Sort by';

	/// en: 'Name'
	String get sortName => 'Name';

	/// en: 'Size'
	String get sortSize => 'Size';

	/// en: 'Date modified'
	String get sortModified => 'Date modified';

	/// en: 'Reverse order'
	String get sortDirection => 'Reverse order';

	/// en: '{count} selected'
	String selectedCount({required Object count}) => '${count} selected';

	/// en: 'Select all'
	String get selectAll => 'Select all';

	/// en: 'Copy path'
	String get copyPath => 'Copy path';

	/// en: 'Path copied'
	String get pathCopied => 'Path copied';

	/// en: 'Modified {date}'
	String modified({required Object date}) => 'Modified ${date}';

	/// en: 'Cancel'
	String get cancel => 'Cancel';

	/// en: 'Cancelled'
	String get cancelled => 'Cancelled';

	/// en: '{current} of {total}'
	String imageCounter({required Object current, required Object total}) => '${current} of ${total}';

	late final Translations$sftp$errors$en errors = Translations$sftp$errors$en.internal(_root);

	/// en: 'Checking file…'
	String get checkingFile => 'Checking file…';

	/// en: 'Open as text anyway'
	String get openAsText => 'Open as text anyway';

	/// en: 'Could not delete {count} items. {error}'
	String deleteFailedCount({required Object count, required Object error}) => 'Could not delete ${count} items. ${error}';

	/// en: 'Saved: {name}'
	String savedToDownloads({required Object name}) => 'Saved: ${name}';

	/// en: 'Saved {count} files to {folder}'
	String savedFilesToDownloads({required Object count, required Object folder}) => 'Saved ${count} files to ${folder}';

	/// en: 'Open'
	String get openDownload => 'Open';

	/// en: 'Share'
	String get shareDownload => 'Share';

	/// en: 'No app on this device can open it.'
	String get noAppToOpen => 'No app on this device can open it.';

	/// en: 'Could not share it.'
	String get couldNotShare => 'Could not share it.';

	/// en: 'Downloads'
	String get downloadsFolder => 'Downloads';

	/// en: 'Copy to…'
	String get copyTo => 'Copy to…';

	/// en: 'Move to…'
	String get moveTo => 'Move to…';

	/// en: 'Copy {count} items to'
	String copyItemsTo({required Object count}) => 'Copy ${count} items to';

	/// en: 'Move {count} items to'
	String moveItemsTo({required Object count}) => 'Move ${count} items to';

	/// en: 'Copy {name} to'
	String copyNameTo({required Object name}) => 'Copy ${name} to';

	/// en: 'Move {name} to'
	String moveNameTo({required Object name}) => 'Move ${name} to';

	/// en: 'Copy here'
	String get copyHere => 'Copy here';

	/// en: 'Move here'
	String get moveHere => 'Move here';

	/// en: 'Recent'
	String get recentFolders => 'Recent';

	/// en: 'Edit path'
	String get editPath => 'Edit path';

	/// en: 'More'
	String get moreActions => 'More';

	/// en: 'Already there'
	String get conflictTitle => 'Already there';

	/// en: '{name} already exists in {folder}.'
	String conflictOne({required Object name, required Object folder}) => '${name} already exists in ${folder}.';

	/// en: '{count} of {total} items already exist in {folder}.'
	String conflictMany({required Object count, required Object total, required Object folder}) => '${count} of ${total} items already exist in ${folder}.';

	/// en: 'Skip'
	String get conflictSkip => 'Skip';

	/// en: 'Replace'
	String get conflictReplace => 'Replace';

	/// en: 'Keep both'
	String get conflictKeepBoth => 'Keep both';

	/// en: 'Copied {name}'
	String copiedName({required Object name}) => 'Copied ${name}';

	/// en: 'Moved {name}'
	String movedName({required Object name}) => 'Moved ${name}';

	/// en: 'Copied {count} items'
	String copiedCount({required Object count}) => 'Copied ${count} items';

	/// en: 'Moved {count} items'
	String movedCount({required Object count}) => 'Moved ${count} items';

	/// en: '{count} skipped'
	String skippedCount({required Object count}) => '${count} skipped';

	/// en: 'Nothing changed - every item was skipped'
	String get nothingTransferred => 'Nothing changed - every item was skipped';

	/// en: 'Could not copy {count} items. {error}'
	String copyFailedCount({required Object count, required Object error}) => 'Could not copy ${count} items. ${error}';

	/// en: 'Could not move {count} items. {error}'
	String moveFailedCount({required Object count, required Object error}) => 'Could not move ${count} items. ${error}';

	late final Translations$sftp$queue$en queue = Translations$sftp$queue$en.internal(_root);
}

// Path: editor
class Translations$editor$en {
	Translations$editor$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Unsaved changes'
	String get unsavedTitle => 'Unsaved changes';

	/// en: 'Discard changes?'
	String get discardConfirm => 'Discard changes?';

	/// en: 'File saved successfully'
	String get savedSuccess => 'File saved successfully';

	/// en: 'Failed to save: {error}'
	String saveFailed({required Object error}) => 'Failed to save: ${error}';

	/// en: 'Lines {start}-{end} of {total}'
	String lines({required Object start, required Object end, required Object total}) => 'Lines ${start}-${end} of ${total}';

	/// en: '· scroll to load more'
	String get scrollToLoadMore => '· scroll to load more';

	/// en: 'Error: {error}'
	String error({required Object error}) => 'Error: ${error}';

	/// en: 'Toggle word wrap'
	String get toggleWordWrap => 'Toggle word wrap';

	/// en: 'File changed on server'
	String get modifiedRemotelyTitle => 'File changed on server';

	/// en: 'This file was modified on the server since it was opened. Saving now will overwrite those changes.'
	String get modifiedRemotelyBody => 'This file was modified on the server since it was opened. Saving now will overwrite those changes.';

	/// en: 'Save anyway'
	String get saveAnyway => 'Save anyway';

	/// en: 'Find'
	String get find => 'Find';

	/// en: 'Find'
	String get findHint => 'Find';

	/// en: 'Replace'
	String get replace => 'Replace';

	/// en: 'Replace with'
	String get replaceHint => 'Replace with';

	/// en: 'All'
	String get replaceAll => 'All';

	/// en: '{current}/{total}'
	String matchCount({required Object current, required Object total}) => '${current}/${total}';

	/// en: 'None'
	String get noMatches => 'None';

	/// en: 'Match case'
	String get matchCase => 'Match case';

	/// en: 'Regular expression'
	String get regex => 'Regular expression';

	/// en: 'Previous match'
	String get previousMatch => 'Previous match';

	/// en: 'Next match'
	String get nextMatch => 'Next match';

	/// en: 'Close'
	String get closeFind => 'Close';
}

// Path: settings
class Translations$settings$en {
	Translations$settings$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Settings'
	String get title => 'Settings';

	/// en: 'Configure app behavior and terminal preferences'
	String get subtitle => 'Configure app behavior and terminal preferences';

	/// en: 'Appearance'
	String get appearance => 'Appearance';

	/// en: 'Theme'
	String get themeMode => 'Theme';

	/// en: 'Follow device'
	String get themeModeSystem => 'Follow device';

	/// en: 'Light'
	String get themeModeLight => 'Light';

	/// en: 'Dark'
	String get themeModeDark => 'Dark';

	/// en: 'Terminal'
	String get terminal => 'Terminal';

	/// en: 'Terminal appearance'
	String get terminalAppearance => 'Terminal appearance';

	/// en: 'Color scheme, font, cursor - with a live preview'
	String get terminalNavSubtitle => 'Color scheme, font, cursor - with a live preview';

	/// en: 'Style'
	String get terminalStyle => 'Style';

	/// en: 'Behavior'
	String get terminalBehavior => 'Behavior';

	/// en: 'Color scheme'
	String get colorScheme => 'Color scheme';

	/// en: 'Font'
	String get font => 'Font';

	/// en: 'Font size'
	String get fontSize => 'Font size';

	/// en: 'Line height'
	String get lineHeight => 'Line height';

	/// en: 'Side padding'
	String get sidePadding => 'Side padding';

	/// en: 'Cursor'
	String get cursor => 'Cursor';

	/// en: 'Block'
	String get cursorBlock => 'Block';

	/// en: 'Underline'
	String get cursorUnderline => 'Underline';

	/// en: 'Bar'
	String get cursorBar => 'Bar';

	/// en: 'Blink'
	String get cursorBlink => 'Blink';

	/// en: 'Predictive echo'
	String get predictiveEcho => 'Predictive echo';

	/// en: 'Show typing instantly on slow connections'
	String get predictiveEchoSubtitle => 'Show typing instantly on slow connections';

	/// en: 'Fast upload'
	String get fastUpload => 'Fast upload';

	/// en: 'Uploads land in the server's temporary directory'
	String get fastUploadNavSubtitleTmp => 'Uploads land in the server\'s temporary directory';

	/// en: 'Uploads land in the shell's current directory'
	String get fastUploadNavSubtitleCurrentDir => 'Uploads land in the shell\'s current directory';

	/// en: 'Asks where to put each upload'
	String get fastUploadNavSubtitleAsk => 'Asks where to put each upload';

	/// en: 'Upload a file into the open session'
	String get fastUploadSubtitle => 'Upload a file into the open session';

	/// en: 'New'
	String get newBadge => 'New';

	/// en: 'Upload destination'
	String get uploadDestination => 'Upload destination';

	/// en: 'Temporary directory (scratch folder)'
	String get uploadDestinationTmp => 'Temporary directory (scratch folder)';

	/// en: 'Shell's current directory'
	String get uploadDestinationCurrentDir => 'Shell\'s current directory';

	/// en: 'Ask every time'
	String get uploadDestinationAsk => 'Ask every time';

	/// en: 'Where the shell is, with the agent'
	String get uploadDestinationCurrentDirHint => 'Where the shell is, with the agent';

	/// en: 'Pick a folder for every upload'
	String get uploadDestinationAskHint => 'Pick a folder for every upload';

	/// en: 'Timestamped names, nothing overwritten'
	String get uploadDestinationTmpHint => 'Timestamped names, nothing overwritten';

	/// en: 'Paste the path straight away'
	String get uploadAutoPaste => 'Paste the path straight away';

	/// en: 'Type the path at the cursor when done'
	String get uploadAutoPasteSubtitle => 'Type the path at the cursor when done';

	/// en: 'Connection'
	String get connection => 'Connection';

	/// en: 'Termphin agent'
	String get remoteAgentToggle => 'Termphin agent';

	/// en: 'Keeps sessions alive across disconnects'
	String get remoteAgentToggleSubtitle => 'Keeps sessions alive across disconnects';

	/// en: 'How the Termphin agent works'
	String get remoteAgentHowItWorks => 'How the Termphin agent works';

	/// en: 'What it runs on your server, and why it is safe'
	String get remoteAgentHowItWorksSubtitle => 'What it runs on your server, and why it is safe';

	/// en: 'Sessions in the background'
	String get backgroundSuspended => 'Sessions in the background';

	/// en: 'The agent keeps your shell running'
	String get backgroundSuspendedSubtitle => 'The agent keeps your shell running';

	/// en: 'Termphin agent'
	String get agentSheetTitle => 'Termphin agent';

	/// en: 'A small helper Termphin uploads to your server over SSH. It keeps your shell running there, so closing the app or losing signal doesn't end what you were doing.'
	String get agentSheetIntro => 'A small helper Termphin uploads to your server over SSH. It keeps your shell running there, so closing the app or losing signal doesn\'t end what you were doing.';

	/// en: 'Runs on Linux and macOS (x86_64 and arm64) and on Windows (x86_64).'
	String get agentSheetPointPlatforms => 'Runs on Linux and macOS (x86_64 and arm64) and on Windows (x86_64).';

	/// en: 'Keeps each session's shell alive. After a short drop you get only what you missed; after a longer one, the screen as it is now.'
	String get agentSheetPointKeepsAlive => 'Keeps each session\'s shell alive. After a short drop you get only what you missed; after a longer one, the screen as it is now.';

	/// en: 'Opens no network port. The app reaches it through your SSH connection, over a socket only your user can open.'
	String get agentSheetPointNoNetwork => 'Opens no network port. The app reaches it through your SSH connection, over a socket only your user can open.';

	/// en: 'Runs as your user. No root, nothing installed system-wide, no service or cron entry.'
	String get agentSheetPointNoRoot => 'Runs as your user. No root, nothing installed system-wide, no service or cron entry.';

	/// en: 'Everything lives in ~/.cache/termphin/sessions (%LOCALAPPDATA%\\termphin\\sessions on Windows). Ending a session deletes its folder.'
	String get agentSheetPointFiles => 'Everything lives in ~/.cache/termphin/sessions (%LOCALAPPDATA%\\termphin\\sessions on Windows). Ending a session deletes its folder.';

	/// en: 'Recent output is kept in memory for picking up where you left off. A copy of the scrollback is saved in the session's folder, so it survives a server reboot.'
	String get agentSheetPointMemory => 'Recent output is kept in memory for picking up where you left off. A copy of the scrollback is saved in the session\'s folder, so it survives a server reboot.';

	/// en: 'Termphin checks the helper's SHA-256 checksum before uploading it, and checks the copy already on your server the same way.'
	String get agentSheetPointVerified => 'Termphin checks the helper\'s SHA-256 checksum before uploading it, and checks the copy already on your server the same way.';

	/// en: 'It's open source: about 5,000 lines of Rust and one library for reading the screen (vt100), so you can read exactly what it does.'
	String get agentSheetOpenSource => 'It\'s open source: about 5,000 lines of Rust and one library for reading the screen (vt100), so you can read exactly what it does.';

	/// en: 'View the source on GitHub'
	String get agentSheetRepoButton => 'View the source on GitHub';

	/// en: 'Could not open the link.'
	String get agentSheetLinkFailed => 'Could not open the link.';

	/// en: 'Security'
	String get security => 'Security';

	/// en: 'PIN lock'
	String get pinLock => 'PIN lock';

	/// en: 'Enabled - asked on launch and when you come back'
	String get pinLockEnabled => 'Enabled - asked on launch and when you come back';

	/// en: 'Ask again'
	String get lockAfter => 'Ask again';

	/// en: 'Right away'
	String get lockAfterImmediately => 'Right away';

	/// en: 'After 30 seconds'
	String get lockAfter30s => 'After 30 seconds';

	/// en: 'After 1 minute'
	String get lockAfter1m => 'After 1 minute';

	/// en: 'After 5 minutes'
	String get lockAfter5m => 'After 5 minutes';

	/// en: 'Disabled'
	String get pinLockDisabled => 'Disabled';

	/// en: 'Biometric unlock'
	String get biometricUnlock => 'Biometric unlock';

	/// en: 'Use fingerprint or face as alternative'
	String get biometricSubtitle => 'Use fingerprint or face as alternative';

	/// en: 'Not available on this device'
	String get biometricUnavailable => 'Not available on this device';

	/// en: 'Enable PIN lock first'
	String get enablePinFirst => 'Enable PIN lock first';

	/// en: 'Change PIN'
	String get changePin => 'Change PIN';

	/// en: 'Data & Backup'
	String get dataBackup => 'Data & Backup';

	/// en: 'Backup profiles, SSH keys and settings to JSON'
	String get exportImportSubtitle => 'Backup profiles, SSH keys and settings to JSON';

	/// en: 'Rename, recolour and reorder your groups'
	String get groupsSubtitle => 'Rename, recolour and reorder your groups';

	/// en: 'Organization'
	String get organization => 'Organization';

	/// en: 'Analytics'
	String get analytics => 'Analytics';

	/// en: 'Share usage analytics'
	String get analyticsToggle => 'Share usage analytics';

	/// en: 'Anonymous usage and crash reports'
	String get analyticsToggleSubtitle => 'Anonymous usage and crash reports';

	/// en: 'On-screen controls'
	String get terminalControls => 'On-screen controls';

	/// en: 'Key toolbar'
	String get keyToolbar => 'Key toolbar';

	/// en: 'Esc, Tab, Ctrl, arrows above the keyboard'
	String get keyToolbarSubtitle => 'Esc, Tab, Ctrl, arrows above the keyboard';

	/// en: 'Toolbar layout'
	String get toolbarLayout => 'Toolbar layout';

	/// en: 'Action dock'
	String get actionDock => 'Action dock';

	/// en: 'Floating button over the terminal with quick actions'
	String get actionDockSwitchSubtitle => 'Floating button over the terminal with quick actions';

	/// en: 'Tabs at the bottom'
	String get tabsAtBottom => 'Tabs at the bottom';

	/// en: 'Above the key toolbar, within reach of your thumb'
	String get tabsAtBottomSubtitle => 'Above the key toolbar, within reach of your thumb';

	/// en: 'Autocomplete'
	String get commandSuggestions => 'Autocomplete';

	/// en: 'Suggests commands and paths as you type'
	String get commandSuggestionsSubtitle => 'Suggests commands and paths as you type';

	/// en: 'How it works'
	String get howItWorks => 'How it works';

	/// en: 'Dock actions'
	String get actionDockLayout => 'Dock actions';

	/// en: 'Drag to move, − to hide, + to restore'
	String get actionDockSubtitle => 'Drag to move, − to hide, + to restore';

	/// en: 'Dock'
	String get actionDockPreview => 'Dock';

	/// en: 'Hidden'
	String get actionDockHiddenLabel => 'Hidden';

	/// en: 'Every tile is hidden. Tap + below or drag one here.'
	String get actionDockAllHidden => 'Every tile is hidden. Tap + below or drag one here.';

	/// en: 'Nothing hidden - drag a tile here to hide it.'
	String get actionDockNoneHidden => 'Nothing hidden - drag a tile here to hide it.';

	/// en: 'Hide {name}'
	String actionDockHide({required Object name}) => 'Hide ${name}';

	/// en: 'Add {name} to the dock'
	String actionDockShow({required Object name}) => 'Add ${name} to the dock';

	/// en: 'Reset dock'
	String get actionDockReset => 'Reset dock';

	/// en: 'Reset the dock?'
	String get actionDockResetTitle => 'Reset the dock?';

	/// en: 'The default actions come back, in the default order.'
	String get actionDockResetMessage => 'The default actions come back, in the default order.';

	/// en: 'Dock reset'
	String get actionDockResetDone => 'Dock reset';

	/// en: 'Disable lock?'
	String get disableLockTitle => 'Disable lock?';

	/// en: 'PIN and biometric lock will be removed.'
	String get disableLockContent => 'PIN and biometric lock will be removed.';

	/// en: 'Layout {number}'
	String layoutLabel({required Object number}) => 'Layout ${number}';

	/// en: 'Grid'
	String get toolbarGrid => 'Grid';

	/// en: 'Columns'
	String get toolbarColumns => 'Columns';

	/// en: 'Rows'
	String get toolbarRows => 'Rows';

	/// en: 'Pages'
	String get toolbarPages => 'Pages';

	/// en: 'Button height'
	String get toolbarButtonHeight => 'Button height';

	/// en: 'New key'
	String get toolbarAddCustom => 'New key';

	/// en: 'Remove key'
	String get toolbarSlotRemove => 'Remove key';

	/// en: 'No free slot - remove a key first.'
	String get toolbarNoFreeSlot => 'No free slot - remove a key first.';

	/// en: 'Tap a slot, then a key to fill it'
	String get toolbarTapToPlace => 'Tap a slot, then a key to fill it';

	/// en: 'Tap a key below to fill this slot'
	String get toolbarSlotSelected => 'Tap a key below to fill this slot';

	/// en: 'Smaller grid'
	String get toolbarResizeTitle => 'Smaller grid';

	/// en: '{count} keys do not fit the new grid and will be taken off the toolbar.'
	String toolbarResizeMessage({required Object count}) => '${count} keys do not fit the new grid and will be taken off the toolbar.';

	/// en: 'Shrink anyway'
	String get toolbarResizeConfirm => 'Shrink anyway';

	/// en: 'Anonymize'
	String get anonymize => 'Anonymize';

	/// en: 'Hide hosts and usernames for screenshots'
	String get anonymizeSubtitle => 'Hide hosts and usernames for screenshots';

	/// en: 'Download folder'
	String get downloadFolder => 'Download folder';

	/// en: 'System Downloads folder'
	String get downloadFolderDefault => 'System Downloads folder';

	/// en: 'Use system Downloads'
	String get downloadFolderReset => 'Use system Downloads';

	/// en: 'That folder is no longer available. Pick it again or fall back to Downloads.'
	String get downloadFolderUnavailable => 'That folder is no longer available. Pick it again or fall back to Downloads.';

	/// en: 'Privacy'
	String get privacy => 'Privacy';

	/// en: 'SFTP'
	String get sftp => 'SFTP';

	/// en: 'Text editor'
	String get textEditor => 'Text editor';

	/// en: '{font}, {size} pt'
	String textEditorSubtitle({required Object font, required Object size}) => '${font}, ${size} pt';

	/// en: 'Style'
	String get editorStyle => 'Style';

	/// en: 'Pinch in the editor to resize text'
	String get editorPinchHint => 'Pinch in the editor to resize text';

	/// en: 'Line numbers'
	String get editorLineNumbers => 'Line numbers';

	/// en: 'Wrap long lines'
	String get editorWordWrap => 'Wrap long lines';

	/// en: 'Off, a long line scrolls sideways instead.'
	String get editorWordWrapSubtitle => 'Off, a long line scrolls sideways instead.';

	/// en: 'Unrestricted battery use'
	String get batteryUnrestricted => 'Unrestricted battery use';

	/// en: 'Keeps sessions connected in the background'
	String get batteryUnrestrictedSubtitle => 'Keeps sessions connected in the background';

	/// en: 'Notifications'
	String get notificationsPermission => 'Notifications';

	/// en: 'For background sessions and downloads'
	String get notificationsPermissionSubtitle => 'For background sessions and downloads';

	/// en: 'Local network access'
	String get localNetworkPermission => 'Local network access';

	/// en: 'Needed to reach machines on your network'
	String get localNetworkPermissionSubtitle => 'Needed to reach machines on your network';

	/// en: 'Feedback'
	String get feedback => 'Feedback';

	/// en: 'Send feedback'
	String get sendFeedback => 'Send feedback';

	/// en: 'Ideas, requests, anything you'd like to see'
	String get sendFeedbackSubtitle => 'Ideas, requests, anything you\'d like to see';

	/// en: 'Report a bug'
	String get reportBug => 'Report a bug';

	/// en: 'Something broke? Tell us what happened'
	String get reportBugSubtitle => 'Something broke? Tell us what happened';

	/// en: 'Issue tracker'
	String get issueTracker => 'Issue tracker';

	/// en: 'Open bugs and ideas, out in the open on GitHub'
	String get issueTrackerSubtitle => 'Open bugs and ideas, out in the open on GitHub';

	/// en: 'Open source'
	String get openSource => 'Open source';

	/// en: 'Star on GitHub'
	String get starOnGitHub => 'Star on GitHub';

	/// en: 'Helps others find Termphin'
	String get starOnGitHubSubtitle => 'Helps others find Termphin';

	/// en: 'Contribute'
	String get contribute => 'Contribute';

	/// en: 'Fix a bug or build a feature, here is where to start'
	String get contributeSubtitle => 'Fix a bug or build a feature, here is where to start';

	/// en: 'License'
	String get sourceLicense => 'License';

	/// en: 'GPL-3.0: read the code, build it, change it'
	String get sourceLicenseSubtitle => 'GPL-3.0: read the code, build it, change it';

	/// en: 'Manual'
	String get manual => 'Manual';

	/// en: 'How to use Termphin, from first connection onwards'
	String get manualSubtitle => 'How to use Termphin, from first connection onwards';

	/// en: 'Error reports'
	String get errorReports => 'Error reports';

	/// en: 'Errors Termphin ran into, to send with a bug report'
	String get errorReportsSubtitle => 'Errors Termphin ran into, to send with a bug report';

	/// en: 'Could not open your mail app.'
	String get feedbackEmailFailed => 'Could not open your mail app.';

	/// en: 'About'
	String get about => 'About';

	/// en: 'SSH client'
	String get aboutTagline => 'SSH client';

	/// en: 'Version {version}'
	String aboutVersion({required Object version}) => 'Version ${version}';

	/// en: 'Release notes'
	String get releaseNotes => 'Release notes';

	/// en: 'What's changed across every version'
	String get releaseNotesSubtitle => 'What\'s changed across every version';

	/// en: 'Rate Termphin'
	String get rateApp => 'Rate Termphin';

	/// en: 'Leave a review on Google Play'
	String get rateAppSubtitle => 'Leave a review on Google Play';

	/// en: 'Leave a review on the App Store'
	String get rateAppSubtitleIos => 'Leave a review on the App Store';

	/// en: 'Could not open Google Play.'
	String get rateAppFailed => 'Could not open Google Play.';

	/// en: 'Could not open the App Store.'
	String get rateAppFailedIos => 'Could not open the App Store.';

	/// en: 'Files app (On My iPhone / Termphin)'
	String get downloadFolderIos => 'Files app (On My iPhone / Termphin)';

	/// en: 'Open source licenses'
	String get licenses => 'Open source licenses';

	/// en: 'The packages Termphin is built on, and their terms'
	String get licensesSubtitle => 'The packages Termphin is built on, and their terms';

	/// en: 'Privacy policy'
	String get privacyPolicy => 'Privacy policy';

	/// en: 'What is collected, and what never leaves this device'
	String get privacyPolicySubtitle => 'What is collected, and what never leaves this device';

	/// en: 'Terms of service'
	String get terms => 'Terms of service';

	/// en: 'The terms you agree to by using Termphin'
	String get termsSubtitle => 'The terms you agree to by using Termphin';

	/// en: 'Could not open your browser.'
	String get legalLinkFailed => 'Could not open your browser.';

	/// en: 'Known hosts'
	String get knownHosts => 'Known hosts';

	/// en: 'Host keys this device trusts'
	String get knownHostsSubtitle => 'Host keys this device trusts';

	/// en: 'No host keys pinned'
	String get knownHostsEmpty => 'No host keys pinned';

	/// en: 'A server's key is pinned here the first time you accept it while connecting.'
	String get knownHostsEmptyBody => 'A server\'s key is pinned here the first time you accept it while connecting.';

	/// en: 'Pinned {date}'
	String knownHostsAddedAt({required Object date}) => 'Pinned ${date}';

	/// en: 'Forget'
	String get knownHostsForget => 'Forget';

	/// en: 'Forget this host key?'
	String get knownHostsForgetTitle => 'Forget this host key?';

	/// en: 'The next connection to {host} will ask you to accept its key again.'
	String knownHostsForgetBody({required Object host}) => 'The next connection to ${host} will ask you to accept its key again.';

	/// en: 'Host key forgotten.'
	String get knownHostsForgotten => 'Host key forgotten.';

	/// en: 'Toolbar layouts'
	String get toolbarProfiles => 'Toolbar layouts';

	/// en: 'Switch between key layouts'
	String get toolbarProfilesSubtitle => 'Switch between key layouts';

	/// en: 'Default'
	String get toolbarProfileDefault => 'Default';

	/// en: 'In use'
	String get toolbarProfileActive => 'In use';

	/// en: 'New layout'
	String get toolbarProfileNew => 'New layout';

	/// en: 'Layout {number}'
	String toolbarProfileNewName({required Object number}) => 'Layout ${number}';

	/// en: 'Rename layout'
	String get toolbarProfileRenameTitle => 'Rename layout';

	/// en: 'Layout name'
	String get toolbarProfileNameLabel => 'Layout name';

	/// en: 'Delete this layout?'
	String get toolbarProfileDeleteTitle => 'Delete this layout?';

	/// en: '“{name}” and the keys arranged in it are gone.'
	String toolbarProfileDeleteConfirm({required Object name}) => '“${name}” and the keys arranged in it are gone.';

	/// en: 'This is the only layout left - the toolbar needs one.'
	String get toolbarProfileDeleteLast => 'This is the only layout left - the toolbar needs one.';

	/// en: '{count} keys · {columns}x{rows}, {pages} page(s)'
	String toolbarProfileSummary({required Object count, required Object columns, required Object rows, required Object pages}) => '${count} keys · ${columns}x${rows}, ${pages} page(s)';

	/// en: 'Grid size'
	String get toolbarGridSize => 'Grid size';

	/// en: 'Reset layout'
	String get toolbarReset => 'Reset layout';

	/// en: 'Reset this layout?'
	String get toolbarResetTitle => 'Reset this layout?';

	/// en: 'Every slot goes back to the default arrangement.'
	String get toolbarResetMessage => 'Every slot goes back to the default arrangement.';

	/// en: 'Layout reset'
	String get toolbarResetDone => 'Layout reset';

	/// en: '“{name}” removed'
	String toolbarKeyRemoved({required Object name}) => '“${name}” removed';

	/// en: 'Empty slot'
	String get toolbarEmptySlot => 'Empty slot';

	/// en: 'Page {number} of {total}'
	String toolbarPageOf({required Object number, required Object total}) => 'Page ${number} of ${total}';

	/// en: 'Tap another slot to move it'
	String get toolbarKeyHeld => 'Tap another slot to move it';

	/// en: 'Tab width'
	String get editorTabWidth => 'Tab width';

	/// en: 'Show hidden files'
	String get sftpShowHidden => 'Show hidden files';

	/// en: 'Names that start with a dot, like .ssh and .bashrc.'
	String get sftpShowHiddenSubtitle => 'Names that start with a dot, like .ssh and .bashrc.';

	/// en: 'Follow the terminal'
	String get sftpFollowTerminal => 'Follow the terminal';

	/// en: 'Open in the shell's current folder'
	String get sftpFollowTerminalSubtitle => 'Open in the shell\'s current folder';
}

// Path: exportScreen
class Translations$exportScreen$en {
	Translations$exportScreen$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Export & Import'
	String get title => 'Export & Import';

	/// en: 'Choose what to include in the backup file.'
	String get exportInstructions => 'Choose what to include in the backup file.';

	/// en: 'Save backup'
	String get saveDialogTitle => 'Save backup';

	/// en: 'SSH profiles'
	String get includeSshProfiles => 'SSH profiles';

	/// en: 'Host, port, username, auth method'
	String get includeSshProfilesSubtitle => 'Host, port, username, auth method';

	/// en: 'Include passwords'
	String get includePasswords => 'Include passwords';

	/// en: 'Stored plaintext passwords in profiles'
	String get includePasswordsSubtitle => 'Stored plaintext passwords in profiles';

	/// en: 'Include inline private keys'
	String get includeInlineKeys => 'Include inline private keys';

	/// en: 'Private keys pasted directly into profiles'
	String get includeInlineKeysSubtitle => 'Private keys pasted directly into profiles';

	/// en: 'SSH keys'
	String get includeSshKeys => 'SSH keys';

	/// en: 'All keys from the key manager (incl. private)'
	String get includeSshKeysSubtitle => 'All keys from the key manager (incl. private)';

	/// en: 'Snippets'
	String get includeSnippets => 'Snippets';

	/// en: 'Saved commands, their tags and defaults'
	String get includeSnippetsSubtitle => 'Saved commands, their tags and defaults';

	/// en: 'Known hosts'
	String get includeKnownHosts => 'Known hosts';

	/// en: 'Pinned server host keys'
	String get includeKnownHostsSubtitle => 'Pinned server host keys';

	/// en: 'Terminal settings'
	String get includeTerminalSettings => 'Terminal settings';

	/// en: 'Color scheme, font size, cursor style'
	String get includeTerminalSettingsSubtitle => 'Color scheme, font size, cursor style';

	/// en: 'App preferences'
	String get includeAppPreferences => 'App preferences';

	/// en: 'Toolbar, action dock, theme and view options'
	String get includeAppPreferencesSubtitle => 'Toolbar, action dock, theme and view options';

	/// en: 'The backup will contain passwords and private keys. Protect it with a passphrase, or keep the file secure and delete it after use.'
	String get sensitiveWarning => 'The backup will contain passwords and private keys. Protect it with a passphrase, or keep the file secure and delete it after use.';

	/// en: 'Protect with a passphrase'
	String get encryptTitle => 'Protect with a passphrase';

	/// en: 'Encrypts the file. Without the passphrase it cannot be restored - there is no recovery.'
	String get encryptSubtitle => 'Encrypts the file. Without the passphrase it cannot be restored - there is no recovery.';

	/// en: 'Passphrase'
	String get passphraseLabel => 'Passphrase';

	/// en: 'Repeat passphrase'
	String get passphraseConfirmLabel => 'Repeat passphrase';

	/// en: 'At least 8 characters.'
	String get passphraseTooShort => 'At least 8 characters.';

	/// en: 'The two passphrases do not match.'
	String get passphraseMismatch => 'The two passphrases do not match.';

	/// en: 'Export backup'
	String get exportButton => 'Export backup';

	/// en: 'Exporting…'
	String get exporting => 'Exporting…';

	/// en: 'Backup saved'
	String get exportSuccess => 'Backup saved';

	/// en: 'Pick at least one section to export.'
	String get exportNothingSelected => 'Pick at least one section to export.';

	/// en: 'Export secrets unprotected?'
	String get confirmPlaintextTitle => 'Export secrets unprotected?';

	/// en: 'This file will hold passwords and private keys in plain text. Anything that can read the file can use them.'
	String get confirmPlaintextBody => 'This file will hold passwords and private keys in plain text. Anything that can read the file can use them.';

	/// en: 'Export anyway'
	String get confirmPlaintextContinue => 'Export anyway';

	/// en: 'Last backup {date}'
	String lastBackup({required Object date}) => 'Last backup ${date}';

	/// en: 'No backup taken from this device yet.'
	String get lastBackupNever => 'No backup taken from this device yet.';

	/// en: 'About to write: {summary}'
	String estimatedContents({required Object summary}) => 'About to write: ${summary}';

	/// en: 'Restore from a backup file. You choose what comes across and what happens to entries already on this device.'
	String get importInstructions => 'Restore from a backup file. You choose what comes across and what happens to entries already on this device.';

	/// en: 'Select backup file'
	String get selectFile => 'Select backup file';

	/// en: 'Reading file…'
	String get reading => 'Reading file…';

	/// en: 'Importing…'
	String get importing => 'Importing…';

	/// en: 'Import backup'
	String get importDialogTitle => 'Import backup';

	/// en: 'Exported {date}'
	String exportedAt({required Object date}) => 'Exported ${date}';

	/// en: 'What to import'
	String get whatToImport => 'What to import';

	/// en: 'SSH profiles'
	String get sectionProfiles => 'SSH profiles';

	/// en: 'SSH keys'
	String get sectionSshKeys => 'SSH keys';

	/// en: 'Snippets'
	String get sectionSnippets => 'Snippets';

	/// en: 'Known hosts'
	String get sectionKnownHosts => 'Known hosts';

	/// en: 'Choose individually'
	String get showItems => 'Choose individually';

	/// en: 'Hide entries'
	String get hideItems => 'Hide entries';

	/// en: 'All'
	String get selectAll => 'All';

	/// en: 'None'
	String get selectNone => 'None';

	/// en: 'Already here'
	String get alreadyHere => 'Already here';

	/// en: 'Entries already on this device'
	String get conflictsTitle => 'Entries already on this device';

	/// en: 'Keep mine'
	String get conflictsSkip => 'Keep mine';

	/// en: 'Leave the local entry alone and skip the one in the file.'
	String get conflictsSkipSubtitle => 'Leave the local entry alone and skip the one in the file.';

	/// en: 'Overwrite'
	String get conflictsReplace => 'Overwrite';

	/// en: 'Replace the local entry with the one in the file.'
	String get conflictsReplaceSubtitle => 'Replace the local entry with the one in the file.';

	/// en: '(one) {{n} entry in this file is already on the device.} (other) {{n} entries in this file are already on the device.}'
	String conflictSummary({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} entry in this file is already on the device.',
		other: '${n} entries in this file are already on the device.',
	);

	/// en: 'This backup carries passwords and private keys. They will be stored on this device.'
	String get importSecretsWarning => 'This backup carries passwords and private keys. They will be stored on this device.';

	/// en: '(one) {{n} profile} (other) {{n} profiles}'
	String profileCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} profile',
		other: '${n} profiles',
	);

	/// en: '(one) {{n} SSH key} (other) {{n} SSH keys}'
	String keyCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} SSH key',
		other: '${n} SSH keys',
	);

	/// en: '(one) {{n} snippet} (other) {{n} snippets}'
	String snippetCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} snippet',
		other: '${n} snippets',
	);

	/// en: '(one) {{n} known host} (other) {{n} known hosts}'
	String knownHostCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} known host',
		other: '${n} known hosts',
	);

	/// en: 'This backup is encrypted'
	String get passphrasePromptTitle => 'This backup is encrypted';

	/// en: 'Enter the passphrase it was exported with.'
	String get passphrasePromptBody => 'Enter the passphrase it was exported with.';

	/// en: 'Wrong passphrase.'
	String get passphraseWrong => 'Wrong passphrase.';

	/// en: 'Unlock'
	String get unlock => 'Unlock';

	/// en: 'That file is not a Termphin backup.'
	String get invalidFile => 'That file is not a Termphin backup.';

	/// en: 'This backup was written by a newer version of Termphin. Update the app and try again.'
	String get unsupportedVersion => 'This backup was written by a newer version of Termphin. Update the app and try again.';

	/// en: 'This backup holds nothing to import.'
	String get emptyBackup => 'This backup holds nothing to import.';

	/// en: 'Pick at least one thing to import.'
	String get importNothingSelected => 'Pick at least one thing to import.';

	/// en: 'Imported {added}, replaced {replaced}, skipped {skipped}'
	String importSuccess({required Object added, required Object replaced, required Object skipped}) => 'Imported ${added}, replaced ${replaced}, skipped ${skipped}';

	/// en: 'Nothing changed - everything in the file was already here.'
	String get importNothingChanged => 'Nothing changed - everything in the file was already here.';

	/// en: 'Profiles left without their SSH key: {names}'
	String importMissingKeys({required Object names}) => 'Profiles left without their SSH key: ${names}';

	/// en: 'Profiles left without their jump host: {names}'
	String importMissingJumpHosts({required Object names}) => 'Profiles left without their jump host: ${names}';

	/// en: 'Export'
	String get exportSection => 'Export';

	/// en: 'Import'
	String get importSection => 'Import';

	/// en: 'Write a backup file of your profiles, keys and settings.'
	String get hubExportSubtitle => 'Write a backup file of your profiles, keys and settings.';

	/// en: 'Restore from a backup file you exported earlier.'
	String get hubImportSubtitle => 'Restore from a backup file you exported earlier.';

	/// en: 'Choose another file'
	String get chooseAnotherFile => 'Choose another file';

	/// en: 'Pick a backup file to see what is in it.'
	String get noFileChosen => 'Pick a backup file to see what is in it.';

	/// en: 'Export failed: {error}'
	String exportFailed({required Object error}) => 'Export failed: ${error}';

	/// en: 'Import failed: {error}'
	String importFailed({required Object error}) => 'Import failed: ${error}';

	/// en: 'Failed: {error}'
	String failed({required Object error}) => 'Failed: ${error}';
}

// Path: connection
class Translations$connection$en {
	Translations$connection$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Connecting...'
	String get connecting => 'Connecting...';

	/// en: 'Allow local network'
	String get allowLocalNetwork => 'Allow local network';

	/// en: 'Open settings'
	String get openLocalNetworkSettings => 'Open settings';

	/// en: 'Connected'
	String get connected => 'Connected';

	/// en: 'Error'
	String get error => 'Error';

	/// en: 'Disconnected'
	String get disconnected => 'Disconnected';

	/// en: 'Reconnecting, attempt {attempt}…'
	String reconnecting({required Object attempt}) => 'Reconnecting, attempt ${attempt}…';

	/// en: 'Retrying in {seconds}s…'
	String reconnectingIn({required Object seconds}) => 'Retrying in ${seconds}s…';

	/// en: 'Waiting for a network…'
	String get waitingForNetwork => 'Waiting for a network…';

	/// en: 'Restoring history…'
	String get restoringHistory => 'Restoring history…';

	/// en: 'No connection log yet'
	String get logEmpty => 'No connection log yet';

	/// en: 'Connection log'
	String get viewLog => 'Connection log';

	late final Translations$connection$quality$en quality = Translations$connection$quality$en.internal(_root);
	late final Translations$connection$errors$en errors = Translations$connection$errors$en.internal(_root);
}

// Path: connectionLog
class Translations$connectionLog$en {
	Translations$connectionLog$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Trying {host}:{port}'
	String trying({required Object host, required Object port}) => 'Trying ${host}:${port}';

	/// en: 'Connecting through {name}'
	String connectingThrough({required Object name}) => 'Connecting through ${name}';

	/// en: 'Reached {name}'
	String reached({required Object name}) => 'Reached ${name}';

	/// en: 'Connecting to {host}:{port}'
	String connectingTo({required Object host, required Object port}) => 'Connecting to ${host}:${port}';

	/// en: 'Authentication successful'
	String get authSuccessful => 'Authentication successful';

	/// en: 'Checking Termphin agent'
	String get checkingAgent => 'Checking Termphin agent';

	/// en: 'Termphin agent unavailable: {error}'
	String agentUnavailable({required Object error}) => 'Termphin agent unavailable: ${error}';

	/// en: 'Opening terminal session'
	String get openingSession => 'Opening terminal session';

	/// en: 'Terminal session ready'
	String get sessionReady => 'Terminal session ready';

	/// en: 'Connection lost'
	String get connectionLost => 'Connection lost';
}

// Path: groups
class Translations$groups$en {
	Translations$groups$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Groups'
	String get title => 'Groups';

	/// en: 'Organize your machines, keys and snippets into groups'
	String get subtitle => 'Organize your machines, keys and snippets into groups';

	/// en: 'General'
	String get general => 'General';

	/// en: 'New group'
	String get newGroup => 'New group';

	/// en: 'Edit group'
	String get editGroup => 'Edit group';

	/// en: 'Create group'
	String get createGroup => 'Create group';

	/// en: 'Group name'
	String get groupName => 'Group name';

	/// en: 'e.g. Production'
	String get groupNameHint => 'e.g. Production';

	/// en: 'Group'
	String get groupTitle => 'Group';

	/// en: 'Select group'
	String get selectGroup => 'Select group';

	/// en: 'All'
	String get allGroups => 'All';

	/// en: 'Colour'
	String get colorLabel => 'Colour';

	/// en: 'Manage groups'
	String get manageGroups => 'Manage groups';

	/// en: 'Default'
	String get defaultBadge => 'Default';

	/// en: 'General is the fallback group. It cannot be renamed.'
	String get defaultNameLocked => 'General is the fallback group. It cannot be renamed.';

	/// en: 'Delete group?'
	String get deleteTitle => 'Delete group?';

	/// en: 'Are you sure you want to delete "{name}"? Machines, keys, and snippets in this group will be moved to General.'
	String deleteConfirm({required Object name}) => 'Are you sure you want to delete "${name}"? Machines, keys, and snippets in this group will be moved to General.';

	/// en: 'Rename group'
	String get renameTitle => 'Rename group';

	/// en: 'No groups yet'
	String get empty => 'No groups yet';

	/// en: '(one) {{count} machine} (other) {{count} machines}'
	String countMachines({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${count} machine',
		other: '${count} machines',
	);

	/// en: '(one) {{count} key} (other) {{count} keys}'
	String countKeys({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${count} key',
		other: '${count} keys',
	);

	/// en: '(one) {{count} snippet} (other) {{count} snippets}'
	String countSnippets({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${count} snippet',
		other: '${count} snippets',
	);

	/// en: 'Empty'
	String get groupEmpty => 'Empty';

	/// en: 'A group with this name already exists.'
	String get alreadyExists => 'A group with this name already exists.';

	/// en: 'No colour'
	String get noColour => 'No colour';

	/// en: 'Other groups'
	String get otherGroups => 'Other groups';

	/// en: 'Hold a group and drag it to change the order.'
	String get reorderHint => 'Hold a group and drag it to change the order.';
}

// Path: portForwarding
class Translations$portForwarding$en {
	Translations$portForwarding$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Port Forwarding'
	String get title => 'Port Forwarding';

	/// en: 'Add Rule'
	String get addRule => 'Add Rule';

	/// en: 'Edit Rule'
	String get editRule => 'Edit Rule';

	/// en: 'Local'
	String get localForward => 'Local';

	/// en: 'Remote'
	String get remoteForward => 'Remote';

	/// en: 'Opens a port on your device. Traffic is tunneled to a service on the server.'
	String get localForwardDescription => 'Opens a port on your device. Traffic is tunneled to a service on the server.';

	/// en: 'Opens a port on the SSH server. Incoming traffic is forwarded to a service on your device.'
	String get remoteForwardDescription => 'Opens a port on the SSH server. Incoming traffic is forwarded to a service on your device.';

	/// en: 'Where should the listening port be opened?'
	String get modeQuestion => 'Where should the listening port be opened?';

	/// en: 'On this device'
	String get modeOptionDevice => 'On this device';

	/// en: 'Access a remote service locally'
	String get modeOptionDeviceSubtitle => 'Access a remote service locally';

	/// en: 'On the SSH server'
	String get modeOptionServer => 'On the SSH server';

	/// en: 'Expose a local service remotely'
	String get modeOptionServerSubtitle => 'Expose a local service remotely';

	/// en: 'Direction'
	String get modeSection => 'Direction';

	/// en: 'Details'
	String get detailsSection => 'Details';

	/// en: 'Route'
	String get previewSection => 'Route';

	/// en: 'Local Port'
	String get localPort => 'Local Port';

	/// en: 'Target Host'
	String get remoteHost => 'Target Host';

	/// en: 'Target Port'
	String get remotePort => 'Target Port';

	/// en: 'Port on this device'
	String get localPortHint => 'Port on this device';

	/// en: 'Address visible from the SSH server'
	String get remoteHostHint => 'Address visible from the SSH server';

	/// en: 'Port on the target host'
	String get remotePortHint => 'Port on the target host';

	/// en: 'Server Port'
	String get remotePortLabel => 'Server Port';

	/// en: 'Port opened on the server'
	String get remotePortLabelHint => 'Port opened on the server';

	/// en: 'Target Host'
	String get localHostLabel => 'Target Host';

	/// en: 'Address of the service on this device'
	String get localHostLabelHint => 'Address of the service on this device';

	/// en: 'Target Port'
	String get localPortTargetLabel => 'Target Port';

	/// en: 'Port of the local service to expose'
	String get localPortTargetHint => 'Port of the local service to expose';

	/// en: 'Name'
	String get name => 'Name';

	/// en: 'Error'
	String get statusError => 'Error';

	/// en: 'Starting…'
	String get statusStarting => 'Starting…';

	/// en: 'Manage tunnels'
	String get manageTunnels => 'Manage tunnels';

	/// en: 'Profile Rules'
	String get profileRules => 'Profile Rules';

	/// en: 'Ad-hoc Tunnels'
	String get adhocTunnels => 'Ad-hoc Tunnels';

	/// en: 'Add Tunnel'
	String get addTunnel => 'Add Tunnel';

	/// en: 'No forwarding rules yet'
	String get noRulesYet => 'No forwarding rules yet';

	/// en: 'Server'
	String get server => 'Server';

	/// en: 'This device'
	String get arrowDevice => 'This device';

	/// en: 'Server'
	String get arrowServer => 'Server';
}

// Path: notifications
class Translations$notifications$en {
	Translations$notifications$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'connected'
	String get connected => 'connected';

	/// en: 'reconnecting…'
	String get reconnecting => 'reconnecting…';

	/// en: 'Download finished'
	String get transferDoneTitle => 'Download finished';

	/// en: '{name} saved'
	String transferDoneOne({required Object name}) => '${name} saved';

	/// en: '{count} files saved to {folder}'
	String transferDoneMany({required Object count, required Object folder}) => '${count} files saved to ${folder}';

	/// en: 'Download failed'
	String get transferFailedTitle => 'Download failed';

	/// en: '{name} did not finish.'
	String transferFailedBody({required Object name}) => '${name} did not finish.';

	/// en: 'Session disconnected'
	String get sessionDroppedTitle => 'Session disconnected';

	/// en: '{name} lost its connection.'
	String sessionDroppedBody({required Object name}) => '${name} lost its connection.';

	/// en: 'Session alerts'
	String get sessionChannelName => 'Session alerts';

	/// en: 'When a session loses its connection and cannot get it back.'
	String get sessionChannelDescription => 'When a session loses its connection and cannot get it back.';

	/// en: 'Download progress'
	String get downloadProgressChannelName => 'Download progress';

	/// en: 'Shown while a file is being downloaded.'
	String get downloadProgressChannelDescription => 'Shown while a file is being downloaded.';

	/// en: 'Download complete'
	String get downloadCompleteChannelName => 'Download complete';

	/// en: 'Shown when a download has finished.'
	String get downloadCompleteChannelDescription => 'Shown when a download has finished.';

	/// en: 'Saved'
	String get downloadSaved => 'Saved';
}

// Path: linkPreview
class Translations$linkPreview$en {
	Translations$linkPreview$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Loading preview…'
	String get loading => 'Loading preview…';

	/// en: 'Copy Link'
	String get copyLink => 'Copy Link';

	/// en: 'No preview available'
	String get noPreview => 'No preview available';
}

// Path: session
class Translations$session$en {
	Translations$session$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'The remote shell was restarted - reattached in the same directory, previous shell state is gone.'
	String get rebootRestored => 'The remote shell was restarted - reattached in the same directory, previous shell state is gone.';

	/// en: 'Session detached'
	String get offlineTitle => 'Session detached';

	/// en: 'The session is still running on the server. Re-attach to pick up where you left off.'
	String get offlineBody => 'The session is still running on the server. Re-attach to pick up where you left off.';

	/// en: 'Re-attach'
	String get attach => 'Re-attach';

	/// en: 'Detach (keep running)'
	String get detach => 'Detach (keep running)';

	/// en: 'Session'
	String get menuSection => 'Session';

	/// en: '{ms} ms'
	String latency({required Object ms}) => '${ms} ms';

	/// en: 'End session'
	String get endSession => 'End session';

	/// en: 'End session?'
	String get endSessionTitle => 'End session?';

	/// en: 'This kills the persistent session on {host}. Anything running in it stops.'
	String endSessionConfirm({required Object host}) => 'This kills the persistent session on ${host}. Anything running in it stops.';

	/// en: 'Couldn't end the session on {host}: {error}'
	String endSessionFailed({required Object host, required Object error}) => 'Couldn\'t end the session on ${host}: ${error}';

	/// en: 'Sessions on server'
	String get serverSessions => 'Sessions on server';

	/// en: 'No detached sessions on this server.'
	String get noServerSessions => 'No detached sessions on this server.';

	/// en: 'Could not list sessions: {error}'
	String serverSessionsFailed({required Object error}) => 'Could not list sessions: ${error}';

	/// en: 'Load sessions'
	String get loadSessions => 'Load sessions';

	/// en: 'Loaded {count} session(s).'
	String loadedSessions({required Object count}) => 'Loaded ${count} session(s).';

	/// en: 'Load sessions for every machine'
	String get loadGroupSessions => 'Load sessions for every machine';

	/// en: 'Loaded {count} session(s) from {machines} machine(s).'
	String loadedGroupSessions({required Object count, required Object machines}) => 'Loaded ${count} session(s) from ${machines} machine(s).';

	/// en: 'Loaded {count} session(s). {failed} machine(s) could not be reached.'
	String loadedGroupSessionsPartial({required Object count, required Object failed}) => 'Loaded ${count} session(s). ${failed} machine(s) could not be reached.';

	/// en: 'No detached sessions on these servers.'
	String get noGroupServerSessions => 'No detached sessions on these servers.';

	/// en: 'Stop'
	String get stopLoading => 'Stop';

	/// en: 'Stopped. Loaded {count} session(s).'
	String loadStopped({required Object count}) => 'Stopped. Loaded ${count} session(s).';

	/// en: 'Could not reach {failed} machine(s).'
	String groupSessionsFailed({required Object failed}) => 'Could not reach ${failed} machine(s).';

	/// en: 'Kill session?'
	String get killSessionTitle => 'Kill session?';

	/// en: 'Session {name} and everything running in it will be terminated.'
	String killSessionConfirm({required Object name}) => 'Session ${name} and everything running in it will be terminated.';

	/// en: 'Kill'
	String get kill => 'Kill';

	/// en: 'Session {name} killed.'
	String killed({required Object name}) => 'Session ${name} killed.';

	/// en: 'Update Termphin agent'
	String get agentUpdateTooltip => 'Update Termphin agent';

	/// en: 'Updating Termphin agent…'
	String get agentUpdating => 'Updating Termphin agent…';

	/// en: 'Termphin agent updated to {version}.'
	String agentUpdated({required Object version}) => 'Termphin agent updated to ${version}.';

	/// en: 'Could not update Termphin agent: {error}'
	String agentUpdateFailed({required Object error}) => 'Could not update Termphin agent: ${error}';

	/// en: 'Detached'
	String get detached => 'Detached';

	/// en: 'Ready to restore · {target}'
	String restoreDock({required Object target}) => 'Ready to restore · ${target}';

	/// en: 'Connected'
	String get connected => 'Connected';

	/// en: 'Rename session'
	String get rename => 'Rename session';

	/// en: 'Rename session'
	String get renameTitle => 'Rename session';

	/// en: 'Session name'
	String get renameLabel => 'Session name';

	/// en: 'Name cannot be empty'
	String get renameNameEmpty => 'Name cannot be empty';

	/// en: 'Use only letters, numbers, '-' and '_''
	String get renameNameInvalid => 'Use only letters, numbers, \'-\' and \'_\'';

	/// en: 'Rename failed: {error}'
	String renameFailed({required Object error}) => 'Rename failed: ${error}';

	/// en: 'Session renamed to {name}.'
	String renamed({required Object name}) => 'Session renamed to ${name}.';

	/// en: 'Couldn't reach the session'
	String get unreachableTitle => 'Couldn\'t reach the session';

	/// en: '{error} If the server was reset or lost power, the session is probably gone for good. Forget it on this device?'
	String unreachableBody({required Object error}) => '${error}\n\nIf the server was reset or lost power, the session is probably gone for good. Forget it on this device?';

	/// en: 'Forget'
	String get forget => 'Forget';

	/// en: 'Loading sessions from the server…'
	String get loadingServerSessions => 'Loading sessions from the server…';

	/// en: 'Checked just now'
	String get checkedJustNow => 'Checked just now';

	/// en: 'Checked {minutes}m ago'
	String checkedMinutesAgo({required Object minutes}) => 'Checked ${minutes}m ago';

	/// en: 'Checked {hours}h ago'
	String checkedHoursAgo({required Object hours}) => 'Checked ${hours}h ago';

	/// en: 'Checked {days}d ago'
	String checkedDaysAgo({required Object days}) => 'Checked ${days}d ago';
}

// Path: snippets
class Translations$snippets$en {
	Translations$snippets$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Snippets'
	String get title => 'Snippets';

	/// en: 'Save and manage your commands and scripts'
	String get subtitle => 'Save and manage your commands and scripts';

	/// en: 'All snippets'
	String get allSnippets => 'All snippets';

	/// en: 'New snippet'
	String get newTitle => 'New snippet';

	/// en: 'Edit snippet'
	String get editTitle => 'Edit snippet';

	/// en: 'Name'
	String get nameHint => 'Name';

	/// en: 'Command'
	String get commandHint => 'Command';

	/// en: 'Wrap a word in double curly braces to ask for it each time.'
	String get placeholderHint => 'Wrap a word in double curly braces to ask for it each time.';

	/// en: 'Arguments'
	String get argumentsTitle => 'Arguments';

	/// en: 'A default fills the field in for you when the snippet runs. Leave one blank to be asked from scratch.'
	String get argumentsHint => 'A default fills the field in for you when the snippet runs. Leave one blank to be asked from scratch.';

	/// en: 'Delete snippet?'
	String get deleteTitle => 'Delete snippet?';

	/// en: 'Are you sure you want to delete "{name}"?'
	String deleteConfirm({required Object name}) => 'Are you sure you want to delete "${name}"?';

	/// en: 'No snippets yet Tap + to add one'
	String get empty => 'No snippets yet\nTap + to add one';

	/// en: 'No snippets yet'
	String get emptyTitle => 'No snippets yet';

	/// en: 'Tap + to save a command or script.'
	String get emptySubtitle => 'Tap + to save a command or script.';

	/// en: 'Copy command'
	String get copyCommand => 'Copy command';

	/// en: 'Command copied.'
	String get commandCopied => 'Command copied.';

	/// en: 'Run'
	String get run => 'Run';

	/// en: 'Run snippet'
	String get runTitle => 'Run snippet';

	/// en: 'Choose machines'
	String get pickMachines => 'Choose machines';

	/// en: 'Add a machine first to run snippets on it.'
	String get pickMachinesEmpty => 'Add a machine first to run snippets on it.';

	/// en: 'Run on {count} machine(s)'
	String runNow({required Object count}) => 'Run on ${count} machine(s)';

	/// en: 'Runs'
	String get runsTitle => 'Runs';

	/// en: 'No runs yet'
	String get runsEmpty => 'No runs yet';

	/// en: 'Run a snippet on one or more machines to see its progress here.'
	String get runsEmptySubtitle => 'Run a snippet on one or more machines to see its progress here.';

	/// en: 'Waiting'
	String get runPending => 'Waiting';

	/// en: 'Connecting'
	String get runConnecting => 'Connecting';

	/// en: 'Running'
	String get runRunning => 'Running';

	/// en: 'Done'
	String get runSucceeded => 'Done';

	/// en: 'Exit {code}'
	String runFailed({required Object code}) => 'Exit ${code}';

	/// en: 'Failed to start'
	String get runError => 'Failed to start';

	/// en: '{done} of {total} finished'
	String runSummary({required Object done, required Object total}) => '${done} of ${total} finished';

	/// en: 'Clear'
	String get runForget => 'Clear';

	/// en: 'Enter to run'
	String get enterToRun => 'Enter to run';

	/// en: 'Could not send the snippet: {error}'
	String runStageFailed({required Object error}) => 'Could not send the snippet: ${error}';

	/// en: '{name} copy'
	String duplicateSuffix({required Object name}) => '${name} copy';

	/// en: 'Copied to “{name}”.'
	String duplicated({required Object name}) => 'Copied to “${name}”.';

	/// en: 'Deleted “{name}”.'
	String deleted({required Object name}) => 'Deleted “${name}”.';

	/// en: 'More actions'
	String get moreActions => 'More actions';

	/// en: 'What your snippets did, and what each machine said back.'
	String get runsSubtitle => 'What your snippets did, and what each machine said back.';

	/// en: 'Clear run history?'
	String get runsClearAllTitle => 'Clear run history?';

	/// en: 'Every run listed here is forgotten. Nothing running is stopped.'
	String get runsClearAllConfirm => 'Every run listed here is forgotten. Nothing running is stopped.';

	/// en: 'Clear this run?'
	String get runForgetTitle => 'Clear this run?';

	/// en: '“{name}” and everything it printed is forgotten.'
	String runForgetConfirm({required Object name}) => '“${name}” and everything it printed is forgotten.';

	/// en: 'Run again'
	String get runAgain => 'Run again';

	/// en: 'Copy output'
	String get copyOutput => 'Copy output';

	/// en: 'Output copied.'
	String get outputCopied => 'Output copied.';

	/// en: 'Nothing printed yet.'
	String get runNoOutput => 'Nothing printed yet.';

	/// en: '{count} of {total} selected'
	String pickMachinesSelected({required Object count, required Object total}) => '${count} of ${total} selected';

	/// en: 'Command'
	String get commandSection => 'Command';

	/// en: 'Filled in once, for every machine in this run.'
	String get runArgumentsHint => 'Filled in once, for every machine in this run.';
}

// Path: toolbar
class Translations$toolbar$en {
	Translations$toolbar$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Search keys…'
	String get searchHint => 'Search keys…';

	/// en: 'No keys match'
	String get noResults => 'No keys match';

	/// en: 'Navigation'
	String get categoryNavigation => 'Navigation';

	/// en: 'Editing'
	String get categoryEditing => 'Editing';

	/// en: 'Modifiers'
	String get categoryModifiers => 'Modifiers';

	/// en: 'Function keys'
	String get categoryFunction => 'Function keys';

	/// en: 'Symbols'
	String get categorySymbols => 'Symbols';

	/// en: 'Custom'
	String get categoryCustom => 'Custom';

	/// en: 'Text to send'
	String get customTextHint => 'Text to send';

	/// en: 'Go to page {number}'
	String goToPage({required Object number}) => 'Go to page ${number}';

	/// en: 'Quick settings'
	String get quickSettings => 'Quick settings';

	/// en: 'Toolbar'
	String get quickTabToolbar => 'Toolbar';

	/// en: 'Appearance'
	String get quickTabAppearance => 'Appearance';

	/// en: 'All terminal settings'
	String get allTerminalSettings => 'All terminal settings';

	/// en: 'Add toolbar layout'
	String get importTitle => 'Add toolbar layout';

	/// en: 'Shared layout'
	String get importUnnamed => 'Shared layout';

	/// en: '(one) {1 key types text} (other) {{n} keys type text}'
	String importTextKeys({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '1 key types text',
		other: '${n} keys type text',
	);

	/// en: '(one) {1 presses Enter} (other) {{n} press Enter}'
	String importPressEnter({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '1 presses Enter',
		other: '${n} press Enter',
	);

	/// en: 'A key marked Enter runs its command the moment it is tapped.'
	String get importEnterNote => 'A key marked Enter runs its command the moment it is tapped.';

	/// en: 'Enter'
	String get importEnter => 'Enter';

	/// en: 'Left out {count} keys this version does not have.'
	String importDropped({required Object count}) => 'Left out ${count} keys this version does not have.';

	/// en: 'Add'
	String get importAdd => 'Add';

	/// en: 'Add and use'
	String get importAddAndUse => 'Add and use';

	/// en: 'Layout added'
	String get importAdded => 'Layout added';

	/// en: 'This toolbar link could not be read.'
	String get importInvalid => 'This toolbar link could not be read.';

	/// en: 'Manage layouts'
	String get manageLayouts => 'Manage layouts';

	/// en: 'No keys yet'
	String get emptyLayout => 'No keys yet';

	/// en: 'Escape'
	String get escape => 'Escape';

	/// en: 'Tab'
	String get tab => 'Tab';

	/// en: 'Back tab'
	String get backTab => 'Back tab';

	/// en: 'Home'
	String get home => 'Home';

	/// en: 'End'
	String get end => 'End';

	/// en: 'Control'
	String get control => 'Control';

	/// en: 'Alt'
	String get alt => 'Alt';

	/// en: 'Shift'
	String get shift => 'Shift';

	/// en: 'Enter'
	String get enter => 'Enter';

	/// en: 'Delete'
	String get delete => 'Delete';

	/// en: 'Backspace'
	String get backspace => 'Backspace';

	/// en: 'Page up'
	String get pageUp => 'Page up';

	/// en: 'Page down'
	String get pageDown => 'Page down';

	/// en: 'Insert'
	String get insert => 'Insert';

	/// en: 'Space'
	String get space => 'Space';

	/// en: 'Arrow left'
	String get arrowLeft => 'Arrow left';

	/// en: 'Arrow up'
	String get arrowUp => 'Arrow up';

	/// en: 'Arrow down'
	String get arrowDown => 'Arrow down';

	/// en: 'Arrow right'
	String get arrowRight => 'Arrow right';

	/// en: 'Hide keyboard'
	String get hideKeyboard => 'Hide keyboard';

	/// en: 'F{number}'
	String functionKey({required Object number}) => 'F${number}';

	/// en: 'Control {key}'
	String ctrlCombo({required Object key}) => 'Control ${key}';

	/// en: 'Symbol {char}'
	String symbol({required Object char}) => 'Symbol ${char}';

	/// en: 'Send text {text}'
	String sendText({required Object text}) => 'Send text ${text}';

	/// en: 'Run snippet'
	String get runSnippet => 'Run snippet';

	/// en: 'Snippet no longer exists.'
	String get snippetMissing => 'Snippet no longer exists.';

	/// en: 'New key'
	String get newCustomKey => 'New key';

	/// en: 'Edit key'
	String get editCustomKey => 'Edit key';

	/// en: 'Sent to the terminal exactly as typed here.'
	String get customTextHelp => 'Sent to the terminal exactly as typed here.';

	/// en: 'Press Enter after'
	String get customAppendEnter => 'Press Enter after';

	/// en: 'Runs the text instead of only typing it'
	String get customAppendEnterSubtitle => 'Runs the text instead of only typing it';

	/// en: 'Key combo'
	String get comboMode => 'Key combo';

	/// en: 'Text'
	String get textMode => 'Text';

	/// en: 'Tap the box and press a key - whatever the keyboard sends becomes the key.'
	String get comboHint => 'Tap the box and press a key - whatever the keyboard sends becomes the key.';

	/// en: 'press a key'
	String get comboAwaitingKey => 'press a key';

	/// en: 'Keys the keyboard cannot send'
	String get comboSpecialKeys => 'Keys the keyboard cannot send';
}

// Path: actionDock
class Translations$actionDock$en {
	Translations$actionDock$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Fast upload'
	String get uploadFile => 'Fast upload';

	/// en: 'Upload {name} to'
	String uploadNameTo({required Object name}) => 'Upload ${name} to';

	/// en: 'Upload {count} files to'
	String uploadItemsTo({required Object count}) => 'Upload ${count} files to';

	/// en: 'Upload here'
	String get uploadHere => 'Upload here';

	/// en: 'Copy path'
	String get copyPath => 'Copy path';

	/// en: 'Copying the current path needs a Termphin agent session - this connection doesn't have one.'
	String get copyPathRequiresAgent => 'Copying the current path needs a Termphin agent session - this connection doesn\'t have one.';

	/// en: 'Couldn't find the current directory.'
	String get copyPathUnknown => 'Couldn\'t find the current directory.';

	/// en: 'Uploaded to {path}'
	String uploaded({required Object path}) => 'Uploaded to ${path}';

	/// en: 'Uploaded {count} files to {path}'
	String uploadedMany({required Object count, required Object path}) => 'Uploaded ${count} files to ${path}';

	/// en: 'Paste path'
	String get pasteUploadedPath => 'Paste path';

	/// en: 'Paste'
	String get paste => 'Paste';

	/// en: 'Search'
	String get search => 'Search';
}

// Path: share
class Translations$share$en {
	Translations$share$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Upload to'
	String get uploadTo => 'Upload to';

	/// en: 'Upload {count} files to'
	String uploadManyTo({required Object count}) => 'Upload ${count} files to';

	/// en: 'Search machines'
	String get searchHint => 'Search machines';

	/// en: 'Couldn't read the shared files.'
	String get noFiles => 'Couldn\'t read the shared files.';

	/// en: 'Only files can be sent to a server. Share a file instead.'
	String get textOnly => 'Only files can be sent to a server. Share a file instead.';

	/// en: 'Connecting to {name}'
	String connecting({required Object name}) => 'Connecting to ${name}';

	/// en: 'Couldn't connect'
	String get connectFailed => 'Couldn\'t connect';

	/// en: 'Uploading'
	String get uploading => 'Uploading';

	/// en: 'File {index} of {count}'
	String fileOf({required Object index, required Object count}) => 'File ${index} of ${count}';

	/// en: 'Uploaded'
	String get done => 'Uploaded';
}

// Path: terminalSearch
class Translations$terminalSearch$en {
	Translations$terminalSearch$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Search the output'
	String get hint => 'Search the output';

	/// en: '{current}/{total}'
	String matchCount({required Object current, required Object total}) => '${current}/${total}';

	/// en: 'None'
	String get noMatches => 'None';

	/// en: 'Match case'
	String get matchCase => 'Match case';

	/// en: 'Older match'
	String get older => 'Older match';

	/// en: 'Newer match'
	String get newer => 'Newer match';

	/// en: 'Close search'
	String get close => 'Close search';
}

// Path: commandPalette
class Translations$commandPalette$en {
	Translations$commandPalette$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Search snippets…'
	String get searchHintSnippets => 'Search snippets…';

	/// en: 'Nothing here yet'
	String get empty => 'Nothing here yet';

	/// en: 'No matches'
	String get noResults => 'No matches';

	/// en: 'Enter to run'
	String get enterToRun => 'Enter to run';

	/// en: 'Insert snippet'
	String get insertSnippetTitle => 'Insert snippet';
}

// Path: background
class Translations$background$en {
	Translations$background$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Active sessions'
	String get channelName => 'Active sessions';

	/// en: 'Shown while Termphin keeps SSH sessions connected in the background.'
	String get channelDescription => 'Shown while Termphin keeps SSH sessions connected in the background.';

	/// en: '1 session connected'
	String get notificationTitleOne => '1 session connected';

	/// en: '{count} sessions connected'
	String notificationTitleOther({required Object count}) => '${count} sessions connected';

	/// en: 'Tap to return'
	String get notificationText => 'Tap to return';
}

// Path: analyticsConsent
class Translations$analyticsConsent$en {
	Translations$analyticsConsent$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Share usage analytics?'
	String get title => 'Share usage analytics?';

	/// en: 'Nothing personal, nothing from your screen or sessions - just a handful of named events: which screens you open, which settings you change, whether a connection succeeded or why it failed. Enough to tell what's used and catch crashes. No autocapture, no tracking of what you type or where you connect. Nothing is collected unless you check the box below, and you can change your mind any time in Settings.'
	String get body => 'Nothing personal, nothing from your screen or sessions - just a handful of named events: which screens you open, which settings you change, whether a connection succeeded or why it failed. Enough to tell what\'s used and catch crashes. No autocapture, no tracking of what you type or where you connect. Nothing is collected unless you check the box below, and you can change your mind any time in Settings.';

	/// en: 'Share anonymous usage data'
	String get checkboxLabel => 'Share anonymous usage data';

	/// en: 'By continuing you accept the terms of service and the privacy policy.'
	String get legalNotice => 'By continuing you accept the terms of service and the privacy policy.';

	/// en: 'Privacy policy'
	String get privacyLink => 'Privacy policy';

	/// en: 'Terms of service'
	String get termsLink => 'Terms of service';

	/// en: 'Allow'
	String get allow => 'Allow';
}

// Path: onboarding
class Translations$onboarding$en {
	Translations$onboarding$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Welcome to Termphin'
	String get welcomeTitle => 'Welcome to Termphin';

	/// en: 'An SSH client whose sessions survive a dropped connection. Lock the phone, lose signal, come back - your shell is still there.'
	String get welcomeBody => 'An SSH client whose sessions survive a dropped connection. Lock the phone, lose signal, come back - your shell is still there.';

	/// en: 'Get started'
	String get getStarted => 'Get started';

	/// en: 'Do you have a server?'
	String get serverTitle => 'Do you have a server?';

	/// en: 'Termphin connects to machines you already run, over SSH.'
	String get serverBody => 'Termphin connects to machines you already run, over SSH.';

	/// en: 'Yes, I have one'
	String get serverYes => 'Yes, I have one';

	/// en: 'A VPS, a Raspberry Pi, a machine at work - anything you can SSH into.'
	String get serverYesSubtitle => 'A VPS, a Raspberry Pi, a machine at work - anything you can SSH into.';

	/// en: 'Not yet'
	String get serverNotYet => 'Not yet';

	/// en: 'See where to get one.'
	String get serverNotYetSubtitle => 'See where to get one.';

	/// en: 'A few things to set up'
	String get permissionsTitle => 'A few things to set up';

	/// en: 'All optional, and all changeable later in Settings.'
	String get permissionsBody => 'All optional, and all changeable later in Settings.';

	/// en: 'Unrestricted battery use'
	String get backgroundTitle => 'Unrestricted battery use';

	/// en: 'Lets the system keep Termphin running so SSH sessions survive when you switch apps or lock the screen.'
	String get backgroundSubtitle => 'Lets the system keep Termphin running so SSH sessions survive when you switch apps or lock the screen.';

	/// en: 'Notifications'
	String get notificationsTitle => 'Notifications';

	/// en: 'Shows what sessions are running and how downloads are getting on.'
	String get notificationsSubtitle => 'Shows what sessions are running and how downloads are getting on.';

	/// en: 'Local network access'
	String get localNetworkTitle => 'Local network access';

	/// en: 'Lets you reach machines on the network you're connected to. Skip it if yours are all elsewhere.'
	String get localNetworkSubtitle => 'Lets you reach machines on the network you\'re connected to. Skip it if yours are all elsewhere.';

	/// en: 'Continue'
	String get continueAction => 'Continue';

	/// en: 'Finish'
	String get finish => 'Finish';

	/// en: 'Skip'
	String get skip => 'Skip';

	/// en: 'Back'
	String get back => 'Back';
}

// Path: serverGuide
class Translations$serverGuide$en {
	Translations$serverGuide$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Where to get a server'
	String get title => 'Where to get a server';

	/// en: 'Your own computer'
	String get computerTitle => 'Your own computer';

	/// en: 'Turn on SSH: Remote Login on a Mac, OpenSSH Server on Windows or Linux. Then add its address here.'
	String get computerBody => 'Turn on SSH: Remote Login on a Mac, OpenSSH Server on Windows or Linux. Then add its address here.';

	/// en: 'A cloud server'
	String get cloudTitle => 'A cloud server';

	/// en: 'Any Linux VPS works. The provider gives you an address, a username and a password or key.'
	String get cloudBody => 'Any Linux VPS works. The provider gives you an address, a username and a password or key.';
}

// Path: whatsNew
class Translations$whatsNew$en {
	Translations$whatsNew$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'What's new'
	String get title => 'What\'s new';

	/// en: 'Got it'
	String get gotIt => 'Got it';

	/// en: 'Now available'
	String get nowAvailable => 'Now available';

	/// en: 'Next'
	String get next => 'Next';
}

// Path: hostKey
class Translations$hostKey$en {
	Translations$hostKey$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Unknown host'
	String get newTitle => 'Unknown host';

	/// en: 'Host key changed'
	String get changedTitle => 'Host key changed';

	/// en: 'Termphin has not connected to this address before. Check that the fingerprint matches the server, then accept it to remember this host.'
	String get newBody => 'Termphin has not connected to this address before. Check that the fingerprint matches the server, then accept it to remember this host.';

	/// en: 'The key this address presented is not the one Termphin pinned. A rebuilt server or a rotated key looks like this - so does someone sitting between you and it.'
	String get changedBody => 'The key this address presented is not the one Termphin pinned. A rebuilt server or a rotated key looks like this - so does someone sitting between you and it.';

	/// en: 'Only accept this if you know the server's key changed.'
	String get changedWarning => 'Only accept this if you know the server\'s key changed.';

	/// en: '{host}:{port}'
	String endpoint({required Object host, required Object port}) => '${host}:${port}';

	/// en: 'Key type'
	String get keyTypeLabel => 'Key type';

	/// en: 'Fingerprint'
	String get fingerprintLabel => 'Fingerprint';

	/// en: 'Previously pinned'
	String get pinnedLabel => 'Previously pinned';

	/// en: 'On the server, ssh-keygen -lf its host key file prints the same fingerprint.'
	String get verifyHint => 'On the server, ssh-keygen -lf its host key file prints the same fingerprint.';

	/// en: 'Accept and remember'
	String get accept => 'Accept and remember';

	/// en: 'Accept new key'
	String get acceptChanged => 'Accept new key';

	/// en: 'Do not connect'
	String get reject => 'Do not connect';
}

// Path: keyboardInteractive
class Translations$keyboardInteractive$en {
	Translations$keyboardInteractive$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'The server is asking'
	String get title => 'The server is asking';

	/// en: 'Response'
	String get fallbackPrompt => 'Response';

	/// en: 'Send'
	String get submit => 'Send';
}

// Path: manual
class Translations$manual$en {
	Translations$manual$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Manual'
	String get title => 'Manual';

	/// en: 'Could not load the manual.'
	String get loadFailed => 'Could not load the manual.';

	/// en: 'Check your connection and try again.'
	String get loadFailedBody => 'Check your connection and try again.';

	/// en: 'Try again'
	String get retry => 'Try again';

	/// en: 'Open in browser'
	String get openInBrowser => 'Open in browser';

	/// en: 'Could not open the link.'
	String get openFailed => 'Could not open the link.';

	/// en: 'How to fix this'
	String get howToFix => 'How to fix this';

	/// en: 'Troubleshooting guide'
	String get troubleshooting => 'Troubleshooting guide';

	/// en: 'Read more in the manual'
	String get readMore => 'Read more in the manual';

	/// en: 'What is this?'
	String get whatIsThis => 'What is this?';
}

// Path: tagMigration
class Translations$tagMigration$en {
	Translations$tagMigration$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Convert tags to groups'
	String get title => 'Convert tags to groups';

	/// en: 'Tags have been replaced by groups. Each machine and snippet now belongs to a single group. Choose which tags to convert into groups.'
	String get explanation => 'Tags have been replaced by groups. Each machine and snippet now belongs to a single group. Choose which tags to convert into groups.';

	/// en: 'Records with several tags will join the first of their tags kept in this list.'
	String get multipleTagsNotice => 'Records with several tags will join the first of their tags kept in this list.';

	/// en: '(one) {{n} record} (other) {{n} records}'
	String usageCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} record',
		other: '${n} records',
	);

	/// en: 'Create groups'
	String get createGroups => 'Create groups';

	/// en: 'Start fresh'
	String get startFresh => 'Start fresh';

	/// en: 'Discard tags?'
	String get skipDialogTitle => 'Discard tags?';

	/// en: 'Your tags will be discarded and cannot be restored. All machines and snippets will be moved to General.'
	String get skipDialogMessage => 'Your tags will be discarded and cannot be restored. All machines and snippets will be moved to General.';

	/// en: 'Discard tags'
	String get skipDialogConfirm => 'Discard tags';
}

// Path: selection
class Translations$selection$en {
	Translations$selection$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '(one) {{count} selected} (other) {{count} selected}'
	String countSelected({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${count} selected',
		other: '${count} selected',
	);

	/// en: 'Move to group'
	String get moveToGroup => 'Move to group';

	/// en: 'Clear selection'
	String get clear => 'Clear selection';

	/// en: 'Select all'
	String get selectAll => 'Select all';

	/// en: 'All'
	String get all => 'All';

	/// en: 'Move'
	String get move => 'Move';

	/// en: '(one) {Delete {count} item?} (other) {Delete {count} items?}'
	String deleteTitle({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Delete ${count} item?',
		other: 'Delete ${count} items?',
	);

	/// en: 'This cannot be undone.'
	String get deleteConfirm => 'This cannot be undone.';

	/// en: 'Delete anyway'
	String get deleteAnyway => 'Delete anyway';

	/// en: '(one) {Moved {count} to {group}} (other) {Moved {count} to {group}}'
	String moved({required num n, required Object count, required Object group}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Moved ${count} to ${group}',
		other: 'Moved ${count} to ${group}',
	);

	/// en: '(one) {Deleted {count} item} (other) {Deleted {count} items}'
	String deleted({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Deleted ${count} item',
		other: 'Deleted ${count} items',
	);

	/// en: '(one) {1 machine connects through one you are deleting and will stop connecting:} (other) {{count} machines connect through one you are deleting and will stop connecting:}'
	String machinesInUseBody({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '1 machine connects through one you are deleting and will stop connecting:',
		other: '${count} machines connect through one you are deleting and will stop connecting:',
	);

	/// en: '(one) {1 machine uses a key you are deleting and will stop connecting:} (other) {{count} machines use a key you are deleting and will stop connecting:}'
	String keysInUseBody({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '1 machine uses a key you are deleting and will stop connecting:',
		other: '${count} machines use a key you are deleting and will stop connecting:',
	);

	/// en: 'Still in use'
	String get inUseTitle => 'Still in use';
}

// Path: globalSearch
class Translations$globalSearch$en {
	Translations$globalSearch$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Search everything'
	String get hint => 'Search everything';

	/// en: 'Back'
	String get back => 'Back';

	/// en: 'Clear'
	String get clear => 'Clear';

	/// en: 'Machines'
	String get machines => 'Machines';

	/// en: 'Sessions'
	String get sessions => 'Sessions';

	/// en: 'Groups'
	String get groups => 'Groups';

	/// en: 'Snippets'
	String get snippets => 'Snippets';

	/// en: 'Keys'
	String get keys => 'Keys';

	/// en: 'Recent machines'
	String get recentMachines => 'Recent machines';

	/// en: 'Open sessions'
	String get openSessions => 'Open sessions';

	/// en: 'Find machines by name, address or username, and sessions, groups, snippets and keys by name.'
	String get emptyHint => 'Find machines by name, address or username, and sessions, groups, snippets and keys by name.';

	/// en: 'Nothing matches "{query}"'
	String noResults({required Object query}) => 'Nothing matches "${query}"';

	/// en: 'In {group}'
	String inGroup({required Object group}) => 'In ${group}';

	/// en: 'Search everything again'
	String get leaveGroup => 'Search everything again';

	/// en: '(one) {{n} machine} (other) {{n} machines}'
	String machineCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} machine',
		other: '${n} machines',
	);

	/// en: '(one) {{n} snippet} (other) {{n} snippets}'
	String snippetCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} snippet',
		other: '${n} snippets',
	);

	/// en: '(one) {{n} key} (other) {{n} keys}'
	String keyCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} key',
		other: '${n} keys',
	);

	/// en: 'Empty'
	String get emptyGroup => 'Empty';
}

// Path: sftp.errors
class Translations$sftp$errors$en {
	Translations$sftp$errors$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'File or directory not found.'
	String get notFound => 'File or directory not found.';

	/// en: 'Permission denied. You don't have access to this file or directory.'
	String get permissionDenied => 'Permission denied. You don\'t have access to this file or directory.';

	/// en: 'Operation failed. The server may be low on disk space or the file may be locked.'
	String get failure => 'Operation failed. The server may be low on disk space or the file may be locked.';

	/// en: 'Connection to the server was lost.'
	String get connectionLost => 'Connection to the server was lost.';

	/// en: 'Not enough disk space.'
	String get diskFull => 'Not enough disk space.';

	/// en: 'File is locked or in use.'
	String get fileLocked => 'File is locked or in use.';

	/// en: 'Network error. Check your connection.'
	String get networkError => 'Network error. Check your connection.';

	/// en: 'Operation timed out.'
	String get timeout => 'Operation timed out.';

	/// en: 'Failed to save file locally.'
	String get localWriteError => 'Failed to save file locally.';

	/// en: 'Failed to read local file for upload.'
	String get uploadReadError => 'Failed to read local file for upload.';

	/// en: 'Operation cancelled.'
	String get cancelled => 'Operation cancelled.';

	/// en: 'Operation failed: {error}'
	String generic({required Object error}) => 'Operation failed: ${error}';

	/// en: 'This server only allows file transfers, so it cannot copy files itself.'
	String get noShell => 'This server only allows file transfers, so it cannot copy files itself.';
}

// Path: sftp.queue
class Translations$sftp$queue$en {
	Translations$sftp$queue$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Show transfers'
	String get show => 'Show transfers';

	/// en: 'Hide transfers'
	String get hide => 'Hide transfers';

	/// en: 'Waiting'
	String get waiting => 'Waiting';

	/// en: 'Cancelling…'
	String get cancelling => 'Cancelling…';

	/// en: 'Cancelled'
	String get cancelled => 'Cancelled';

	/// en: 'Copying on the server'
	String get copying => 'Copying on the server';

	/// en: 'Moving on the server'
	String get moving => 'Moving on the server';

	/// en: '{position} of {count}'
	String position({required Object position, required Object count}) => '${position} of ${count}';

	/// en: '{count} failed - tap to see why'
	String failedCount({required Object count}) => '${count} failed - tap to see why';

	/// en: 'Clear'
	String get clearFinished => 'Clear';

	/// en: '{count} items'
	String items({required Object count}) => '${count} items';
}

// Path: connection.quality
class Translations$connection$quality$en {
	Translations$connection$quality$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '(one) {{n} key waiting to send} (other) {{n} keys waiting to send}'
	String queued({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} key waiting to send',
		other: '${n} keys waiting to send',
	);

	/// en: 'No reply for {seconds}s'
	String unresponsive({required Object seconds}) => 'No reply for ${seconds}s';

	/// en: 'Slow connection · {ms} ms'
	String slow({required Object ms}) => 'Slow connection · ${ms} ms';

	/// en: 'Connection log'
	String get openDetails => 'Connection log';
}

// Path: connection.errors
class Translations$connection$errors$en {
	Translations$connection$errors$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'The server did not answer. Check the address and port.'
	String get hostUnreachable => 'The server did not answer. Check the address and port.';

	/// en: 'This machine is on the network you're connected to, which Termphin doesn't have permission to reach yet.'
	String get localNetworkBlocked => 'This machine is on the network you\'re connected to, which Termphin doesn\'t have permission to reach yet.';

	/// en: 'Nothing answered at this address. It is on the network you're connected to, so either the machine is off or Termphin does not have permission to reach it.'
	String get localNetworkUnverified => 'Nothing answered at this address. It is on the network you\'re connected to, so either the machine is off or Termphin does not have permission to reach it.';

	/// en: 'The server stopped answering.'
	String get timeout => 'The server stopped answering.';

	/// en: 'Wrong username or password.'
	String get authFailedPassword => 'Wrong username or password.';

	/// en: 'The server did not accept this key. Check the username, and that the key is authorised on the server.'
	String get authFailedKey => 'The server did not accept this key. Check the username, and that the key is authorised on the server.';

	/// en: 'You did not accept the server's key. Nothing was sent.'
	String get hostKeyRejected => 'You did not accept the server\'s key. Nothing was sent.';

	/// en: 'This server's key has changed. Remove the old one in Settings → Known hosts if that was expected.'
	String get hostKeyMismatch => 'This server\'s key has changed. Remove the old one in Settings → Known hosts if that was expected.';

	/// en: 'This profile's key is gone from the key manager.'
	String get keyMissing => 'This profile\'s key is gone from the key manager.';

	/// en: 'Wrong passphrase for this key.'
	String get keyPassphrase => 'Wrong passphrase for this key.';

	/// en: 'This key could not be read.'
	String get keyInvalid => 'This key could not be read.';

	/// en: 'The jump host connection failed.'
	String get jumpHost => 'The jump host connection failed.';

	/// en: 'This profile's jump host is not set up right.'
	String get jumpHostConfig => 'This profile\'s jump host is not set up right.';
}

/// The flat map containing all translations for locale <en>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on Translations {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'nav.home' => 'Home',
			'nav.snippets' => 'Snippets',
			'nav.keys' => 'Keys',
			'nav.settings' => 'Settings',
			'nav.collapseSidebar' => 'Collapse sidebar',
			'nav.expandSidebar' => 'Expand sidebar',
			'errorReports.empty' => 'No errors recorded',
			'errorReports.emptySubtitle' => 'When Termphin runs into an error, it shows up here so you can send it to us.',
			'errorReports.privacy' => 'Kept on this device only. Nothing is sent until you send it.',
			'errorReports.sendEmail' => 'Send by email',
			'errorReports.share' => 'Share',
			'errorReports.clear' => 'Clear',
			'errorReports.clearTitle' => 'Clear error reports?',
			'errorReports.clearMessage' => 'Every recorded error is removed from this device.',
			'errorReports.repeated' => ({required Object count}) => '${count} times',
			'errorReports.emailSubject' => 'Termphin error report',
			'common.add' => 'Add',
			'common.cancel' => 'Cancel',
			'common.save' => 'Save',
			'common.delete' => 'Delete',
			'common.rename' => 'Rename',
			'common.import' => 'Import',
			'common.export' => 'Export',
			'common.done' => 'Done',
			'common.copy' => 'Copy',
			'common.discard' => 'Discard',
			'common.required' => 'Required',
			'common.invalid' => 'Invalid',
			'common.optional' => 'optional',
			'common.reset' => 'Reset',
			'common.edit' => 'Edit',
			'common.retry' => 'Retry',
			'common.back' => 'Back',
			'common.refresh' => 'Refresh',
			'common.showPassword' => 'Show password',
			'common.hidePassword' => 'Hide password',
			'common.close' => 'Close',
			'common.disable' => 'Disable',
			'common.name' => 'Name',
			'common.keyCopied' => 'Public key copied.',
			'common.copied' => 'Copied.',
			'common.generate' => 'Generate',
			'common.paste' => 'Paste',
			'common.share' => 'Share',
			'common.allow' => 'Allow',
			'common.allowed' => 'Allowed',
			'common.justNow' => 'just now',
			'common.minutesAgo' => ({required Object minutes}) => '${minutes}m ago',
			'common.hoursAgo' => ({required Object hours}) => '${hours}h ago',
			'common.daysAgo' => ({required Object days}) => '${days}d ago',
			'common.duplicate' => 'Duplicate',
			'common.selectAll' => 'Select all',
			'common.clearSelection' => 'Clear selection',
			'common.clearAll' => 'Clear all',
			'common.clearSearch' => 'Clear search',
			'common.undo' => 'Undo',
			'lock.incorrectPin' => 'Incorrect PIN',
			'lock.setPin' => 'Set PIN',
			'lock.confirmPin' => 'Confirm PIN',
			'lock.pinMismatch' => 'PINs don\'t match - try again',
			'lock.authenticateReason' => 'Authenticate to open Termphin',
			'lock.enterPin' => 'Enter your PIN',
			'lock.checking' => 'Checking…',
			'lock.incorrectPinTriesLeft' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Incorrect PIN. One more try before a short wait.', other: 'Incorrect PIN. ${count} more tries before a short wait.', ), 
			'lock.tooManyAttempts' => ({required Object time}) => 'Too many attempts. Try again in ${time}.',
			'lock.pinLengthHint' => '4 to 6 digits',
			'lock.pinNext' => 'Next',
			'profiles.title' => 'Termphin',
			'profiles.machines' => 'Machines',
			'profiles.keys' => 'Keys',
			'profiles.machinesHeading' => 'Your machines',
			'profiles.machinesSubtitle' => 'Connect to your SSH servers',
			'profiles.emptyMachines' => 'No machines yet\nTap + to add one',
			'profiles.deleteTitle' => 'Delete profile?',
			'profiles.deleteConfirm' => ({required Object name}) => 'Are you sure you want to delete "${name}"?',
			'profiles.deleted' => 'Profile deleted.',
			'profiles.addMachine' => 'Machine Profile',
			'profiles.keyCopied' => ({required Object name}) => 'Public key "${name}" copied.',
			'profiles.searchHint' => 'Search machines…',
			'profiles.sortRecent' => 'Recent',
			'profiles.sortAZ' => 'A-z',
			'profiles.sortZA' => 'Z-a',
			'profiles.noResults' => ({required Object query}) => 'No results for "${query}"',
			'profiles.connections' => 'Connections',
			'profiles.closeAll' => 'Close all',
			'profiles.allMachines' => 'All machines',
			'profiles.addMachineButton' => 'Add machine',
			'profiles.addFirstMachine' => 'Add your first machine',
			'profiles.emptyMachinesTitle' => 'No machines yet',
			'profiles.emptyMachinesSubtitle' => 'Add a server you can SSH into to start your first session.',
			'profiles.moreActions' => 'More actions',
			'profiles.sortMachines' => 'Sort machines',
			'profiles.returnToSession' => ({required Object name}) => 'Return to ${name}',
			'profiles.noServerYet' => 'No server yet?',
			'profiles.quickAddHint' => 'user@host',
			'profiles.quickAddTooltip' => 'Add this machine',
			'profiles.quickAddInvalid' => 'Type it the way you would after ssh, like user@server.',
			'profileForm.newTitle' => 'New Machine',
			'profileForm.editTitle' => 'Edit Machine',
			'profileForm.connection' => 'Connection',
			'profileForm.nameHint' => 'e.g. Production',
			'profileForm.host' => 'Host',
			'profileForm.hostHint' => '192.168.1.1',
			'profileForm.port' => 'Port',
			'profileForm.portHint' => '22',
			'profileForm.username' => 'Username',
			'profileForm.usernameHint' => 'root',
			'profileForm.authentication' => 'Authentication',
			'profileForm.noAuth' => 'No authentication',
			'profileForm.password' => 'Password',
			'profileForm.sshKey' => 'SSH Key',
			'profileForm.passphrase' => 'Passphrase',
			'profileForm.enterKeyManually' => 'Enter key manually',
			'profileForm.privateKeyRequired' => 'Private key is required.',
			'profileForm.saveFailed' => ({required Object error}) => 'Could not save: ${error}',
			'profileForm.avatar' => 'Avatar',
			'profileForm.fallbackHosts' => 'Fallback addresses',
			'profileForm.fallbackHostsHint' => 'Tried in order if the host above doesn\'t answer, e.g. a Tailscale IP or a LAN address.',
			'profileForm.fallbackHostHint' => 'host or host:port',
			'profileForm.addFallbackHost' => 'Add address',
			'profileForm.fallbackHostsEmpty' => 'No fallback addresses yet.',
			'profileForm.mainHostFirst' => 'Always try the main address first',
			'profileForm.mainHostFirstHint' => 'Turn off to start with the address that worked last time.',
			'profileForm.fallbackHostInvalid' => 'Enter a host, optionally as host:port.',
			'profileForm.jumpHost' => 'Jump host',
			'profileForm.jumpHostHint' => 'Connect through another profile first, the way OpenSSH\'s ProxyJump does. The session with this host stays end-to-end encrypted - the jump host moves the bytes, it cannot read them.',
			'profileForm.jumpHostNone' => 'Connect directly',
			'profileForm.jumpHostNoCandidates' => 'No other profile can be used here yet.',
			'profileForm.linkPrefilled' => 'Filled in from the link. Check it before saving.',
			'profileForm.linkInvalid' => 'That link is not a valid ssh:// address.',
			'profileForm.testConnection' => 'Test connection',
			'profileForm.testingConnection' => 'Connecting… tap to stop',
			'profileForm.testSucceeded' => 'It works - the server let you in.',
			'profileForm.noAuthHint' => 'The server lets anyone in with just the username. Rare - mostly test machines.',
			'profileForm.passwordHint' => 'The account\'s password on the server. The simplest way to start; it is stored encrypted on this device.',
			'profileForm.sshKeyHint' => 'A key pair: the private half stays on this device, the public half goes into ~/.ssh/authorized_keys on the server. Safer than a password, and nothing to type.',
			'profileForm.createKey' => 'Create a new key',
			'profileForm.chooseAuth' => 'Choose how to sign in to this machine.',
			'keys.title' => 'SSH Keys',
			'keys.subtitle' => 'Generate, import and manage your SSH keys',
			'keys.allKeys' => 'All keys',
			'keys.emptyTitle' => 'No SSH keys yet',
			'keys.emptySubtitle' => 'Tap + to generate or import a key.',
			'keys.deleteTitle' => 'Delete key?',
			'keys.deleteConfirm' => ({required Object name}) => 'Delete "${name}"? This cannot be undone.',
			'keys.renameTitle' => 'Rename key',
			'keys.copyPublicKey' => 'Copy public key',
			'keys.keyCreatedTitle' => 'Key created',
			'keys.keyCreatedInstructions' => 'Add this public key to your server\'s ~/.ssh/authorized_keys:',
			'keys.importTitle' => 'Import key (PEM)',
			'keys.keyNameLabel' => 'Key name',
			'keys.keyNameHint' => 'e.g. my-laptop',
			'keys.privateKeyLabel' => 'Private key (PEM)',
			'keys.privateKeyHint' => '-----BEGIN OPENSSH PRIVATE KEY-----\n...',
			'keys.keyPassphraseLabel' => 'Key passphrase',
			'keys.keyPassphraseHint' => 'This key is encrypted',
			'keys.keyPassphraseNote' => 'Used only to read the key. Termphin does not store it - enter it again on the profile that uses this key.',
			'keys.selectPrivateKeyFile' => 'Choose key file',
			'keys.selectedFile' => ({required Object name}) => 'Selected: ${name}',
			'keys.keyFileTooLarge' => 'The key file is too large.',
			'keys.keyFileEmpty' => 'The selected file is empty.',
			'keys.keyFileReadFailed' => ({required Object error}) => 'Could not read key file: ${error}',
			'keys.importSuccess' => ({required Object name}) => 'Key "${name}" imported.',
			'keys.addKey' => 'Add SSH Key',
			'keys.generateEd25519' => 'Generate Ed25519',
			'keys.generateEd25519Subtitle' => 'Fast, secure modern key',
			'keys.generateRsa2048' => 'Generate RSA 2048',
			'keys.generateRsa2048Subtitle' => 'Compatible with most servers',
			'keys.generateRsa4096' => 'Generate RSA 4096',
			'keys.generateRsa4096Subtitle' => 'Stronger RSA (takes longer)',
			'keys.importPem' => 'Import private key',
			'keys.importPemSubtitle' => 'Choose a key file or paste PEM',
			'keys.deleted' => ({required Object name}) => 'Key "${name}" deleted.',
			'keys.importFailed' => ({required Object error}) => 'Import failed: ${error}',
			'keys.importWrongPassphrase' => 'That passphrase does not open this key.',
			'keys.importPassphraseRequired' => 'This key is encrypted. Enter its passphrase to import it.',
			'keys.generateFailed' => ({required Object error}) => 'Failed to generate key: ${error}',
			'keys.newKeyTitle' => 'New key',
			'keys.editKeyTitle' => 'Edit key',
			'keys.keyTypeLabel' => 'Key type',
			'keys.keyTypeEd25519' => 'Ed25519',
			'keys.keyTypeRsa2048' => 'RSA 2048',
			'keys.keyTypeRsa4096' => 'RSA 4096',
			'keys.keyTypeImport' => 'Import existing key',
			'keys.keyTypeEd25519Subtitle' => 'Fast and modern. The right choice unless a server demands otherwise.',
			'keys.keyTypeRsa2048Subtitle' => 'Widely compatible with older servers.',
			'keys.keyTypeRsa4096Subtitle' => 'Stronger RSA, slower to generate.',
			'keys.keyTypeImportSubtitle' => 'Paste a private key or pick a file.',
			'keys.generating' => 'Generating key...',
			'keys.inUseTitle' => 'Key is in use',
			'keys.inUseBody' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '1 machine uses this key and will stop connecting:', other: '${count} machines use this key and will stop connecting:', ), 
			'keys.deleteAnyway' => 'Delete anyway',
			'terminal.selectDevice' => 'Select device to connect',
			'terminal.suggestionDismiss' => 'Hide suggestion',
			'terminal.newSession' => 'New session',
			'terminal.switchToTerminal' => 'Terminal',
			'terminal.switchToSftp' => 'SFTP Browser',
			'terminal.modeTerminal' => 'Terminal',
			'terminal.modeFiles' => 'Files',
			'terminal.disconnect' => 'Disconnect',
			'terminal.connectFailed' => 'Failed to connect.',
			'terminal.paste' => 'Paste',
			'terminal.openInBrowser' => 'Open in Browser',
			'terminal.scrollToBottom' => 'Scroll to bottom',
			'terminal.searchDevices' => 'Search devices…',
			'terminal.noDevices' => 'No devices found',
			'terminal.remoteCopied' => 'Remote host copied to clipboard.',
			'terminal.splitWith' => 'Split screen with…',
			'terminal.splitWithTitle' => 'Split screen with',
			'terminal.splitNewConnection' => 'New connection',
			'terminal.unsplit' => 'Move out of split',
			'terminal.splitDivider' => 'Resize split',
			'sftp.deleteTitle' => 'Delete?',
			'sftp.deleteConfirm' => ({required Object filename}) => 'Are you sure you want to delete ${filename}?',
			'sftp.deleteSelectedTitle' => ({required Object count}) => 'Delete ${count} items?',
			'sftp.deleteSelectedConfirm' => ({required Object count}) => 'Are you sure you want to delete ${count} selected items?',
			'sftp.openInEditor' => 'Open in Editor',
			'sftp.download' => 'Download',
			'sftp.downloadComplete' => ({required Object filename}) => '${filename} saved',
			'sftp.deleteFailed' => ({required Object error}) => 'Delete failed: ${error}',
			'sftp.renameFailed' => ({required Object error}) => 'Rename failed: ${error}',
			'sftp.transferBytes' => ({required Object done, required Object total}) => '${done} of ${total}',
			'sftp.transferRate' => ({required Object rate}) => '${rate}/s',
			'sftp.transferItemCount' => ({required Object current, required Object total}) => '${current} of ${total}',
			'sftp.transferScanning' => ({required Object count}) => 'Scanning folder… ${count} items',
			'sftp.downloadCancelled' => 'Download cancelled',
			'sftp.uploadCancelled' => 'Upload cancelled',
			'sftp.preview' => 'Preview',
			'sftp.fileTooLarge' => ({required Object size}) => 'File too large to preview (${size}).\nUse Download instead.',
			'sftp.fileTooLargeToEdit' => ({required Object size}) => 'File too large to open in the editor (${size}).\nUse Download instead.',
			'sftp.imageDecodeError' => 'Could not decode image',
			'sftp.uploadAction' => 'Upload',
			'sftp.newFolder' => 'New folder',
			'sftp.newFile' => 'New file',
			'sftp.newFolderTitle' => 'New folder',
			'sftp.newFileTitle' => 'New file',
			'sftp.folderNameHint' => 'Folder name',
			'sftp.fileNameHint' => 'File name',
			'sftp.create' => 'Create',
			'sftp.createFailed' => ({required Object error}) => 'Create failed: ${error}',
			'sftp.overwriteTitle' => 'Replace file?',
			'sftp.overwriteConfirm' => ({required Object filename}) => '${filename} already exists on the server. Replace it?',
			'sftp.overwrite' => 'Replace',
			'sftp.sortBy' => 'Sort by',
			'sftp.sortName' => 'Name',
			'sftp.sortSize' => 'Size',
			'sftp.sortModified' => 'Date modified',
			'sftp.sortDirection' => 'Reverse order',
			'sftp.selectedCount' => ({required Object count}) => '${count} selected',
			'sftp.selectAll' => 'Select all',
			'sftp.copyPath' => 'Copy path',
			'sftp.pathCopied' => 'Path copied',
			'sftp.modified' => ({required Object date}) => 'Modified ${date}',
			'sftp.cancel' => 'Cancel',
			'sftp.cancelled' => 'Cancelled',
			'sftp.imageCounter' => ({required Object current, required Object total}) => '${current} of ${total}',
			'sftp.errors.notFound' => 'File or directory not found.',
			'sftp.errors.permissionDenied' => 'Permission denied. You don\'t have access to this file or directory.',
			'sftp.errors.failure' => 'Operation failed. The server may be low on disk space or the file may be locked.',
			'sftp.errors.connectionLost' => 'Connection to the server was lost.',
			'sftp.errors.diskFull' => 'Not enough disk space.',
			'sftp.errors.fileLocked' => 'File is locked or in use.',
			'sftp.errors.networkError' => 'Network error. Check your connection.',
			'sftp.errors.timeout' => 'Operation timed out.',
			'sftp.errors.localWriteError' => 'Failed to save file locally.',
			'sftp.errors.uploadReadError' => 'Failed to read local file for upload.',
			'sftp.errors.cancelled' => 'Operation cancelled.',
			'sftp.errors.generic' => ({required Object error}) => 'Operation failed: ${error}',
			'sftp.errors.noShell' => 'This server only allows file transfers, so it cannot copy files itself.',
			'sftp.checkingFile' => 'Checking file…',
			'sftp.openAsText' => 'Open as text anyway',
			'sftp.deleteFailedCount' => ({required Object count, required Object error}) => 'Could not delete ${count} items. ${error}',
			'sftp.savedToDownloads' => ({required Object name}) => 'Saved: ${name}',
			'sftp.savedFilesToDownloads' => ({required Object count, required Object folder}) => 'Saved ${count} files to ${folder}',
			'sftp.openDownload' => 'Open',
			'sftp.shareDownload' => 'Share',
			'sftp.noAppToOpen' => 'No app on this device can open it.',
			'sftp.couldNotShare' => 'Could not share it.',
			'sftp.downloadsFolder' => 'Downloads',
			'sftp.copyTo' => 'Copy to…',
			'sftp.moveTo' => 'Move to…',
			'sftp.copyItemsTo' => ({required Object count}) => 'Copy ${count} items to',
			'sftp.moveItemsTo' => ({required Object count}) => 'Move ${count} items to',
			'sftp.copyNameTo' => ({required Object name}) => 'Copy ${name} to',
			'sftp.moveNameTo' => ({required Object name}) => 'Move ${name} to',
			'sftp.copyHere' => 'Copy here',
			'sftp.moveHere' => 'Move here',
			'sftp.recentFolders' => 'Recent',
			'sftp.editPath' => 'Edit path',
			'sftp.moreActions' => 'More',
			'sftp.conflictTitle' => 'Already there',
			'sftp.conflictOne' => ({required Object name, required Object folder}) => '${name} already exists in ${folder}.',
			'sftp.conflictMany' => ({required Object count, required Object total, required Object folder}) => '${count} of ${total} items already exist in ${folder}.',
			'sftp.conflictSkip' => 'Skip',
			'sftp.conflictReplace' => 'Replace',
			'sftp.conflictKeepBoth' => 'Keep both',
			'sftp.copiedName' => ({required Object name}) => 'Copied ${name}',
			'sftp.movedName' => ({required Object name}) => 'Moved ${name}',
			'sftp.copiedCount' => ({required Object count}) => 'Copied ${count} items',
			'sftp.movedCount' => ({required Object count}) => 'Moved ${count} items',
			'sftp.skippedCount' => ({required Object count}) => '${count} skipped',
			'sftp.nothingTransferred' => 'Nothing changed - every item was skipped',
			'sftp.copyFailedCount' => ({required Object count, required Object error}) => 'Could not copy ${count} items. ${error}',
			'sftp.moveFailedCount' => ({required Object count, required Object error}) => 'Could not move ${count} items. ${error}',
			'sftp.queue.show' => 'Show transfers',
			'sftp.queue.hide' => 'Hide transfers',
			'sftp.queue.waiting' => 'Waiting',
			'sftp.queue.cancelling' => 'Cancelling…',
			'sftp.queue.cancelled' => 'Cancelled',
			'sftp.queue.copying' => 'Copying on the server',
			'sftp.queue.moving' => 'Moving on the server',
			'sftp.queue.position' => ({required Object position, required Object count}) => '${position} of ${count}',
			'sftp.queue.failedCount' => ({required Object count}) => '${count} failed - tap to see why',
			'sftp.queue.clearFinished' => 'Clear',
			'sftp.queue.items' => ({required Object count}) => '${count} items',
			'editor.unsavedTitle' => 'Unsaved changes',
			'editor.discardConfirm' => 'Discard changes?',
			'editor.savedSuccess' => 'File saved successfully',
			'editor.saveFailed' => ({required Object error}) => 'Failed to save: ${error}',
			'editor.lines' => ({required Object start, required Object end, required Object total}) => 'Lines ${start}-${end} of ${total}',
			'editor.scrollToLoadMore' => '· scroll to load more',
			'editor.error' => ({required Object error}) => 'Error: ${error}',
			'editor.toggleWordWrap' => 'Toggle word wrap',
			'editor.modifiedRemotelyTitle' => 'File changed on server',
			'editor.modifiedRemotelyBody' => 'This file was modified on the server since it was opened. Saving now will overwrite those changes.',
			'editor.saveAnyway' => 'Save anyway',
			'editor.find' => 'Find',
			'editor.findHint' => 'Find',
			'editor.replace' => 'Replace',
			'editor.replaceHint' => 'Replace with',
			'editor.replaceAll' => 'All',
			'editor.matchCount' => ({required Object current, required Object total}) => '${current}/${total}',
			'editor.noMatches' => 'None',
			'editor.matchCase' => 'Match case',
			'editor.regex' => 'Regular expression',
			'editor.previousMatch' => 'Previous match',
			'editor.nextMatch' => 'Next match',
			'editor.closeFind' => 'Close',
			'settings.title' => 'Settings',
			'settings.subtitle' => 'Configure app behavior and terminal preferences',
			'settings.appearance' => 'Appearance',
			'settings.themeMode' => 'Theme',
			'settings.themeModeSystem' => 'Follow device',
			'settings.themeModeLight' => 'Light',
			'settings.themeModeDark' => 'Dark',
			'settings.terminal' => 'Terminal',
			'settings.terminalAppearance' => 'Terminal appearance',
			'settings.terminalNavSubtitle' => 'Color scheme, font, cursor - with a live preview',
			'settings.terminalStyle' => 'Style',
			'settings.terminalBehavior' => 'Behavior',
			'settings.colorScheme' => 'Color scheme',
			'settings.font' => 'Font',
			'settings.fontSize' => 'Font size',
			'settings.lineHeight' => 'Line height',
			'settings.sidePadding' => 'Side padding',
			'settings.cursor' => 'Cursor',
			'settings.cursorBlock' => 'Block',
			'settings.cursorUnderline' => 'Underline',
			'settings.cursorBar' => 'Bar',
			'settings.cursorBlink' => 'Blink',
			'settings.predictiveEcho' => 'Predictive echo',
			'settings.predictiveEchoSubtitle' => 'Show typing instantly on slow connections',
			'settings.fastUpload' => 'Fast upload',
			'settings.fastUploadNavSubtitleTmp' => 'Uploads land in the server\'s temporary directory',
			'settings.fastUploadNavSubtitleCurrentDir' => 'Uploads land in the shell\'s current directory',
			'settings.fastUploadNavSubtitleAsk' => 'Asks where to put each upload',
			'settings.fastUploadSubtitle' => 'Upload a file into the open session',
			'settings.newBadge' => 'New',
			'settings.uploadDestination' => 'Upload destination',
			'settings.uploadDestinationTmp' => 'Temporary directory (scratch folder)',
			'settings.uploadDestinationCurrentDir' => 'Shell\'s current directory',
			'settings.uploadDestinationAsk' => 'Ask every time',
			'settings.uploadDestinationCurrentDirHint' => 'Where the shell is, with the agent',
			'settings.uploadDestinationAskHint' => 'Pick a folder for every upload',
			'settings.uploadDestinationTmpHint' => 'Timestamped names, nothing overwritten',
			'settings.uploadAutoPaste' => 'Paste the path straight away',
			'settings.uploadAutoPasteSubtitle' => 'Type the path at the cursor when done',
			'settings.connection' => 'Connection',
			'settings.remoteAgentToggle' => 'Termphin agent',
			'settings.remoteAgentToggleSubtitle' => 'Keeps sessions alive across disconnects',
			'settings.remoteAgentHowItWorks' => 'How the Termphin agent works',
			'settings.remoteAgentHowItWorksSubtitle' => 'What it runs on your server, and why it is safe',
			'settings.backgroundSuspended' => 'Sessions in the background',
			'settings.backgroundSuspendedSubtitle' => 'The agent keeps your shell running',
			'settings.agentSheetTitle' => 'Termphin agent',
			'settings.agentSheetIntro' => 'A small helper Termphin uploads to your server over SSH. It keeps your shell running there, so closing the app or losing signal doesn\'t end what you were doing.',
			'settings.agentSheetPointPlatforms' => 'Runs on Linux and macOS (x86_64 and arm64) and on Windows (x86_64).',
			'settings.agentSheetPointKeepsAlive' => 'Keeps each session\'s shell alive. After a short drop you get only what you missed; after a longer one, the screen as it is now.',
			'settings.agentSheetPointNoNetwork' => 'Opens no network port. The app reaches it through your SSH connection, over a socket only your user can open.',
			'settings.agentSheetPointNoRoot' => 'Runs as your user. No root, nothing installed system-wide, no service or cron entry.',
			'settings.agentSheetPointFiles' => 'Everything lives in ~/.cache/termphin/sessions (%LOCALAPPDATA%\\termphin\\sessions on Windows). Ending a session deletes its folder.',
			'settings.agentSheetPointMemory' => 'Recent output is kept in memory for picking up where you left off. A copy of the scrollback is saved in the session\'s folder, so it survives a server reboot.',
			'settings.agentSheetPointVerified' => 'Termphin checks the helper\'s SHA-256 checksum before uploading it, and checks the copy already on your server the same way.',
			'settings.agentSheetOpenSource' => 'It\'s open source: about 5,000 lines of Rust and one library for reading the screen (vt100), so you can read exactly what it does.',
			'settings.agentSheetRepoButton' => 'View the source on GitHub',
			'settings.agentSheetLinkFailed' => 'Could not open the link.',
			'settings.security' => 'Security',
			'settings.pinLock' => 'PIN lock',
			'settings.pinLockEnabled' => 'Enabled - asked on launch and when you come back',
			'settings.lockAfter' => 'Ask again',
			'settings.lockAfterImmediately' => 'Right away',
			'settings.lockAfter30s' => 'After 30 seconds',
			'settings.lockAfter1m' => 'After 1 minute',
			'settings.lockAfter5m' => 'After 5 minutes',
			'settings.pinLockDisabled' => 'Disabled',
			'settings.biometricUnlock' => 'Biometric unlock',
			'settings.biometricSubtitle' => 'Use fingerprint or face as alternative',
			'settings.biometricUnavailable' => 'Not available on this device',
			'settings.enablePinFirst' => 'Enable PIN lock first',
			'settings.changePin' => 'Change PIN',
			'settings.dataBackup' => 'Data & Backup',
			'settings.exportImportSubtitle' => 'Backup profiles, SSH keys and settings to JSON',
			'settings.groupsSubtitle' => 'Rename, recolour and reorder your groups',
			'settings.organization' => 'Organization',
			'settings.analytics' => 'Analytics',
			'settings.analyticsToggle' => 'Share usage analytics',
			'settings.analyticsToggleSubtitle' => 'Anonymous usage and crash reports',
			'settings.terminalControls' => 'On-screen controls',
			'settings.keyToolbar' => 'Key toolbar',
			'settings.keyToolbarSubtitle' => 'Esc, Tab, Ctrl, arrows above the keyboard',
			'settings.toolbarLayout' => 'Toolbar layout',
			'settings.actionDock' => 'Action dock',
			'settings.actionDockSwitchSubtitle' => 'Floating button over the terminal with quick actions',
			'settings.tabsAtBottom' => 'Tabs at the bottom',
			'settings.tabsAtBottomSubtitle' => 'Above the key toolbar, within reach of your thumb',
			'settings.commandSuggestions' => 'Autocomplete',
			'settings.commandSuggestionsSubtitle' => 'Suggests commands and paths as you type',
			'settings.howItWorks' => 'How it works',
			'settings.actionDockLayout' => 'Dock actions',
			'settings.actionDockSubtitle' => 'Drag to move, − to hide, + to restore',
			'settings.actionDockPreview' => 'Dock',
			'settings.actionDockHiddenLabel' => 'Hidden',
			'settings.actionDockAllHidden' => 'Every tile is hidden. Tap + below or drag one here.',
			'settings.actionDockNoneHidden' => 'Nothing hidden - drag a tile here to hide it.',
			'settings.actionDockHide' => ({required Object name}) => 'Hide ${name}',
			'settings.actionDockShow' => ({required Object name}) => 'Add ${name} to the dock',
			'settings.actionDockReset' => 'Reset dock',
			'settings.actionDockResetTitle' => 'Reset the dock?',
			'settings.actionDockResetMessage' => 'The default actions come back, in the default order.',
			'settings.actionDockResetDone' => 'Dock reset',
			'settings.disableLockTitle' => 'Disable lock?',
			'settings.disableLockContent' => 'PIN and biometric lock will be removed.',
			'settings.layoutLabel' => ({required Object number}) => 'Layout ${number}',
			'settings.toolbarGrid' => 'Grid',
			'settings.toolbarColumns' => 'Columns',
			'settings.toolbarRows' => 'Rows',
			'settings.toolbarPages' => 'Pages',
			'settings.toolbarButtonHeight' => 'Button height',
			'settings.toolbarAddCustom' => 'New key',
			'settings.toolbarSlotRemove' => 'Remove key',
			'settings.toolbarNoFreeSlot' => 'No free slot - remove a key first.',
			'settings.toolbarTapToPlace' => 'Tap a slot, then a key to fill it',
			'settings.toolbarSlotSelected' => 'Tap a key below to fill this slot',
			'settings.toolbarResizeTitle' => 'Smaller grid',
			'settings.toolbarResizeMessage' => ({required Object count}) => '${count} keys do not fit the new grid and will be taken off the toolbar.',
			'settings.toolbarResizeConfirm' => 'Shrink anyway',
			'settings.anonymize' => 'Anonymize',
			'settings.anonymizeSubtitle' => 'Hide hosts and usernames for screenshots',
			'settings.downloadFolder' => 'Download folder',
			'settings.downloadFolderDefault' => 'System Downloads folder',
			'settings.downloadFolderReset' => 'Use system Downloads',
			'settings.downloadFolderUnavailable' => 'That folder is no longer available. Pick it again or fall back to Downloads.',
			'settings.privacy' => 'Privacy',
			'settings.sftp' => 'SFTP',
			'settings.textEditor' => 'Text editor',
			'settings.textEditorSubtitle' => ({required Object font, required Object size}) => '${font}, ${size} pt',
			'settings.editorStyle' => 'Style',
			'settings.editorPinchHint' => 'Pinch in the editor to resize text',
			'settings.editorLineNumbers' => 'Line numbers',
			'settings.editorWordWrap' => 'Wrap long lines',
			'settings.editorWordWrapSubtitle' => 'Off, a long line scrolls sideways instead.',
			'settings.batteryUnrestricted' => 'Unrestricted battery use',
			'settings.batteryUnrestrictedSubtitle' => 'Keeps sessions connected in the background',
			'settings.notificationsPermission' => 'Notifications',
			'settings.notificationsPermissionSubtitle' => 'For background sessions and downloads',
			'settings.localNetworkPermission' => 'Local network access',
			'settings.localNetworkPermissionSubtitle' => 'Needed to reach machines on your network',
			'settings.feedback' => 'Feedback',
			'settings.sendFeedback' => 'Send feedback',
			'settings.sendFeedbackSubtitle' => 'Ideas, requests, anything you\'d like to see',
			'settings.reportBug' => 'Report a bug',
			'settings.reportBugSubtitle' => 'Something broke? Tell us what happened',
			'settings.issueTracker' => 'Issue tracker',
			'settings.issueTrackerSubtitle' => 'Open bugs and ideas, out in the open on GitHub',
			'settings.openSource' => 'Open source',
			'settings.starOnGitHub' => 'Star on GitHub',
			'settings.starOnGitHubSubtitle' => 'Helps others find Termphin',
			'settings.contribute' => 'Contribute',
			'settings.contributeSubtitle' => 'Fix a bug or build a feature, here is where to start',
			'settings.sourceLicense' => 'License',
			'settings.sourceLicenseSubtitle' => 'GPL-3.0: read the code, build it, change it',
			'settings.manual' => 'Manual',
			'settings.manualSubtitle' => 'How to use Termphin, from first connection onwards',
			'settings.errorReports' => 'Error reports',
			'settings.errorReportsSubtitle' => 'Errors Termphin ran into, to send with a bug report',
			'settings.feedbackEmailFailed' => 'Could not open your mail app.',
			'settings.about' => 'About',
			'settings.aboutTagline' => 'SSH client',
			'settings.aboutVersion' => ({required Object version}) => 'Version ${version}',
			'settings.releaseNotes' => 'Release notes',
			'settings.releaseNotesSubtitle' => 'What\'s changed across every version',
			'settings.rateApp' => 'Rate Termphin',
			'settings.rateAppSubtitle' => 'Leave a review on Google Play',
			'settings.rateAppSubtitleIos' => 'Leave a review on the App Store',
			'settings.rateAppFailed' => 'Could not open Google Play.',
			'settings.rateAppFailedIos' => 'Could not open the App Store.',
			'settings.downloadFolderIos' => 'Files app (On My iPhone / Termphin)',
			'settings.licenses' => 'Open source licenses',
			'settings.licensesSubtitle' => 'The packages Termphin is built on, and their terms',
			'settings.privacyPolicy' => 'Privacy policy',
			'settings.privacyPolicySubtitle' => 'What is collected, and what never leaves this device',
			'settings.terms' => 'Terms of service',
			_ => null,
		} ?? switch (path) {
			'settings.termsSubtitle' => 'The terms you agree to by using Termphin',
			'settings.legalLinkFailed' => 'Could not open your browser.',
			'settings.knownHosts' => 'Known hosts',
			'settings.knownHostsSubtitle' => 'Host keys this device trusts',
			'settings.knownHostsEmpty' => 'No host keys pinned',
			'settings.knownHostsEmptyBody' => 'A server\'s key is pinned here the first time you accept it while connecting.',
			'settings.knownHostsAddedAt' => ({required Object date}) => 'Pinned ${date}',
			'settings.knownHostsForget' => 'Forget',
			'settings.knownHostsForgetTitle' => 'Forget this host key?',
			'settings.knownHostsForgetBody' => ({required Object host}) => 'The next connection to ${host} will ask you to accept its key again.',
			'settings.knownHostsForgotten' => 'Host key forgotten.',
			'settings.toolbarProfiles' => 'Toolbar layouts',
			'settings.toolbarProfilesSubtitle' => 'Switch between key layouts',
			'settings.toolbarProfileDefault' => 'Default',
			'settings.toolbarProfileActive' => 'In use',
			'settings.toolbarProfileNew' => 'New layout',
			'settings.toolbarProfileNewName' => ({required Object number}) => 'Layout ${number}',
			'settings.toolbarProfileRenameTitle' => 'Rename layout',
			'settings.toolbarProfileNameLabel' => 'Layout name',
			'settings.toolbarProfileDeleteTitle' => 'Delete this layout?',
			'settings.toolbarProfileDeleteConfirm' => ({required Object name}) => '“${name}” and the keys arranged in it are gone.',
			'settings.toolbarProfileDeleteLast' => 'This is the only layout left - the toolbar needs one.',
			'settings.toolbarProfileSummary' => ({required Object count, required Object columns, required Object rows, required Object pages}) => '${count} keys · ${columns}x${rows}, ${pages} page(s)',
			'settings.toolbarGridSize' => 'Grid size',
			'settings.toolbarReset' => 'Reset layout',
			'settings.toolbarResetTitle' => 'Reset this layout?',
			'settings.toolbarResetMessage' => 'Every slot goes back to the default arrangement.',
			'settings.toolbarResetDone' => 'Layout reset',
			'settings.toolbarKeyRemoved' => ({required Object name}) => '“${name}” removed',
			'settings.toolbarEmptySlot' => 'Empty slot',
			'settings.toolbarPageOf' => ({required Object number, required Object total}) => 'Page ${number} of ${total}',
			'settings.toolbarKeyHeld' => 'Tap another slot to move it',
			'settings.editorTabWidth' => 'Tab width',
			'settings.sftpShowHidden' => 'Show hidden files',
			'settings.sftpShowHiddenSubtitle' => 'Names that start with a dot, like .ssh and .bashrc.',
			'settings.sftpFollowTerminal' => 'Follow the terminal',
			'settings.sftpFollowTerminalSubtitle' => 'Open in the shell\'s current folder',
			'exportScreen.title' => 'Export & Import',
			'exportScreen.exportInstructions' => 'Choose what to include in the backup file.',
			'exportScreen.saveDialogTitle' => 'Save backup',
			'exportScreen.includeSshProfiles' => 'SSH profiles',
			'exportScreen.includeSshProfilesSubtitle' => 'Host, port, username, auth method',
			'exportScreen.includePasswords' => 'Include passwords',
			'exportScreen.includePasswordsSubtitle' => 'Stored plaintext passwords in profiles',
			'exportScreen.includeInlineKeys' => 'Include inline private keys',
			'exportScreen.includeInlineKeysSubtitle' => 'Private keys pasted directly into profiles',
			'exportScreen.includeSshKeys' => 'SSH keys',
			'exportScreen.includeSshKeysSubtitle' => 'All keys from the key manager (incl. private)',
			'exportScreen.includeSnippets' => 'Snippets',
			'exportScreen.includeSnippetsSubtitle' => 'Saved commands, their tags and defaults',
			'exportScreen.includeKnownHosts' => 'Known hosts',
			'exportScreen.includeKnownHostsSubtitle' => 'Pinned server host keys',
			'exportScreen.includeTerminalSettings' => 'Terminal settings',
			'exportScreen.includeTerminalSettingsSubtitle' => 'Color scheme, font size, cursor style',
			'exportScreen.includeAppPreferences' => 'App preferences',
			'exportScreen.includeAppPreferencesSubtitle' => 'Toolbar, action dock, theme and view options',
			'exportScreen.sensitiveWarning' => 'The backup will contain passwords and private keys. Protect it with a passphrase, or keep the file secure and delete it after use.',
			'exportScreen.encryptTitle' => 'Protect with a passphrase',
			'exportScreen.encryptSubtitle' => 'Encrypts the file. Without the passphrase it cannot be restored - there is no recovery.',
			'exportScreen.passphraseLabel' => 'Passphrase',
			'exportScreen.passphraseConfirmLabel' => 'Repeat passphrase',
			'exportScreen.passphraseTooShort' => 'At least 8 characters.',
			'exportScreen.passphraseMismatch' => 'The two passphrases do not match.',
			'exportScreen.exportButton' => 'Export backup',
			'exportScreen.exporting' => 'Exporting…',
			'exportScreen.exportSuccess' => 'Backup saved',
			'exportScreen.exportNothingSelected' => 'Pick at least one section to export.',
			'exportScreen.confirmPlaintextTitle' => 'Export secrets unprotected?',
			'exportScreen.confirmPlaintextBody' => 'This file will hold passwords and private keys in plain text. Anything that can read the file can use them.',
			'exportScreen.confirmPlaintextContinue' => 'Export anyway',
			'exportScreen.lastBackup' => ({required Object date}) => 'Last backup ${date}',
			'exportScreen.lastBackupNever' => 'No backup taken from this device yet.',
			'exportScreen.estimatedContents' => ({required Object summary}) => 'About to write: ${summary}',
			'exportScreen.importInstructions' => 'Restore from a backup file. You choose what comes across and what happens to entries already on this device.',
			'exportScreen.selectFile' => 'Select backup file',
			'exportScreen.reading' => 'Reading file…',
			'exportScreen.importing' => 'Importing…',
			'exportScreen.importDialogTitle' => 'Import backup',
			'exportScreen.exportedAt' => ({required Object date}) => 'Exported ${date}',
			'exportScreen.whatToImport' => 'What to import',
			'exportScreen.sectionProfiles' => 'SSH profiles',
			'exportScreen.sectionSshKeys' => 'SSH keys',
			'exportScreen.sectionSnippets' => 'Snippets',
			'exportScreen.sectionKnownHosts' => 'Known hosts',
			'exportScreen.showItems' => 'Choose individually',
			'exportScreen.hideItems' => 'Hide entries',
			'exportScreen.selectAll' => 'All',
			'exportScreen.selectNone' => 'None',
			'exportScreen.alreadyHere' => 'Already here',
			'exportScreen.conflictsTitle' => 'Entries already on this device',
			'exportScreen.conflictsSkip' => 'Keep mine',
			'exportScreen.conflictsSkipSubtitle' => 'Leave the local entry alone and skip the one in the file.',
			'exportScreen.conflictsReplace' => 'Overwrite',
			'exportScreen.conflictsReplaceSubtitle' => 'Replace the local entry with the one in the file.',
			'exportScreen.conflictSummary' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} entry in this file is already on the device.', other: '${n} entries in this file are already on the device.', ), 
			'exportScreen.importSecretsWarning' => 'This backup carries passwords and private keys. They will be stored on this device.',
			'exportScreen.profileCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} profile', other: '${n} profiles', ), 
			'exportScreen.keyCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} SSH key', other: '${n} SSH keys', ), 
			'exportScreen.snippetCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} snippet', other: '${n} snippets', ), 
			'exportScreen.knownHostCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} known host', other: '${n} known hosts', ), 
			'exportScreen.passphrasePromptTitle' => 'This backup is encrypted',
			'exportScreen.passphrasePromptBody' => 'Enter the passphrase it was exported with.',
			'exportScreen.passphraseWrong' => 'Wrong passphrase.',
			'exportScreen.unlock' => 'Unlock',
			'exportScreen.invalidFile' => 'That file is not a Termphin backup.',
			'exportScreen.unsupportedVersion' => 'This backup was written by a newer version of Termphin. Update the app and try again.',
			'exportScreen.emptyBackup' => 'This backup holds nothing to import.',
			'exportScreen.importNothingSelected' => 'Pick at least one thing to import.',
			'exportScreen.importSuccess' => ({required Object added, required Object replaced, required Object skipped}) => 'Imported ${added}, replaced ${replaced}, skipped ${skipped}',
			'exportScreen.importNothingChanged' => 'Nothing changed - everything in the file was already here.',
			'exportScreen.importMissingKeys' => ({required Object names}) => 'Profiles left without their SSH key: ${names}',
			'exportScreen.importMissingJumpHosts' => ({required Object names}) => 'Profiles left without their jump host: ${names}',
			'exportScreen.exportSection' => 'Export',
			'exportScreen.importSection' => 'Import',
			'exportScreen.hubExportSubtitle' => 'Write a backup file of your profiles, keys and settings.',
			'exportScreen.hubImportSubtitle' => 'Restore from a backup file you exported earlier.',
			'exportScreen.chooseAnotherFile' => 'Choose another file',
			'exportScreen.noFileChosen' => 'Pick a backup file to see what is in it.',
			'exportScreen.exportFailed' => ({required Object error}) => 'Export failed: ${error}',
			'exportScreen.importFailed' => ({required Object error}) => 'Import failed: ${error}',
			'exportScreen.failed' => ({required Object error}) => 'Failed: ${error}',
			'connection.connecting' => 'Connecting...',
			'connection.allowLocalNetwork' => 'Allow local network',
			'connection.openLocalNetworkSettings' => 'Open settings',
			'connection.connected' => 'Connected',
			'connection.error' => 'Error',
			'connection.disconnected' => 'Disconnected',
			'connection.reconnecting' => ({required Object attempt}) => 'Reconnecting, attempt ${attempt}…',
			'connection.reconnectingIn' => ({required Object seconds}) => 'Retrying in ${seconds}s…',
			'connection.waitingForNetwork' => 'Waiting for a network…',
			'connection.restoringHistory' => 'Restoring history…',
			'connection.logEmpty' => 'No connection log yet',
			'connection.viewLog' => 'Connection log',
			'connection.quality.queued' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} key waiting to send', other: '${n} keys waiting to send', ), 
			'connection.quality.unresponsive' => ({required Object seconds}) => 'No reply for ${seconds}s',
			'connection.quality.slow' => ({required Object ms}) => 'Slow connection · ${ms} ms',
			'connection.quality.openDetails' => 'Connection log',
			'connection.errors.hostUnreachable' => 'The server did not answer. Check the address and port.',
			'connection.errors.localNetworkBlocked' => 'This machine is on the network you\'re connected to, which Termphin doesn\'t have permission to reach yet.',
			'connection.errors.localNetworkUnverified' => 'Nothing answered at this address. It is on the network you\'re connected to, so either the machine is off or Termphin does not have permission to reach it.',
			'connection.errors.timeout' => 'The server stopped answering.',
			'connection.errors.authFailedPassword' => 'Wrong username or password.',
			'connection.errors.authFailedKey' => 'The server did not accept this key. Check the username, and that the key is authorised on the server.',
			'connection.errors.hostKeyRejected' => 'You did not accept the server\'s key. Nothing was sent.',
			'connection.errors.hostKeyMismatch' => 'This server\'s key has changed. Remove the old one in Settings → Known hosts if that was expected.',
			'connection.errors.keyMissing' => 'This profile\'s key is gone from the key manager.',
			'connection.errors.keyPassphrase' => 'Wrong passphrase for this key.',
			'connection.errors.keyInvalid' => 'This key could not be read.',
			'connection.errors.jumpHost' => 'The jump host connection failed.',
			'connection.errors.jumpHostConfig' => 'This profile\'s jump host is not set up right.',
			'connectionLog.trying' => ({required Object host, required Object port}) => 'Trying ${host}:${port}',
			'connectionLog.connectingThrough' => ({required Object name}) => 'Connecting through ${name}',
			'connectionLog.reached' => ({required Object name}) => 'Reached ${name}',
			'connectionLog.connectingTo' => ({required Object host, required Object port}) => 'Connecting to ${host}:${port}',
			'connectionLog.authSuccessful' => 'Authentication successful',
			'connectionLog.checkingAgent' => 'Checking Termphin agent',
			'connectionLog.agentUnavailable' => ({required Object error}) => 'Termphin agent unavailable: ${error}',
			'connectionLog.openingSession' => 'Opening terminal session',
			'connectionLog.sessionReady' => 'Terminal session ready',
			'connectionLog.connectionLost' => 'Connection lost',
			'groups.title' => 'Groups',
			'groups.subtitle' => 'Organize your machines, keys and snippets into groups',
			'groups.general' => 'General',
			'groups.newGroup' => 'New group',
			'groups.editGroup' => 'Edit group',
			'groups.createGroup' => 'Create group',
			'groups.groupName' => 'Group name',
			'groups.groupNameHint' => 'e.g. Production',
			'groups.groupTitle' => 'Group',
			'groups.selectGroup' => 'Select group',
			'groups.allGroups' => 'All',
			'groups.colorLabel' => 'Colour',
			'groups.manageGroups' => 'Manage groups',
			'groups.defaultBadge' => 'Default',
			'groups.defaultNameLocked' => 'General is the fallback group. It cannot be renamed.',
			'groups.deleteTitle' => 'Delete group?',
			'groups.deleteConfirm' => ({required Object name}) => 'Are you sure you want to delete "${name}"? Machines, keys, and snippets in this group will be moved to General.',
			'groups.renameTitle' => 'Rename group',
			'groups.empty' => 'No groups yet',
			'groups.countMachines' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${count} machine', other: '${count} machines', ), 
			'groups.countKeys' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${count} key', other: '${count} keys', ), 
			'groups.countSnippets' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${count} snippet', other: '${count} snippets', ), 
			'groups.groupEmpty' => 'Empty',
			'groups.alreadyExists' => 'A group with this name already exists.',
			'groups.noColour' => 'No colour',
			'groups.otherGroups' => 'Other groups',
			'groups.reorderHint' => 'Hold a group and drag it to change the order.',
			'portForwarding.title' => 'Port Forwarding',
			'portForwarding.addRule' => 'Add Rule',
			'portForwarding.editRule' => 'Edit Rule',
			'portForwarding.localForward' => 'Local',
			'portForwarding.remoteForward' => 'Remote',
			'portForwarding.localForwardDescription' => 'Opens a port on your device. Traffic is tunneled to a service on the server.',
			'portForwarding.remoteForwardDescription' => 'Opens a port on the SSH server. Incoming traffic is forwarded to a service on your device.',
			'portForwarding.modeQuestion' => 'Where should the listening port be opened?',
			'portForwarding.modeOptionDevice' => 'On this device',
			'portForwarding.modeOptionDeviceSubtitle' => 'Access a remote service locally',
			'portForwarding.modeOptionServer' => 'On the SSH server',
			'portForwarding.modeOptionServerSubtitle' => 'Expose a local service remotely',
			'portForwarding.modeSection' => 'Direction',
			'portForwarding.detailsSection' => 'Details',
			'portForwarding.previewSection' => 'Route',
			'portForwarding.localPort' => 'Local Port',
			'portForwarding.remoteHost' => 'Target Host',
			'portForwarding.remotePort' => 'Target Port',
			'portForwarding.localPortHint' => 'Port on this device',
			'portForwarding.remoteHostHint' => 'Address visible from the SSH server',
			'portForwarding.remotePortHint' => 'Port on the target host',
			'portForwarding.remotePortLabel' => 'Server Port',
			'portForwarding.remotePortLabelHint' => 'Port opened on the server',
			'portForwarding.localHostLabel' => 'Target Host',
			'portForwarding.localHostLabelHint' => 'Address of the service on this device',
			'portForwarding.localPortTargetLabel' => 'Target Port',
			'portForwarding.localPortTargetHint' => 'Port of the local service to expose',
			'portForwarding.name' => 'Name',
			'portForwarding.statusError' => 'Error',
			'portForwarding.statusStarting' => 'Starting…',
			'portForwarding.manageTunnels' => 'Manage tunnels',
			'portForwarding.profileRules' => 'Profile Rules',
			'portForwarding.adhocTunnels' => 'Ad-hoc Tunnels',
			'portForwarding.addTunnel' => 'Add Tunnel',
			'portForwarding.noRulesYet' => 'No forwarding rules yet',
			'portForwarding.server' => 'Server',
			'portForwarding.arrowDevice' => 'This device',
			'portForwarding.arrowServer' => 'Server',
			'notifications.connected' => 'connected',
			'notifications.reconnecting' => 'reconnecting…',
			'notifications.transferDoneTitle' => 'Download finished',
			'notifications.transferDoneOne' => ({required Object name}) => '${name} saved',
			'notifications.transferDoneMany' => ({required Object count, required Object folder}) => '${count} files saved to ${folder}',
			'notifications.transferFailedTitle' => 'Download failed',
			'notifications.transferFailedBody' => ({required Object name}) => '${name} did not finish.',
			'notifications.sessionDroppedTitle' => 'Session disconnected',
			'notifications.sessionDroppedBody' => ({required Object name}) => '${name} lost its connection.',
			'notifications.sessionChannelName' => 'Session alerts',
			'notifications.sessionChannelDescription' => 'When a session loses its connection and cannot get it back.',
			'notifications.downloadProgressChannelName' => 'Download progress',
			'notifications.downloadProgressChannelDescription' => 'Shown while a file is being downloaded.',
			'notifications.downloadCompleteChannelName' => 'Download complete',
			'notifications.downloadCompleteChannelDescription' => 'Shown when a download has finished.',
			'notifications.downloadSaved' => 'Saved',
			'linkPreview.loading' => 'Loading preview…',
			'linkPreview.copyLink' => 'Copy Link',
			'linkPreview.noPreview' => 'No preview available',
			'session.rebootRestored' => 'The remote shell was restarted - reattached in the same directory, previous shell state is gone.',
			'session.offlineTitle' => 'Session detached',
			'session.offlineBody' => 'The session is still running on the server. Re-attach to pick up where you left off.',
			'session.attach' => 'Re-attach',
			'session.detach' => 'Detach (keep running)',
			'session.menuSection' => 'Session',
			'session.latency' => ({required Object ms}) => '${ms} ms',
			'session.endSession' => 'End session',
			'session.endSessionTitle' => 'End session?',
			'session.endSessionConfirm' => ({required Object host}) => 'This kills the persistent session on ${host}. Anything running in it stops.',
			'session.endSessionFailed' => ({required Object host, required Object error}) => 'Couldn\'t end the session on ${host}: ${error}',
			'session.serverSessions' => 'Sessions on server',
			'session.noServerSessions' => 'No detached sessions on this server.',
			'session.serverSessionsFailed' => ({required Object error}) => 'Could not list sessions: ${error}',
			'session.loadSessions' => 'Load sessions',
			'session.loadedSessions' => ({required Object count}) => 'Loaded ${count} session(s).',
			'session.loadGroupSessions' => 'Load sessions for every machine',
			'session.loadedGroupSessions' => ({required Object count, required Object machines}) => 'Loaded ${count} session(s) from ${machines} machine(s).',
			'session.loadedGroupSessionsPartial' => ({required Object count, required Object failed}) => 'Loaded ${count} session(s). ${failed} machine(s) could not be reached.',
			'session.noGroupServerSessions' => 'No detached sessions on these servers.',
			'session.stopLoading' => 'Stop',
			'session.loadStopped' => ({required Object count}) => 'Stopped. Loaded ${count} session(s).',
			'session.groupSessionsFailed' => ({required Object failed}) => 'Could not reach ${failed} machine(s).',
			'session.killSessionTitle' => 'Kill session?',
			'session.killSessionConfirm' => ({required Object name}) => 'Session ${name} and everything running in it will be terminated.',
			'session.kill' => 'Kill',
			'session.killed' => ({required Object name}) => 'Session ${name} killed.',
			'session.agentUpdateTooltip' => 'Update Termphin agent',
			'session.agentUpdating' => 'Updating Termphin agent…',
			'session.agentUpdated' => ({required Object version}) => 'Termphin agent updated to ${version}.',
			'session.agentUpdateFailed' => ({required Object error}) => 'Could not update Termphin agent: ${error}',
			'session.detached' => 'Detached',
			'session.restoreDock' => ({required Object target}) => 'Ready to restore · ${target}',
			'session.connected' => 'Connected',
			'session.rename' => 'Rename session',
			'session.renameTitle' => 'Rename session',
			'session.renameLabel' => 'Session name',
			'session.renameNameEmpty' => 'Name cannot be empty',
			'session.renameNameInvalid' => 'Use only letters, numbers, \'-\' and \'_\'',
			'session.renameFailed' => ({required Object error}) => 'Rename failed: ${error}',
			'session.renamed' => ({required Object name}) => 'Session renamed to ${name}.',
			'session.unreachableTitle' => 'Couldn\'t reach the session',
			'session.unreachableBody' => ({required Object error}) => '${error}\n\nIf the server was reset or lost power, the session is probably gone for good. Forget it on this device?',
			'session.forget' => 'Forget',
			'session.loadingServerSessions' => 'Loading sessions from the server…',
			'session.checkedJustNow' => 'Checked just now',
			'session.checkedMinutesAgo' => ({required Object minutes}) => 'Checked ${minutes}m ago',
			'session.checkedHoursAgo' => ({required Object hours}) => 'Checked ${hours}h ago',
			'session.checkedDaysAgo' => ({required Object days}) => 'Checked ${days}d ago',
			'snippets.title' => 'Snippets',
			'snippets.subtitle' => 'Save and manage your commands and scripts',
			'snippets.allSnippets' => 'All snippets',
			'snippets.newTitle' => 'New snippet',
			'snippets.editTitle' => 'Edit snippet',
			'snippets.nameHint' => 'Name',
			'snippets.commandHint' => 'Command',
			'snippets.placeholderHint' => 'Wrap a word in double curly braces to ask for it each time.',
			'snippets.argumentsTitle' => 'Arguments',
			'snippets.argumentsHint' => 'A default fills the field in for you when the snippet runs. Leave one blank to be asked from scratch.',
			'snippets.deleteTitle' => 'Delete snippet?',
			'snippets.deleteConfirm' => ({required Object name}) => 'Are you sure you want to delete "${name}"?',
			'snippets.empty' => 'No snippets yet\nTap + to add one',
			'snippets.emptyTitle' => 'No snippets yet',
			'snippets.emptySubtitle' => 'Tap + to save a command or script.',
			'snippets.copyCommand' => 'Copy command',
			'snippets.commandCopied' => 'Command copied.',
			'snippets.run' => 'Run',
			'snippets.runTitle' => 'Run snippet',
			'snippets.pickMachines' => 'Choose machines',
			'snippets.pickMachinesEmpty' => 'Add a machine first to run snippets on it.',
			'snippets.runNow' => ({required Object count}) => 'Run on ${count} machine(s)',
			'snippets.runsTitle' => 'Runs',
			'snippets.runsEmpty' => 'No runs yet',
			'snippets.runsEmptySubtitle' => 'Run a snippet on one or more machines to see its progress here.',
			'snippets.runPending' => 'Waiting',
			'snippets.runConnecting' => 'Connecting',
			'snippets.runRunning' => 'Running',
			'snippets.runSucceeded' => 'Done',
			'snippets.runFailed' => ({required Object code}) => 'Exit ${code}',
			'snippets.runError' => 'Failed to start',
			'snippets.runSummary' => ({required Object done, required Object total}) => '${done} of ${total} finished',
			'snippets.runForget' => 'Clear',
			'snippets.enterToRun' => 'Enter to run',
			'snippets.runStageFailed' => ({required Object error}) => 'Could not send the snippet: ${error}',
			'snippets.duplicateSuffix' => ({required Object name}) => '${name} copy',
			'snippets.duplicated' => ({required Object name}) => 'Copied to “${name}”.',
			'snippets.deleted' => ({required Object name}) => 'Deleted “${name}”.',
			'snippets.moreActions' => 'More actions',
			'snippets.runsSubtitle' => 'What your snippets did, and what each machine said back.',
			'snippets.runsClearAllTitle' => 'Clear run history?',
			'snippets.runsClearAllConfirm' => 'Every run listed here is forgotten. Nothing running is stopped.',
			'snippets.runForgetTitle' => 'Clear this run?',
			'snippets.runForgetConfirm' => ({required Object name}) => '“${name}” and everything it printed is forgotten.',
			'snippets.runAgain' => 'Run again',
			'snippets.copyOutput' => 'Copy output',
			'snippets.outputCopied' => 'Output copied.',
			'snippets.runNoOutput' => 'Nothing printed yet.',
			'snippets.pickMachinesSelected' => ({required Object count, required Object total}) => '${count} of ${total} selected',
			'snippets.commandSection' => 'Command',
			'snippets.runArgumentsHint' => 'Filled in once, for every machine in this run.',
			'toolbar.searchHint' => 'Search keys…',
			'toolbar.noResults' => 'No keys match',
			'toolbar.categoryNavigation' => 'Navigation',
			'toolbar.categoryEditing' => 'Editing',
			'toolbar.categoryModifiers' => 'Modifiers',
			'toolbar.categoryFunction' => 'Function keys',
			'toolbar.categorySymbols' => 'Symbols',
			'toolbar.categoryCustom' => 'Custom',
			'toolbar.customTextHint' => 'Text to send',
			'toolbar.goToPage' => ({required Object number}) => 'Go to page ${number}',
			'toolbar.quickSettings' => 'Quick settings',
			'toolbar.quickTabToolbar' => 'Toolbar',
			'toolbar.quickTabAppearance' => 'Appearance',
			'toolbar.allTerminalSettings' => 'All terminal settings',
			'toolbar.importTitle' => 'Add toolbar layout',
			'toolbar.importUnnamed' => 'Shared layout',
			'toolbar.importTextKeys' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '1 key types text', other: '${n} keys type text', ), 
			'toolbar.importPressEnter' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '1 presses Enter', other: '${n} press Enter', ), 
			'toolbar.importEnterNote' => 'A key marked Enter runs its command the moment it is tapped.',
			'toolbar.importEnter' => 'Enter',
			'toolbar.importDropped' => ({required Object count}) => 'Left out ${count} keys this version does not have.',
			'toolbar.importAdd' => 'Add',
			'toolbar.importAddAndUse' => 'Add and use',
			'toolbar.importAdded' => 'Layout added',
			'toolbar.importInvalid' => 'This toolbar link could not be read.',
			'toolbar.manageLayouts' => 'Manage layouts',
			'toolbar.emptyLayout' => 'No keys yet',
			'toolbar.escape' => 'Escape',
			'toolbar.tab' => 'Tab',
			'toolbar.backTab' => 'Back tab',
			'toolbar.home' => 'Home',
			'toolbar.end' => 'End',
			'toolbar.control' => 'Control',
			'toolbar.alt' => 'Alt',
			'toolbar.shift' => 'Shift',
			'toolbar.enter' => 'Enter',
			'toolbar.delete' => 'Delete',
			'toolbar.backspace' => 'Backspace',
			'toolbar.pageUp' => 'Page up',
			'toolbar.pageDown' => 'Page down',
			'toolbar.insert' => 'Insert',
			'toolbar.space' => 'Space',
			'toolbar.arrowLeft' => 'Arrow left',
			'toolbar.arrowUp' => 'Arrow up',
			'toolbar.arrowDown' => 'Arrow down',
			'toolbar.arrowRight' => 'Arrow right',
			'toolbar.hideKeyboard' => 'Hide keyboard',
			'toolbar.functionKey' => ({required Object number}) => 'F${number}',
			'toolbar.ctrlCombo' => ({required Object key}) => 'Control ${key}',
			'toolbar.symbol' => ({required Object char}) => 'Symbol ${char}',
			'toolbar.sendText' => ({required Object text}) => 'Send text ${text}',
			'toolbar.runSnippet' => 'Run snippet',
			'toolbar.snippetMissing' => 'Snippet no longer exists.',
			'toolbar.newCustomKey' => 'New key',
			'toolbar.editCustomKey' => 'Edit key',
			'toolbar.customTextHelp' => 'Sent to the terminal exactly as typed here.',
			'toolbar.customAppendEnter' => 'Press Enter after',
			'toolbar.customAppendEnterSubtitle' => 'Runs the text instead of only typing it',
			'toolbar.comboMode' => 'Key combo',
			'toolbar.textMode' => 'Text',
			'toolbar.comboHint' => 'Tap the box and press a key - whatever the keyboard sends becomes the key.',
			'toolbar.comboAwaitingKey' => 'press a key',
			'toolbar.comboSpecialKeys' => 'Keys the keyboard cannot send',
			'actionDock.uploadFile' => 'Fast upload',
			'actionDock.uploadNameTo' => ({required Object name}) => 'Upload ${name} to',
			'actionDock.uploadItemsTo' => ({required Object count}) => 'Upload ${count} files to',
			'actionDock.uploadHere' => 'Upload here',
			'actionDock.copyPath' => 'Copy path',
			'actionDock.copyPathRequiresAgent' => 'Copying the current path needs a Termphin agent session - this connection doesn\'t have one.',
			'actionDock.copyPathUnknown' => 'Couldn\'t find the current directory.',
			'actionDock.uploaded' => ({required Object path}) => 'Uploaded to ${path}',
			'actionDock.uploadedMany' => ({required Object count, required Object path}) => 'Uploaded ${count} files to ${path}',
			'actionDock.pasteUploadedPath' => 'Paste path',
			'actionDock.paste' => 'Paste',
			'actionDock.search' => 'Search',
			'share.uploadTo' => 'Upload to',
			'share.uploadManyTo' => ({required Object count}) => 'Upload ${count} files to',
			'share.searchHint' => 'Search machines',
			'share.noFiles' => 'Couldn\'t read the shared files.',
			'share.textOnly' => 'Only files can be sent to a server. Share a file instead.',
			'share.connecting' => ({required Object name}) => 'Connecting to ${name}',
			'share.connectFailed' => 'Couldn\'t connect',
			'share.uploading' => 'Uploading',
			'share.fileOf' => ({required Object index, required Object count}) => 'File ${index} of ${count}',
			'share.done' => 'Uploaded',
			'terminalSearch.hint' => 'Search the output',
			'terminalSearch.matchCount' => ({required Object current, required Object total}) => '${current}/${total}',
			'terminalSearch.noMatches' => 'None',
			'terminalSearch.matchCase' => 'Match case',
			'terminalSearch.older' => 'Older match',
			'terminalSearch.newer' => 'Newer match',
			'terminalSearch.close' => 'Close search',
			'commandPalette.searchHintSnippets' => 'Search snippets…',
			'commandPalette.empty' => 'Nothing here yet',
			'commandPalette.noResults' => 'No matches',
			'commandPalette.enterToRun' => 'Enter to run',
			'commandPalette.insertSnippetTitle' => 'Insert snippet',
			'background.channelName' => 'Active sessions',
			'background.channelDescription' => 'Shown while Termphin keeps SSH sessions connected in the background.',
			'background.notificationTitleOne' => '1 session connected',
			'background.notificationTitleOther' => ({required Object count}) => '${count} sessions connected',
			'background.notificationText' => 'Tap to return',
			'analyticsConsent.title' => 'Share usage analytics?',
			'analyticsConsent.body' => 'Nothing personal, nothing from your screen or sessions - just a handful of named events: which screens you open, which settings you change, whether a connection succeeded or why it failed. Enough to tell what\'s used and catch crashes. No autocapture, no tracking of what you type or where you connect. Nothing is collected unless you check the box below, and you can change your mind any time in Settings.',
			'analyticsConsent.checkboxLabel' => 'Share anonymous usage data',
			'analyticsConsent.legalNotice' => 'By continuing you accept the terms of service and the privacy policy.',
			'analyticsConsent.privacyLink' => 'Privacy policy',
			'analyticsConsent.termsLink' => 'Terms of service',
			'analyticsConsent.allow' => 'Allow',
			'onboarding.welcomeTitle' => 'Welcome to Termphin',
			'onboarding.welcomeBody' => 'An SSH client whose sessions survive a dropped connection. Lock the phone, lose signal, come back - your shell is still there.',
			'onboarding.getStarted' => 'Get started',
			'onboarding.serverTitle' => 'Do you have a server?',
			'onboarding.serverBody' => 'Termphin connects to machines you already run, over SSH.',
			'onboarding.serverYes' => 'Yes, I have one',
			'onboarding.serverYesSubtitle' => 'A VPS, a Raspberry Pi, a machine at work - anything you can SSH into.',
			'onboarding.serverNotYet' => 'Not yet',
			'onboarding.serverNotYetSubtitle' => 'See where to get one.',
			'onboarding.permissionsTitle' => 'A few things to set up',
			'onboarding.permissionsBody' => 'All optional, and all changeable later in Settings.',
			'onboarding.backgroundTitle' => 'Unrestricted battery use',
			'onboarding.backgroundSubtitle' => 'Lets the system keep Termphin running so SSH sessions survive when you switch apps or lock the screen.',
			'onboarding.notificationsTitle' => 'Notifications',
			'onboarding.notificationsSubtitle' => 'Shows what sessions are running and how downloads are getting on.',
			'onboarding.localNetworkTitle' => 'Local network access',
			'onboarding.localNetworkSubtitle' => 'Lets you reach machines on the network you\'re connected to. Skip it if yours are all elsewhere.',
			'onboarding.continueAction' => 'Continue',
			'onboarding.finish' => 'Finish',
			'onboarding.skip' => 'Skip',
			'onboarding.back' => 'Back',
			'serverGuide.title' => 'Where to get a server',
			'serverGuide.computerTitle' => 'Your own computer',
			'serverGuide.computerBody' => 'Turn on SSH: Remote Login on a Mac, OpenSSH Server on Windows or Linux. Then add its address here.',
			'serverGuide.cloudTitle' => 'A cloud server',
			'serverGuide.cloudBody' => 'Any Linux VPS works. The provider gives you an address, a username and a password or key.',
			'whatsNew.title' => 'What\'s new',
			'whatsNew.gotIt' => 'Got it',
			'whatsNew.nowAvailable' => 'Now available',
			'whatsNew.next' => 'Next',
			'hostKey.newTitle' => 'Unknown host',
			'hostKey.changedTitle' => 'Host key changed',
			'hostKey.newBody' => 'Termphin has not connected to this address before. Check that the fingerprint matches the server, then accept it to remember this host.',
			'hostKey.changedBody' => 'The key this address presented is not the one Termphin pinned. A rebuilt server or a rotated key looks like this - so does someone sitting between you and it.',
			'hostKey.changedWarning' => 'Only accept this if you know the server\'s key changed.',
			'hostKey.endpoint' => ({required Object host, required Object port}) => '${host}:${port}',
			'hostKey.keyTypeLabel' => 'Key type',
			'hostKey.fingerprintLabel' => 'Fingerprint',
			'hostKey.pinnedLabel' => 'Previously pinned',
			'hostKey.verifyHint' => 'On the server, ssh-keygen -lf its host key file prints the same fingerprint.',
			'hostKey.accept' => 'Accept and remember',
			'hostKey.acceptChanged' => 'Accept new key',
			'hostKey.reject' => 'Do not connect',
			'keyboardInteractive.title' => 'The server is asking',
			'keyboardInteractive.fallbackPrompt' => 'Response',
			'keyboardInteractive.submit' => 'Send',
			'manual.title' => 'Manual',
			'manual.loadFailed' => 'Could not load the manual.',
			'manual.loadFailedBody' => 'Check your connection and try again.',
			'manual.retry' => 'Try again',
			'manual.openInBrowser' => 'Open in browser',
			'manual.openFailed' => 'Could not open the link.',
			'manual.howToFix' => 'How to fix this',
			'manual.troubleshooting' => 'Troubleshooting guide',
			'manual.readMore' => 'Read more in the manual',
			'manual.whatIsThis' => 'What is this?',
			'tagMigration.title' => 'Convert tags to groups',
			'tagMigration.explanation' => 'Tags have been replaced by groups. Each machine and snippet now belongs to a single group. Choose which tags to convert into groups.',
			'tagMigration.multipleTagsNotice' => 'Records with several tags will join the first of their tags kept in this list.',
			_ => null,
		} ?? switch (path) {
			'tagMigration.usageCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} record', other: '${n} records', ), 
			'tagMigration.createGroups' => 'Create groups',
			'tagMigration.startFresh' => 'Start fresh',
			'tagMigration.skipDialogTitle' => 'Discard tags?',
			'tagMigration.skipDialogMessage' => 'Your tags will be discarded and cannot be restored. All machines and snippets will be moved to General.',
			'tagMigration.skipDialogConfirm' => 'Discard tags',
			'selection.countSelected' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${count} selected', other: '${count} selected', ), 
			'selection.moveToGroup' => 'Move to group',
			'selection.clear' => 'Clear selection',
			'selection.selectAll' => 'Select all',
			'selection.all' => 'All',
			'selection.move' => 'Move',
			'selection.deleteTitle' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Delete ${count} item?', other: 'Delete ${count} items?', ), 
			'selection.deleteConfirm' => 'This cannot be undone.',
			'selection.deleteAnyway' => 'Delete anyway',
			'selection.moved' => ({required num n, required Object count, required Object group}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Moved ${count} to ${group}', other: 'Moved ${count} to ${group}', ), 
			'selection.deleted' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Deleted ${count} item', other: 'Deleted ${count} items', ), 
			'selection.machinesInUseBody' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '1 machine connects through one you are deleting and will stop connecting:', other: '${count} machines connect through one you are deleting and will stop connecting:', ), 
			'selection.keysInUseBody' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '1 machine uses a key you are deleting and will stop connecting:', other: '${count} machines use a key you are deleting and will stop connecting:', ), 
			'selection.inUseTitle' => 'Still in use',
			'globalSearch.hint' => 'Search everything',
			'globalSearch.back' => 'Back',
			'globalSearch.clear' => 'Clear',
			'globalSearch.machines' => 'Machines',
			'globalSearch.sessions' => 'Sessions',
			'globalSearch.groups' => 'Groups',
			'globalSearch.snippets' => 'Snippets',
			'globalSearch.keys' => 'Keys',
			'globalSearch.recentMachines' => 'Recent machines',
			'globalSearch.openSessions' => 'Open sessions',
			'globalSearch.emptyHint' => 'Find machines by name, address or username, and sessions, groups, snippets and keys by name.',
			'globalSearch.noResults' => ({required Object query}) => 'Nothing matches "${query}"',
			'globalSearch.inGroup' => ({required Object group}) => 'In ${group}',
			'globalSearch.leaveGroup' => 'Search everything again',
			'globalSearch.machineCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} machine', other: '${n} machines', ), 
			'globalSearch.snippetCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} snippet', other: '${n} snippets', ), 
			'globalSearch.keyCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} key', other: '${n} keys', ), 
			'globalSearch.emptyGroup' => 'Empty',
			_ => null,
		};
	}
}
