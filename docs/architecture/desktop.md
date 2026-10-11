# Desktop: what changes off a phone, and how to hide things by platform

Termphin runs on Linux, macOS and Windows from the same widgets as on a phone.
A desktop is not a big phone - it has a window, a mouse and a keyboard, and no
thumb - so a handful of primitives decide the presentation, and screens ask
those rather than which platform they are on. Tablets are deliberately left as
they are: they get the phone's presentation, with the wide-layout rail in
landscape as before.

## Asking about the platform

`lib/utils/platform_info.dart` is the only place that reads
`defaultTargetPlatform`. Screens and widgets ask one of three things:

| Question | Ask | Example |
|---|---|---|
| Can the system do this? | `platformHas(PlatformFeature.x)` | battery restriction, biometrics, web view, the share sheet |
| Is this a mouse-and-keyboard desktop? | `isDesktopPlatform` | dialogs over sheets, right-click menus, shortcuts |
| How much room is there? | `isWideLayout` | sidebar vs bottom nav |

`PlatformFeature` is one exhaustive `switch`: a new platform is one pass down
the list, a new feature is a compile error until every platform answers it.
`PlatformFeature.touchControls` covers everything that stands in for a keyboard
or a pointer - the key toolbar, the floating action dock, "tabs at the bottom",
the selection bubble and its handles - and is off on a desktop. Their settings
stay as they are, so a backup restored onto a phone brings them back.

`test/architecture/platform_branching_test.dart` keeps `lib/screens` and
`lib/widgets` free of `defaultTargetPlatform`, `Platform.isX`,
`showModalBottomSheet`, `fullscreenDialog: true` and `MaterialPageRoute`
outside the helpers below. A new exception goes into its allow-list with the
reason next to it.

To hide something on a desktop: `if (platformHas(PlatformFeature.x)) ...[...]`
in the list it sits in, divider included, so a hidden row leaves no orphaned
separator. If no feature fits, add one to the enum rather than branching on
the platform at the call site.

## Presentation

Four helpers pick the desktop's presentation; screens call them and do not
know which they got.

| Helper | Phone | Desktop |
|---|---|---|
| `showAppSheet` | bottom sheet with a grab handle | dialog in the middle of the window, max 560 wide, closed by Esc or a click outside |
| `pushAppForm` | full-screen page with an X | dialog, max 680 wide; a click outside does nothing, Esc goes through `maybePop` so unsaved edits can ask |
| `pushAppWindow` | ordinary page | large dialog (1280 wide, 90% of the height) for somewhere to work: the SFTP editor, the image preview, the manual |
| `pushAppPage` | page over the app with a back arrow | page inside the current sidebar section, no back arrow, path in the title bar |
| `pushAppPage(window: true)` | the same page | a window over the screen it came from, 820 wide - every Settings page, so the list stays in view behind it |

- **`AppModalScope.isDialog(context)`** tells sheet content it is in a dialog.
  `SheetHandle` hides itself there; `AppDraggableSheet` (the only way to get a
  `DraggableScrollableSheet`) becomes a fixed-height box. A screen that draws
  its own back arrow swaps it for an X when it is in a dialog.
- **`AppDialogRoute`** is barrier-dismissible as far as the route goes, because
  that is what Flutter ties Esc to, and catches a click beside the dialog
  before the barrier sees it. Its `ActionIconTheme` draws the app bar's implied
  back button as an X: there is no page behind a window.
- **`pushAppPage` opened from outside a section** (a form's dialog, a session)
  has no sidebar to open beside, so it falls back to `pushAppWindow`.

## Shell and navigation

- **One sidebar.** On a desktop `MainShell` keeps a `SectionNavigator` per
  destination, so a page opened from Settings or a list stays beside the
  sidebar. A click on the section already selected goes back to its root.
- **No back arrows.** `DesktopPageRoute` implies none. The path to the page is
  published on `desktopBreadcrumb` and drawn in the title bar, every step but
  the last a link back. Esc and the mouse's back button go up one page;
  at a section's root Esc passes on.
- **The terminal is a place in the sidebar, not a screen over it.** The
  terminal's rail on a desktop shows the app's destinations at the top in place
  of the back button, then the sessions, laid out like `MainShell`'s own and
  drawn in the app's theme (`chromeTheme`) so the strip does not move or change
  colour when a session comes and goes. With no session on screen `MainShell`'s
  sidebar lists the open sessions under its destinations instead of the phone's
  single dock row.
- **A phone on its side gets the tablet's rails**, labels and toggle
  included - not a forced icons-only strip. The one collapsed state
  (`sidebarCollapsedSetting`) is the user's to choose on either.

## Window and title bar

`DesktopWindow` (`lib/services/platform/desktop_window.dart`, over
`window_manager`) hides the system's title bar, sets a minimum size and puts
the window back where it was (`desktop_window_bounds`, `desktop_window_maximized`
- device state, outside every backed-up `Setting`). The Linux runner also
starts undecorated so the system bar never flashes.

`DesktopTitleBar` (`lib/widgets/window/title_bar.dart`) sits above the
navigator in `MaterialApp.builder`, with an `Overlay` of its own for its menus.
Left to right: the logo and the Termphin / View / Help menus (on a Mac, room
for the traffic lights instead, and the same menus as the system menu bar via
`AppMenuBar`), the breadcrumb over the drag area (double click maximizes), the
search pill with its shortcut, and minimize / maximize / close painted by
`WindowButtons`. Linux gets resize edges (`DragToResizeArea`) since an
undecorated GTK window has none. The window's own title follows the session on
screen.

## Tray, closing and quitting

Closing the window is the app's decision: `DesktopWindow` sets
`window_manager`'s prevent-close and hands the close to `onCloseRequested`,
which `DesktopTrayHost` (`lib/widgets/window/desktop_tray_host.dart`, around
the chrome in `app.dart`) owns.

- **Close** hides the window into the tray when `closeToTraySetting` is on
  (the default; Settings → Controls, "Keep running in the tray", backed up).
  The first close asks once (`desktop_close_asked`, device state) and the
  answer becomes the setting; "Quit" there quits without a second question.
- **No tray, no hiding.** `DesktopTray.available` asks D-Bus on Linux whether
  a `StatusNotifierWatcher` exists - GNOME without the AppIndicator extension
  has none. Without one, close quits and the setting is greyed out with the
  reason, so the window can never vanish with no way back.
- **Quit** (`AppCommand.quit`, the Termphin menu, the tray) asks first when
  sessions are connected, showing the window if it was hidden.
- **The tray's menu** (`buildTrayMenu`, `tray_menu.dart`): show the window,
  the connected sessions - never the detached ones, which are parked on their
  server on purpose - "New session" on the five machines used last, Quit.
  Names honour `anonymizeProvider`. It follows the manager, the profiles and
  the anonymize switch.
- **Per system** it is `tray_kit` (`repos/tray_kit`, our plugin):
  Linux speaks StatusNotifierItem and dbusmenu over D-Bus from Dart, so
  neither building nor running Termphin needs libappindicator; Windows uses
  `Shell_NotifyIcon`, macOS an `NSStatusItem`. The icon is
  `assets/icons/tray.png`, and `assets/icons/tray_template.png` on a Mac. A
  click on the icon shows the window; on a Mac a click opens the menu, and
  the Dock icon brings a hidden window back.
- **One instance.** A second launch hands over to the first and exits: the
  Linux runner is a unique `GtkApplication` whose `activate` presents the
  existing window; the Windows runner holds a named mutex and broadcasts
  `dev.termphin.termphin.show`; a Mac is single-instance by itself.

The tray icons are written by `scripts/generate_icons.py` with the rest.

## Keyboard

`AppCommands` (`lib/services/app/app_commands.dart`) is the one list of what
the shortcuts and menus run. Shortcuts are read off `HardwareKeyboard` before
focus sees the key, because the terminal takes every key it is given; that is
also why, off a Mac, they all use Ctrl+Shift - plain Ctrl belongs to the
shell. Nothing runs while a dialog or sheet is open (`modalObserver` on the
root navigator).

| Command | Linux / Windows | Mac |
|---|---|---|
| Search everything | Ctrl+Shift+K | ⌘K |
| Copy the selection / paste | Ctrl+C (only with a selection; else the shell's interrupt) / Ctrl+V, also Ctrl+Shift+C/V | ⌘C / ⌘V |
| New machine / new session / close tab | Ctrl+Shift+N / T / W | ⌘N / T / W |
| Next / previous tab | Ctrl+Tab, Ctrl+PgDn / Ctrl+Shift+Tab, Ctrl+PgUp | ⌃Tab, ⇧⌘] / ⌃⇧Tab, ⇧⌘[ |
| Tab 1-9 | Alt+1…9 | ⌘1…9 |
| Find in terminal | Ctrl+Shift+F | ⌘F |
| Fast upload (pick a file, upload it into the session) | Ctrl+Shift+O (Ctrl+Shift+U is IBus's) | ⌘O |
| Text size | Ctrl+= / Ctrl+− / Ctrl+0, Ctrl+wheel | ⌘= / ⌘− / ⌘0 |
| Settings, sidebar, shortcuts, manual | Ctrl+Shift+, / B / / , F1 | ⌘, / ⌘B / ⌘/ , F1 |
| Quit | Ctrl+Shift+Q (plain Ctrl+Q is the shell's XON) | ⌘Q |

The terminal's clipboard keys are terminal_view's, overridden on a desktop by
`desktopTerminalShortcuts()`. Off a Mac, Ctrl+C is `CopyIfSelectedIntent`,
whose action is enabled only with a selection - disabled, the key falls
through to the shell as the interrupt - and Ctrl+V pastes; Ctrl+Shift+C/V,
Shift+Insert and Ctrl+Shift+A are there too. On a Mac it is ⌘C/V/A and Ctrl
is the shell's. Plain Ctrl+A is never bound: it is the line start and tmux's
prefix.

Command suggestions are worked from the keyboard there: while the popup is
up and the session's terminal has focus, Ctrl+Up/Down move through it and
Ctrl+Right takes the one picked (Cmd on a Mac, whose Ctrl+arrows are Mission
Control's) and Esc closes it. `SuggestionKeys` draws those keys as keycaps,
under the popup's rows and beside the Autocomplete switch in Settings. They are taken in
`SessionViewState._onTerminalKey`, which `TerminalPane` hands to
`TerminalView.onKeyEvent`; with the popup gone they are the shell's again.

**A `HardwareKeyboard` handler cannot keep a key from the terminal.** Flutter
hands the focused widget every key whatever the handlers return, so
`AppCommands` running Ctrl+Shift+T does not stop the terminal sending ^T.
`TerminalPane._onKeyEvent` is where a key is kept from the shell: it drops
every key `AppCommands.claims`, and asks its `onKeyEvent` first.

The action dock is a **toolbar over the terminal** on a desktop - the
terminal's width, not the tab rail's, its actions from the left, each
labelled with its shortcut where it has one - on the dock's
own switch (Settings → Controls → Action bar) and with its order and hidden
set. There is no palette of them on a desktop: the bar is that, and the
actions with a shortcut carry it on their button. Settings also has a
Keyboard shortcuts row. The Mac's menu bar shows each command's key
equivalent; `AppCommands.runFromMenu` runs a keystroke once should both the
menu and the keyboard handler hear it.

A handler registers with `AppCommands.instance.register(command, handler)` and
keeps the returned callback to unregister; the last one registered is asked
first, and one that returns false passes the command on.

**Esc** closes whatever is on top: dialogs, sheets, forms and windows (through
the route), menus (Flutter's own), the terminal's
and the editor's find bars, a section's page. A screen with something of its
own to drop - a selection - registers with `AppCommands.registerEscape`;
those are never asked while a `TerminalView` has focus, where Esc is vim's.

## Pointer

- **Right click** is `ContextMenuRegion` / `showAppContextMenu`
  (`lib/widgets/ui/context_menu.dart`): machines, snippets and keys get what
  their tap, long press and `⋮` menu do; the terminal gets copy, paste, select
  all, find; an SFTP row opens its own `⋮` menu, a selection gets download and
  delete.
- **Ctrl (Cmd) click** picks a row, as a long press does on a phone; Shift
  click extends an SFTP selection.
- **A drag moves things without a hold first** - tabs, groups, a split's
  panes - where a phone waits for a long press, a plain drag there being a
  scroll. `ReorderDragListener` and `platformDraggable`
  (`lib/widgets/ui/reorder_drag.dart`) make that choice; use them rather than
  picking a listener at the call site.
- **The terminal has the keyboard without a click.** The session on screen
  takes focus when it is ready and when its tab is switched to
  (`SessionView._focusOnDesktop`), unless a dialog is over it; a press in the
  terminal focuses it too, since terminal_view only focuses on a plain click
  and a drag that selects would otherwise leave Ctrl+C with nowhere to go.
- **The tab swipe is a finger's only.** `SessionSwipeController` ignores mouse
  pointers: a sideways mouse drag over the terminal is a text selection.
- **SFTP** takes files dropped from the file manager (`desktop_drop`), and the
  keys a file manager answers: Backspace up a folder, F5 refresh, F2 rename,
  Delete, Ctrl+A, Esc.

## Smaller things

- On Linux without a keyring the master key falls back to a private file, with
  a warning in Settings → Security (`docs/secrets-architecture.md`, D1).
- On Linux without a keyring the master key falls back to a private file, with
  a warning in Settings → Security (`docs/secrets-architecture.md`, D1).
- Downloads go to the user's Downloads folder or the one picked in Settings
  (`DownloadLocation.desktopTarget`), and the notification offers "Show in
  folder" rather than a share sheet.
- The manual opens in the browser where there is no web view (Linux,
  Windows), and as a window on a Mac.
- The terminal bell blinks the screen once instead of vibrating.
- Toasts stack in the top-right corner at a card's width.
- Global search is a palette over the window rather than a box flying up a
  phone's screen.
