# Screens, widgets, layout and theme

What each screen and shared widget is for, and the layout and colour rules every screen follows.

## Screens and widgets

`HomeScreen` (home), `TerminalScreen`, `LockScreen`, `SettingsScreen`,
`KeyManagerScreen`, `KeyFormScreen`, `GroupsScreen`, `GroupFormScreen`,
`SftpEditorScreen`, `SftpImagePreviewScreen`, `ExportScreen`.

`KeyFormScreen` is where a key is made: name, group and type - including
"import an existing key" as a fourth type - on one screen. It replaced a bottom
sheet of four options that each popped a second dialog to ask for the name.

`TerminalAppearanceScreen` owns every terminal setting, which Settings only
links to. It is a screen because of the preview pinned above the controls:
`TerminalPreview` is a real read-only `TerminalView` with a canned session, so
what is previewed is drawn by the renderer that will draw the session. It holds
no copy of the values - preview and controls read `terminalSettings` directly
and every change writes straight through.

`EditorSettingsScreen` is the same arrangement for the SFTP text editor:
the real `re.CodeEditor`, read-only, as the preview, over `EditorSettings`
(font, size, line height, tab width, line numbers, wrap). Tab width is the
spaces Tab and an indent insert - re_editor fixes it when a file opens and
cannot change how wide a literal tab is drawn.

- **Syntax colours are the terminal scheme's own ANSI palette**
  (`schemeHighlightPalette`), not a fixed theme: the editor is opened inside
  `TerminalSchemeTheme`, so its background is the scheme's, and a fixed Atom
  palette left Dracula strings in Atom's green - and light-grey tokens on a
  light scheme. The preview is wrapped the same way, or it shows colours the
  editor never uses.
- **A pinch writes `editorSettings.fontSize`** through `PinchFontZoom`, which
  watches raw pointers: a scale recogniser would win the arena for one-finger
  drags and stop the file scrolling.
- **Find and replace is re_editor's own `CodeFindController`**, driven by
  `EditorFindBar`. Matches are computed on its isolate, so a widget test has to
  pump with `runAsync` to see them.
- Settings: **SFTP** holds the download folder, `sftpShowHiddenSetting` (the
  browser's eye button, same key it always had) and the editor. **Fast upload
  is under Terminal**, because it is used from a session and its result is a
  path at the cursor. The dropdown and switch rows both appearance screens use
  are `lib/widgets/ui/settings_controls.dart`.

Settings ends with an About card: version from `package_info_plus` and a row
into Flutter's own `showLicensePage`, which assembles the list from every
dependency's LICENSE file.

### Global search

The box at the top of Machines, Snippets and Keys is not a field: a tap flies
it (a `Hero`) to the top of `GlobalSearchScreen`, which searches every
machine, session, group, snippet and key at once. The lists under the box are
narrowed only by their group chips now; there is no in-place filter to keep
in step with the search. The machines' sort is a square box beside the search box, drawn like it (fill,
border, a regular-weight icon of the order in force), so it reads as a tool of
the list rather than one more group to filter by.

- **Matching is `globalSearch()`** (`lib/services/search/global_search.dart`),
  pure and tested on its own. Every word has to appear somewhere in an item.
  Each word scores its best field: how well it fits (the whole field, its
  start, a whole word, a word's start, anywhere) times the field's weight in
  `SearchWeights` - a name counts fully, a group only a third, so "main"
  finds the key named main before the machines filed under a group called
  main. Sections have no fixed order: the one with the best match comes
  first, and Enter takes that match. Machines match on name, host, username,
  `user@host` and group; the default group also by its localized name.
  Nothing typed shows open sessions and recent machines.
- **A tap does what it does on the item's own screen**: a machine goes through
  `TerminalOverlayNotifier.openProfile` (the one place the "first live tab,
  else the resumable one, else new" rule lives), a session opens, a snippet
  runs, a key opens in `KeyFormScreen` and bumps `sshKeysRevisionProvider` so
  the key manager's own list reloads. A group stays on the screen and scopes
  the search to itself, shown as a chip under the field. Enter takes the
  best match.
- **Each screen's box has its own hero tag.** All four main screens stay
  mounted side by side in `MainShell`, and one tag twice in a route is an
  error. The new-session sheet has its own too (`globalSearch-addSession`).
- **The keyboard waits for the landing.** Focus is asked for the frame after
  the route's animation completes: during the flight the hero holds a
  placeholder where the field goes, and before the route is installed its
  animation is a stand-in that already reads as complete.
- **Opening a machine or a session does not fly the box back.** The user is
  looking at the terminal by then, so the search screen switches its hero off
  (`HeroMode`) in the same call as the pop - heroes are paired on the frame
  after, which is in time. Back, and results that stay (a snippet, a key),
  land the box on the list as usual.
- **What flies is the box, not either end's child** (`searchBoxFlight`): a live
  `TextField` squeezed through every width in between reflows each frame. The
  border warms to the accent on the way up.
- Honours `anonymizeProvider` like any list: matching runs on the real values,
  the rows show the placeholders.

### Terminal sub-widgets

- `SessionView` - one tab's terminal, its SFTP browser and everything they open.
  **Was a `part of` `terminal_screen.dart`**, which is not a split but a way
  around one. It is an ordinary import now, and what the screen needs is public
  on `SessionViewState`. **Do not put it back.**
- `SessionSwipeController` (`lib/screens/terminal/state/session_swipe.dart`) -
  the horizontal drag between tabs, formerly eleven fields on
  `TerminalScreenState`. Knows nothing about tabs: the screen supplies count
  and active index and hears back through `onCommit`.
- `TabSplits` (`lib/screens/terminal/state/tab_splits.dart`) - two tabs sharing
  one strip entry. **Partners are adjacent in `_sessions`**, so the flat order
  the manager persists needs no idea splits exist; every mutation goes through
  `join`/`reorder`, which keep that true. Saved by the manager beside the
  tab order (`session_splits`, divider ratio included) and put back by the
  next strip where both tabs made it back; `saveSplits` rewrites only the
  tabs the calling strip holds, since a strip opened for one machine sees
  only some of them. Made and undone from the tab menu only; the
  strip's `ReorderableListView` has one item per entry, so a split is dragged
  and swiped as one tab. Stacked in portrait, side by side in landscape, off
  `MediaQuery.orientationOf` rather than the page's shape, which the keyboard
  changes. Every pane carries a name bar
  lit on focus, held and dragged onto the other pane to swap the two;
  stacked ones also fold - with the keyboard up the unfocused one folds to its
  bar, animated alongside the keyboard, and is clipped **at its last height**
  rather than squeezed, so its pty is never resized for it. The keyboard is read off `View.of`, since the Scaffold
  strips it from the body's `MediaQuery`.
- `TunnelsPanel` - port forwarding. One rule is drawn by
  `PortForwardingRuleTile`, shared with the profile form; it is a row, not a
  card, and callers stack several into one `AppCard.fields`. `status` is null in
  the profile form. **Stopping a tunnel and deleting its rule are two different
  things**: `stopTunnel` parks a rule at `idle` and leaves it on screen,
  `removeAdhocTunnel` is the trash button. They used to be one call, which made
  the ad-hoc switch a delete with no warning and no undo.
- `ConnectingView` - connection progress with auth URL handling.
- `AddSessionSheetContent` - profile picker for new tabs, and the only way in to
  sessions living on a server: each row's overflow lists them (attach, rename,
  kill), asked for only when tapped since listing costs a round trip. Its box
  is the same launcher, opening `GlobalSearchScreen` with `onPick`: machines
  only, all of them, and a pick starts a new session like a tap on the row.

### The keyboard is Flutter's job, not ours

`TerminalScreen`'s `Scaffold` resizes for it (`resizeToAvoidBottomInset` left at
its default) and the body is a `Column` of session and key toolbar. There is no
`KeyboardInsetController`, no measured toolbar height, no `viewInsets`
arithmetic and no keyboard restore path - all of it was deleted and should not
come back:

- **The band of empty screen came from Android, not the layout.** A window's
  saved soft-input state restores the keyboard's *inset* on resume; the input
  connection behind it went with the frozen process. The platform reports the
  same inset either way, so no amount of Dart can tell a real keyboard from a
  leftover reservation. `android:windowSoftInputMode="adjustResize|stateAlwaysHidden"`
  is what closes it - `stateHidden` alone only applies when the activity is
  first entered.
- **The debounce moved to the packet.** The pane follows the keyboard frame by
  frame, and every intermediate height would otherwise be a window-change the
  remote shell acts on. `PtyResizeReporter` holds the last size for 120ms and
  sends once. Throttling the layout to protect the pty was the wrong layer.
  Settling back on the size the server already has (the layout passing
  through another one, as it can on the way back from the background) sends a
  one-row nudge first: the local buffer was resized twice, the pty never, so
  without it no SIGWINCH comes and the program never repaints over what the
  resizes left - until the keyboard changes the size for real.

### Tab strip position

`tabBarPositionSetting` (Settings → On-screen controls, "Tabs at the bottom")
moves the portrait tab strip out of the `AppBar` and into the body `Column`,
between the session and the key toolbar - so in the file browser, which has
no toolbar, it is the bottom row. **Moving it must never resize the pane**:
the strip is the same height in either place and nothing is added around it
(`terminal_tab_bar_position_test.dart` pins the pane's size across a switch).
The toolbar's own top line parts tabs from keys; a gap would cost rows. With
the strip down there is nothing up top, so `MainShell` anchors toasts at 0.
Landscape keeps the side rail either way.

### Action dock

The floating draggable button on the terminal and the tile panel it opens -
`FloatingActionDock`, `showActionDockMenu`, `DockAction` and its order/hidden state
(`lib/services/settings/action_dock_settings.dart`), edited on
`ActionDockSettingsScreen`. It used to be called the command palette, which it
is not - there is nothing to type into. The SharedPreferences keys still read
`command_palette_*` so the rename does not reset anyone's layout. The name
survives in `snippet_picker_panel.dart`, which really is a search-and-run
palette.

The editor draws the panel tile for tile over a tray of the hidden ones.
Dragging inserts (`placeDockAction`), never swaps, and a tray tile can be
dragged straight to its place; hiding and showing go through the corner badge
only, so a stray tap on the panel changes nothing. Every edit stores the order
visible-first (`hideDockAction`), so no hidden action sits unseen between two
visible ones. A mouse drags at once, a finger long-presses first.

### Special-keys toolbar and its editor

Action table, grid shape and persistence in `lib/services/settings/toolbar_layout.dart`;
the live toolbar is `SpecialKeysToolbar`; the editor is `ToolbarSettingsScreen`.

- **Settings → On-screen controls is where both this and the action dock are
  switched on**, one switch each, and the row into each editor is only drawn
  under a switch that is on. Neither editor carries its own switch. Turning the
  toolbar off is a hide, not a reset. `TerminalScreen` watches both settings and
  keeps the two conditions apart (`terminalLive` vs `showToolbar`) - neither may
  take the other down with it.
- **One key widget, `ToolbarKeyButton`, draws keys everywhere** - over a session
  and in the editor's grid. Anything that previews a toolbar key uses this or it
  is not a preview. `toolbarSchemeFromTheme` is the matching palette for use
  outside a session.
- The editor is a **pinned grid over a scrolling pool**, because both ends of a
  placement gesture have to be visible at once. Drag is the accelerator,
  tap-slot-then-key is the one-handed path. A key sits in one slot only: placing
  one already on the toolbar moves it and blanks the old slot.
- **Shrinking the grid asks first.** `ToolbarLayout.resized` silently drops what
  no longer fits, so `keysLostByResize` counts the casualties for the editor to
  put a number in front of the user.
- **A layout is one of several: `ToolbarProfiles`**, on `ToolbarProfilesScreen`.
  A profile carries the whole grid, shape included. `toolbarSettings.layout`
  stays what the live toolbar reads every frame - a copy of the active profile's
  layout, kept in step by `saveToolbarLayout` and `activateToolbarProfile`, the
  only two ways in, so nothing that draws a toolbar knows profiles exist. A
  store that reads back as nothing falls back to the five legacy grid keys.
  Export carries every profile plus the active id, and the single layout
  alongside them for a backup restored onto an older build.
- **Switching mid-session is the quick sheet** (`session_quick_sheet.dart`),
  opened by the caret beside the tab strip's plus while a terminal is live. Its
  Toolbar tab draws every profile's first page with `ToolbarKeyButton` and a
  tap goes through `activateToolbarProfile`; its Appearance tab writes scheme,
  font and font size straight into `terminalSettings`. No light/dark switch
  there: the session's chrome follows the terminal scheme, so it would change
  nothing on screen. With the toolbar off the sheet is the Appearance tab
  alone. Screens it leads to are pushed after it closes, by the caller.
  It is built from the add-session sheet's parts - title, `surfaceElevated`
  cards, `TagChip`s - and its tabs are `SegmentedSwitch`, the same control as
  the tab menu's terminal/files switch.
- **A layout can arrive as a link: `termphin://toolbar?d=...`**
  (`toolbar_share_link.dart`), base64url JSON of the shape and the app's key
  ids. It goes through the same gate as an `ssh://` link, so it waits behind
  the PIN and the relock, and `ToolbarImportSheet` only asks: every page
  drawn, every text key spelled out with those that press Enter marked, then
  Add or Add and use. Reading one is strict - snippets (they name something
  on the sender's phone) and unknown keys are left out and counted, the
  shape is clamped, and the order is padded with blanks and deduplicated in
  place, because `normalizeToolbarOrder` would otherwise fill gaps from the
  default layout and shift keys after a duplicate.

### Notifications and sheets

`AppNotifications` is the only way to show transient feedback. Toasts slide out
from under the app bar, up to three at a time, in a root `OverlayEntry`; the
stack clears as one unit. **Do not use `ScaffoldMessenger`/`SnackBar`** - the
bottom of the screen belongs to the nav bar, the session dock and the key
toolbar. Screens with a non-standard app bar height set
`appNotificationAnchor`.

**Context bars:** selecting rows (machines, keys, snippets, files) and the
transfer bar all use `ContextBar` - a flat docked strip, never a floating card,
tinted while selecting. Actions that do not fit move into "More" from the end,
so a split pane gets the same bar. The file browser and the transfer bar dock
it at the top; machines, keys and snippets dock it at the bottom, within reach
of the thumb, through `SelectionActionHost`, which pushes the list up.

`showAppSheet` is the only way to open a bottom sheet. **Do not call
`showModalBottomSheet` directly** - every sheet used to pass its own `shape`,
silently dropping the theme's styling, and announced the drag gesture three
different ways. The helper draws the handle and leaves shape and background to
`bottomSheetTheme`. `handle: false` is for a `DraggableScrollableSheet`, which
resizes below a bar that has to live inside that child to move with it.

**Anonymize:** `anonymizeProvider` + `IdentityAnonymizer` swap machine names,
hosts and usernames for deterministic placeholders across every screen. Display
only - the profile on disk and the host connected to are untouched. Anything
rendering a profile's identity is expected to honour it.


## Layout and theme

### Content width and system bars

The app is edge to edge, so nothing below the app bar gets its bottom inset for
free: a `Scaffold` body is padded for a `bottomNavigationBar` and nothing else.
A scaffold body is wrapped in `SafeArea(top: false)`; `showAppSheet` does the
same for sheets it draws a handle on, and leaves the `handle: false` ones alone.

The reading width is `ContentGutter`, **not `DesktopContentWidth`**, for
anything that scrolls. Both centre `kContentMaxWidth` on a wide window, but
`DesktopContentWidth` boxes the child, and a box around a scroll view is a box
around the gesture - a drag started in the margin beside a centred list scrolled
nothing. `ContentGutter` hands the view an `EdgeInsets` to add to its **own**
padding, so the viewport keeps full width. `LargeTitleScaffold` passes it as the
third argument to `bodyBuilder`; a `CustomScrollView` takes it as one
`SliverPadding` + `SliverMainAxisGroup`. `DesktopContentWidth` stays for what
does not scroll.

### The wide-layout side rail

Replaces the bottom nav on desktop and in any landscape window
(`isWideLayout`). There are two - `_Sidebar` in `main_shell.dart` and
`_buildTabRail` in `terminal_screen.dart` - and they are the same strip down the
same edge, so they share `kNavRailWidth`/`kNavRailCollapsedWidth` and
`NavRailToggleButton` rather than each carrying its own copy of 240.

- **One setting for both**, `sidebarCollapsedSetting`. They are never on screen
  together, so collapsing one while the other stayed wide would read as the app
  having forgotten.
- **Collapsed, the labels go and the icons stay.** Whatever a row said in words
  has to survive as a tooltip, and a session tab keeps the status ring around
  its avatar. The session tab's tooltip is `TooltipTriggerMode.manual`
  deliberately: a tab is reordered by long-press, and a tooltip answering the
  same gesture stopped collapsed tabs from being dragged at all.
- **`_Sidebar`'s width is the rail plus the left safe-area inset**, because the
  rail sits *behind* a landscape cutout rather than beside it and the `SafeArea`
  inside hands the contents the full rail back. Without the sum, a collapsed
  rail is 64pt with a 48pt cutout taken out of it - the bug that made it read as
  a clipped smear. The terminal's rail needs no sum; its landscape branch
  already wraps the row in a `SafeArea`.
- **The width animates; the contents do not reflow with it.** Both rails lay
  children out at the width being animated *to* and clip with
  `ClipRect`/`OverflowBox`. A 240pt label has no legible form at 100pt.

### Theme

Material 3, light and dark, in `lib/theme/theme.dart`. Every interface colour
lives on `AppColors`, a `ThemeExtension`, and is read off the context:
`context.colors.textPrimary`, **never a constant** - that is what makes a widget
a dependent of the theme so it repaints when the palette changes. `AppTheme`
keeps only what does not vary: radius, spacing and motion tokens, font families,
terminal colour schemes. Reading a colour off the context means the surrounding
expression cannot be `const` - drop the `const`, do not reach for the constant.

`themeModeProvider` over `AppThemeMode`: `system` by default, `light`/`dark` to
pin one. `loadAppSettings()` reads it before `runApp` so a light-theme
user never sees a dark first frame. The terminal keeps its own scheme either
way.

Both palettes are tuned by contrast ratio, and
`test/theme/palette_contrast_test.dart` asserts the ranges **in both
directions** - too much contrast is as much a defect as too little. Separation
comes from the step between `surfaceCard` and `backgroundPrimary`, so
`surfaceBorder` stays a hint (under 1.35 against its own surface);  `AppCard`
drops the stroke entirely in dark. `surfaceBorderStrong` is for edges that carry
themselves - menus, dialogs, popovers over a scrim. Not bottom sheets: the grab
handle already announces the edge. Row separators are `surfaceDivider`
(`AppDivider`), never a `Border.all`. Form controls fill with `fieldFill`.

An implicitly animated fill fades to `someColor.invisible` (the `AppColorFade`
extension), **never `Colors.transparent`** - that constant is transparent
*black*, so the colour tweens through grey on its way out. Same reason
`splashColor`/`highlightColor`/`hoverColor`/`focusColor` are set from the accent
in `themeFor`.

**No sliders** - numeric settings use the `StepperRow`/`ValueStepperRow` +/-
pair, which hits an exact value on the first try.

### Terminal schemes

In a light scheme every `bright*` colour has to be *lighter* than the colour it
brightens, and only `black` may be heavy (over 7:1 against the background) - the
rest stay under 6.5:1 or the output reads muddy rather than coloured.
`terminal_scheme_theme_test.dart` asserts both. Upstream light palettes often
break this, so shipped values deviate where legibility needs them to.

**Terminal chrome follows the terminal scheme.** `TerminalSchemeTheme` wraps
`TerminalScreen` in `MainShell` and swaps in a `ThemeData` built from
`AppColors.fromTerminalScheme`, so tab strip, key toolbar, action dock,
connecting screen and SFTP browser are painted in the selected scheme. It works
without touching any of them because they already read colours off the context,
and it has to wrap from outside the screen since a `Theme` a widget returns sits
below its own `State.context`. The palette derives from the scheme's background,
foreground and ANSI colours rather than its `ui*` fields, so contrast ratios
hold in every scheme.
