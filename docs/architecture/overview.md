# Architecture overview

Where the pieces are and how they connect. The topic files next to this one go deep; this one is the map.


**Entry point:** `lib/main.dart` → `loadAppSettings()` (before the first frame)
→ `SshSessionManager.init()` → `_bindConnectionPrompts()` →
`ForegroundNotificationService.init()` → binds the service to the session count
and registers an `AppLifecycleListener` → `SshClientApp` (`lib/app.dart`) →
`_AppGate` routes to `LockScreen` or `HomeScreen`.

**State:** Riverpod. Providers in `lib/providers/`. `profilesProvider` is CRUD
over `ProfileStorage`; `sshConnectionProvider` (family, keyed by session id +
profile) is the per-session state machine.

**Models** (`lib/models/`): `SshProfile`, `SshKey`, `Snippet`, `KnownHost`,
`ProfileGroup`, `PortForwardingRule`, `SessionTab` and `RemoteAgentStatus` carry
`toJson`/`fromJson`. `ActiveSessionView` and `SnippetRun` have no JSON form:
they describe what is happening now.

## Source layout

`lib/` is layered - `models`, `providers`, `services`, `screens`, `widgets`,
`theme`, `utils`, `i18n` - and the three big layers are split by topic, so a
file is found by asking what it is about, not what kind of class it holds.
`test/` mirrors `lib/` folder for folder.

| Folder | Holds |
|---|---|
| `services/ssh/` | `SshService`, `SshSessionManager`, keepalive and quality, network monitor, local network permission, remote agent client, connection prompts |
| `services/terminal/` | What a session does with bytes: OSC markers, predictive echo, reconnect input buffer, remote mux commands, agent probe cache, terminal modes and text |
| `services/completion/` | Command-line reading and completion |
| `services/sftp/` | SFTP service, remote copy and move, downloads, upload plan, cancel token |
| `services/storage/` | Every store over SharedPreferences, plus the `WriteQueue` they serialise on |
| `services/security/` | `SecretCipher`, the AEAD ciphers, the PIN/biometric lock |
| `services/backup/` | Export and import, the backup envelope's crypto |
| `services/settings/` | `Setting<T>`, `loadAppSettings()` and every concrete settings object, including the toolbar layout |
| `services/platform/` | Foreground service, local notifications, iOS background task, quick actions |
| `services/app/` | Onboarding, what's new, release notes, review prompt, tag migration, URLs, anonymizer |
| `services/snippets/` | Running a snippet in a session |
| `services/search/` | The global search's matching: every word against machines, sessions, groups, snippets and keys |
| `services/analytics/` | PostHog wrapper and its closed enums |
| `widgets/terminal/` | The session pane, key toolbar, action dock, tunnels, add-tab sheet |
| `widgets/ssh/` | Connecting view, connection log, quality pill, host key and keyboard-interactive dialogs |
| `widgets/sftp/` | File browser, folder picker, transfer dialogs, editor pieces |
| `widgets/settings/` | One widget per Settings section, each loading its own state, plus the PIN setup dialog |
| `widgets/profiles/`, `widgets/snippets/`, `widgets/backup/`, `widgets/onboarding/` | Pieces that belong to one feature |
| `widgets/ui/` | The shared kit: cards, sheets, notifications, form fields, nav rail, list headers, settings tiles, confirm and text-input dialogs, clipboard and link helpers |
| `screens/terminal/state/` | The terminal screen's tab strip state (`TabStripController`), splits, swipe and reconciling, kept free of widgets so they unit-test |
| `screens/` | `main_shell`, `home_screen`, `lock_screen`, `onboarding_screen`, then one folder per area: `terminal`, `settings`, `sftp`, `snippets`, `keys`, `groups`, `backup`, `search` |

A new file goes in the folder for its topic. If it fits none, that is a
reason to look at the folders, not to add a flat file beside them.


## Where each topic is written down

| File | Covers |
|---|---|
| [`ssh.md`](ssh.md) | `SshService`, host keys, jump hosts, connectivity, reconnecting, connection quality |
| [`predictive-echo.md`](predictive-echo.md) | The local echo engine and its fuzz test |
| [`platform.md`](platform.md) | Foreground service, iOS suspension, local network permission, shortcuts |
| [`data.md`](data.md) | Storage, groups, the `Setting<T>` system, backup and restore |
| [`transfers.md`](transfers.md) | SFTP downloads, uploads, copy and move |
| [`ui.md`](ui.md) | Screens, shared widgets, layout rules, theme and terminal schemes |
| [`analytics.md`](analytics.md) | PostHog, consent, what is sent |
| [`onboarding.md`](onboarding.md) | First run, review prompt, changelog versus what's new |
| [`../release.md`](../release.md) | Release builds, what a release ships, signing, export compliance, Android toolchain |

## Sync and payments are deleted outright

Not unwired - deleted. That decision was taken while the app was still
unreleased and there was nothing to announce a removal to. **It has shipped
since** - 1.5.0 is on Google Play - so anything user-facing removed from here
on is a change real people notice, and belongs in `assets/release_notes.yaml`.
Sync (`SyncService`, `AuthService`, `SupabaseSyncBackend`,
`lib/services/sync/`, tombstones), the crypto that existed only to serve it
(`secret_vault.dart`, `mnemonic.dart`, `bip39_wordlist.dart`,
`SecretCipher.adoptMasterKey`), and RevenueCat (`purchases_flutter`,
`lib/services/purchases/`, the paywall screen) are all gone, along with
`supabase_flutter` and `google_sign_in`. `SecretCipher` itself stays - it seals
profiles, keys and host key pins. `SshProfile`, `SshKey` and `Snippet` no longer
carry `deletedAt`/`workspaceId`; a delete is a plain remove from storage.

**There is no entitlement anywhere in the app**, and the remote agent has never
had a gate.
