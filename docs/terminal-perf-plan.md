# Terminal performance - open items

Rendering is native Flutter through `terminal_view`, our fork of `xterm`
published to pub (submodule at `repos/terminal_view`). The app-side wrapper is
`lib/widgets/terminal/terminal_pane.dart`.

Rounds 1 and 2 are done: merged paint runs, theme and style equality, one
reflow per pinch-zoom gesture, no platform channel call when the caret has not
moved, a cached current line, `getTrimmedLength` bounded by length, a hoisted
URL pattern and a cursor blink that stops without focus or while output
streams. Two items are left.

---

## 1. Make the scrollback limit configurable

**Severity: low.** Memory, not speed.

`kTerminalScrollbackLines` in `lib/widgets/terminal/terminal_pane.dart`
hardcodes 10000 lines per session. Each `BufferLine` at 80 columns allocates
96 cells × 4 words × 4 bytes ≈ 1.5 KB, so a full scrollback is ~15 MB per tab.

**Approach.** Add a `Setting<T>` next to the other terminal settings and offer
a few presets rather than a free-form number. `Terminal.maxLines` is final in
`terminal_view`, so the value applies to new sessions only; say so in the UI.
The setting goes into the backup like any other (`CLAUDE.md`).

---

## 2. Confirm which rendering backend Android is actually using

**Severity: unknown - this is a measurement task, not a change.**

There is no Impeller flag in `android/app/src/main/AndroidManifest.xml` or
`android/gradle.properties`, so the build takes Flutter's default. On recent
Flutter that is Impeller on Vulkan-capable devices with a Skia fallback
otherwise, and the glyph atlas path differs substantially between the two -
which matters a lot for a terminal, since it is almost entirely text.

**Approach.** A/B on the actual target device:

```bash
flutter run --profile                         # default
flutter run --profile --no-enable-impeller    # forced Skia
```

Compare raster thread times in the DevTools timeline. If Impeller is losing on
the target hardware, the manifest flag is how you pin it. Record the numbers
either way.
