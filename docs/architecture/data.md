# Data: storage, groups, settings, backup

How profiles, keys, snippets and groups are persisted, how a setting works, and how a backup is built and restored.

## Persistence

`ProfileStorage` / `SshKeyStorage` / `SnippetStorage` / `GroupStorage`. Every
mutation is a load-modify-save, so each runs through a shared `WriteQueue` - two
overlapping cycles would otherwise have the second read pre-write state and
erase the first.
The queue is `static` per storage class, because what is serialised is the
SharedPreferences key, not the object holding it.


## Groups

**Groups replaced tags, and a group spans everything**: a profile, an SSH key
and a snippet all carry one `group` name, so `tags` is gone from every model.
`ProfileGroup` is a name plus an optional `colorHex` out of
`ProfileAvatarColor.colors` - the avatar palette, not a second one. Records
reference a group **by name**, which is why `GroupStorage.updateGroup` rewrites
that string on all three stores when a group is renamed, and `deleteGroup`
moves them to `General`.

- **`General` is the floor.** It is always index 0, cannot be renamed or
  deleted, and is where every delete reassigns to - which is also why the groups
  screen gives it no drag handle. Its colour is editable.
- **The group list is seeded once, never merged.** `loadGroups` is a plain read;
  a one-shot migration behind `app_groups_migrated_v1` adopts the legacy
  `profile_groups` key plus whatever groups already stand on records, and that is
  the only time records are consulted. Re-merging on every read is what made a
  deleted group come back, and `group_storage_test.dart` pins it.
- **`addGroup` is a no-op on a blank or duplicate name, not a throw.** The forms
  check first and say `groups.alreadyExists`; a throw from the store would reach
  the UI unhandled the moment two callers raced.
- `GroupPickerField` sits at the top of every create/edit form and is the only
  picker; `GroupFormScreen` is the only way to create or edit one. A list screen
  draws a `ListSectionHeader` per group with a `GroupDot`, and a record naming a
  group that is not on the list is shown under `General` rather than inventing a
  section.

**`TagMigrationService`/`TagMigrationModal` run once, after the lock screen and
before the home screen**, and only when raw storage still holds a `tags` entry.
The user picks which tags become groups rather than having the first one chosen
for them - a tag is multi-valued and a group is not, so the mapping is lossy and
the choice is theirs. It reads the **raw stored JSON**, because by the time a
record is a model its tags have already collapsed through the `fromJson`
fallback. Both paths also set `app_groups_migrated_v1`, or the seed above would
re-create groups the user just declined.



## Settings

**Settings are `Setting<T>`** (`lib/services/settings/setting.dart`), not a
hand-written `loadX()`/`saveX()` pair. One object carries the key, the default,
how a stored value is read back, and the current value - and it *is* a
`ValueNotifier`, so a write cannot happen without being broadcast and a read
cannot come back out of range. `Setting.boolean/number/integer/text/option/textList`
cover the ordinary cases; the general constructor covers the ones with real
rules - `ToolbarSettings.layout` is one setting over five stored keys because
`order` has to be normalised against `columns * rows * pages`, and
`ActionDockSettings.hidden` has to tell "never saved" from a deliberate empty
list.

- `loadAppSettings()` reads every one before the first frame, from `main.dart`.
  That is what lets the rest of the app read `.value` instead of awaiting a
  load. It is also **the only list of what the app persists** - a setting added
  without being put there reads as its default forever.
- Ranges are clamped and unknown values rejected **on read**, not on write: a
  stored value can predate a range that has since narrowed.
- `terminalSettings.changes` is a `Listenable.merge` of the eight terminal
  settings, so nothing has to remember to announce a write.
- Riverpod providers that front a setting only republish it; the value lives in
  the `Setting`.
- **In tests the settings are process-wide.** `SharedPreferences.setMockInitialValues({})`
  is not enough - the in-memory values have to be put back through the readers
  with `await terminalSettings.load()` in `setUp`, and again after seeding
  preferences inside a test.


## Backup and restore

`ExportService` behind three screens: `ExportScreen` is only the fork,
`BackupExportScreen` and `BackupImportScreen` are the halves. Both are a scroll
plus a pinned `BackupActionBar`, so the one commit each screen has does not
scroll away. The import screen previews the file in place through
`ImportOptionsPanel`, which owns the selection and reports it up so the pinned
button can be dead until there is something to import. Both halves draw sections
with `BackupOptionTile`, so a section reads the same going out as coming in.

- **A file has to say it is ours.** `format: termphin-backup` and a `version`
  inside `kMinBackupVersion..kBackupVersion`; `inspect()` throws
  `BackupFormatException` rather than returning a hollow preview, which is what
  used to let any JSON object import "successfully" and change nothing. A
  version above ours is refused outright. Files predating the marker still load:
  a version plus one known section is enough.
- **`inspect()` reads the device too.** Every record comes back as a
  `BackupItem` with a label and `exists`, so the sheet can list what is in the
  file, tick entries individually and say what would clash. `ImportConflicts.skip`
  is the default; `replace` is a deliberate pick. The result is an
  `ImportResult` of added/replaced/skipped per section - a silent "Import
  successful" over a no-op is the thing that replaces. A profile landing without
  its key is named by `profilesMissingKey`/`profilesMissingJumpHost`, since a
  dangling `sshKeyId` is a profile that cannot connect.
- **The passphrase option is real encryption**, not a flag: `backup_crypto.dart`
  derives a key with PBKDF2-HMAC-SHA256 (210k iterations, off the UI isolate)
  and seals with the same AES-256-GCM `sealBytes` the on-device stores use. The
  envelope header stays readable so a file can be recognised without the
  passphrase. Exporting secrets *without* one asks first - the file leaves the
  sandbox and `SecretCipher` protects nothing outside it.
- Sections: profiles (passwords, inline keys, and a key passphrase only when
  asked for - it travels with the secrets, never on its own), SSH keys,
  snippets, groups, known-host pins, terminal settings, app preferences. **A
  section added here has to be added to `_knownSections` and to
  `kBackupVersion`.**
- **Groups are not a toggle in the import UI.** They are structure the records
  point at, so they ride along with whatever is exported. Import adds a group
  the device lacks but never repaints one it already has, takes the file's
  order (groups only the device has go after it), and creates any group
  an imported record names - a record landing on a group that is not on the list
  is what produced phantom sections.
