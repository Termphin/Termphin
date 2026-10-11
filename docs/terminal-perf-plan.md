# Terminal performance — round 2

Follow-up work on the terminal rendering path. Round 1 is already merged
(commits `56bcae8..a6e78af`); this document covers the eight items that were
identified but deliberately left out of it.

Items are independent — they can be done in any order and land as separate
commits. The ordering below is by value for effort.

---

## Context you need first

**The terminal is not xterm.js.** Rendering is native Flutter through a
vendored fork of the `xterm` package at `packages/xterm` (path dependency in
`pubspec.yaml`). The app-side wrapper is `lib/widgets/xterm_terminal_view.dart`.
Older notes in the repo describing a WebView are wrong; `CLAUDE.md` has been
corrected.

**What round 1 already changed** — do not redo any of this:

- `TerminalTheme` and `TerminalStyle` gained `operator ==`. Before that, both
  were rebuilt inline on every `build()` and the render object treated each new
  instance as a full invalidation, flushing the paragraph cache and re-measuring
  the font several times a second.
- `TerminalPainter.paintLine` was rewritten into two passes: neighbouring cells
  with the same background merge into one `drawRect`, and neighbouring ASCII
  cells (`0x20`–`0x7e`) sharing a style merge into one `Paragraph`. Anything
  outside that range still draws per cell, because a fallback font can return a
  glyph of a different advance and shift the rest of a run out of its column.
- `ParagraphCache` evicts generationally and disposes what it drops; lookups are
  verified against the entry's actual text and style, not just its hash.
- Cursor blink moved into `RenderTerminal` (its own `Timer` calling
  `markNeedsPaint`). The app no longer rebuilds to blink.
- `RenderTerminal._onTerminalChange` only calls `markNeedsLayout` when the line
  count changed; otherwise it repaints.
- Writes are coalesced in `_XtermTerminalViewState._drain` with a 6 ms budget,
  producing one `Terminal.write` per drain.
- `ByteConsumer` indexes strings via `codeUnitAt` instead of copying each chunk
  through `runes.toList()`.
- `BufferLine` has a `version` counter, bumped by every mutator. The painter
  records a line into a `ui.Picture` once it has been unchanged across two
  frames and replays that instead of re-walking cells.

**Test baseline.** These failures exist on `main` before any of this work and
are not yours to fix (verified by checking out the pre-change tree):

- `packages/xterm/test/src/terminal_test.dart` — `Terminal.mouseInput can handle
  mouse events`
- `packages/xterm/test/src/terminal_view_test.dart` — both `TerminalView.textScaler`
  tests (golden pixel drift, 0.18% and 0.47%)
- `test/active_session_test.dart` — three timeouts

Everything else passes: 116 in `packages/xterm`, 177 in the app. **If your change
breaks a golden that currently passes, the rendering changed — investigate, do
not re-bless the golden.**

**Commands**

```bash
flutter analyze lib packages/xterm       # must be clean of errors
flutter test                             # app suite, from repo root
cd packages/xterm && flutter test        # package suite
cd packages/xterm && dart run bin/xterm_bench.dart   # parse throughput
```

**Commit messages: title only, no body** (repo convention, see `CLAUDE.md`).

**i18n**: any user-facing string must go through `lib/i18n/strings_en.i18n.json`
and `Translations.of(context)`, then `dart run slang`. Only item 7 touches UI
text.

---

## 1. Stop reflowing the whole scrollback on every pinch-zoom frame

**Severity: high.** Almost certainly the largest remaining hitch.

`RenderTerminal._resizeTerminalIfNeeded` (`packages/xterm/lib/src/ui/render.dart:436`)
is called from `_updateViewportSize` (`:419`) during layout whenever the computed
viewport size in cells changes. It calls `Terminal.resize`
(`packages/xterm/lib/src/terminal.dart:353`), which calls `Buffer.resize`
(`packages/xterm/lib/src/core/buffer/buffer.dart:448`), which on any **width**
change calls `reflow` (`:477` → `packages/xterm/lib/src/core/reflow.dart:163`).

`reflow` walks every line in the buffer, builds a whole new `List<BufferLine>`
with `copyFrom` copies, and allocates `line.anchors.toList()` per line. With
`maxLines: 10000` that is a lot of work.

Pinch-zoom drives `setFontSize` on every gesture update
(`lib/widgets/xterm_terminal_view.dart:636`), which changes the cell size, which
changes the column count, which reflows — once per frame for the whole gesture.

Note the resize sent to the **remote** PTY is already debounced
(`lib/widgets/terminal/session_view.dart:251`). The local buffer reflow is not.

**Approach.** Preferred: hold the font size in a value that only commits to the
render object when the gesture settles. `onScaleUpdate` can drive a visual
preview (a `Transform.scale`, or just deferred), and `onScaleEnd` (`:645`)
applies the real `setFontSize`. That gives one reflow per gesture.

If a live-resizing preview turns out to be visually necessary, the fallback is a
debounce on the render side: have `_resizeTerminalIfNeeded` skip the width change
while a resize is "in flight" and apply the last requested size after a short
timer. Be careful — `Terminal.resize` also fires `onResize`, which is what tells
the SSH session its new size, so skipping it entirely changes behaviour.

**Verify.** Pinch-zoom on a session with a full 10k scrollback should stay
smooth. Confirm in DevTools timeline that `reflow` appears once per gesture, not
once per frame.

---

## 2. Skip the platform channel round-trip when the caret has not moved

**Severity: medium.** Two platform messages per frame of output.

`RenderTerminal._notifyEditableRect` (`render.dart:402`) computes `localToGlobal`
(a walk up the ancestor transforms) and calls out to
`TerminalViewState._onEditableRect` (`packages/xterm/lib/src/terminal_view.dart:493`),
which reaches `CustomTextEditState.setEditableRect`
(`packages/xterm/lib/src/ui/custom_text_edit.dart:119`). That method makes **two**
platform channel calls: `setEditableSizeAndTransform` and `setCaretRect`.

`_notifyEditableRect` runs from `_onTerminalChange` (`render.dart:224` and `:227`)
and `_onScroll` (`:208`) — so on every drain while output streams, whenever an
input connection is open.

**Approach.** Cache the last `(rect, caretRect)` pair in `RenderTerminal` and
return early when both are unchanged. Comparing `Rect`s is cheap and they have
value equality. Keep the `localToGlobal` call — it is needed to compute the
comparison — or, better, compare the cheap inputs first (`cursorOffset`, `size`,
`_painter.cellSize`) and only do `localToGlobal` when one differs.

**Verify.** Existing tests cover IME behaviour in
`packages/xterm/test/src/terminal_view_test.dart`; they must stay green. Manually
confirm the IME caret still follows the cursor when typing with the soft keyboard
open.

---

## 3. Cache the current line instead of re-indexing it per character

**Severity: medium.** Cost is per written character, so it scales with output.

`Buffer.writeChar` reads `currentLine` (`buffer.dart:140`), which is
`lines[absoluteCursorY]`. That goes through
`IndexAwareCircularBuffer.operator[]` (`packages/xterm/lib/src/utils/circular_buffer.dart:103`),
which runs `RangeError.checkValueInInterval` and then a modulo. `RangeError.check…`
is a real call, not an `assert` — it is **not** stripped in release builds.

**Approach.** Memoise the resolved `BufferLine` on `Buffer`, invalidated whenever
anything that could change `absoluteCursorY` or the line array changes: `_cursorY`
writes, scrollback growth, `lineFeed`, `index`, `resize`, buffer switch,
`clearScrollback`, `replaceWith`.

**This is the riskiest item in the list** — a stale cached line writes characters
into the wrong row, and it will not always be obvious. Prefer a narrow version:
cache only within a single `EscapeParser` write pass, or have the setter for
`_cursorY` be the single invalidation point and make sure every mutation actually
goes through it. Audit `buffer.dart` for direct `_cursorY = …` assignments before
committing to a design.

**Verify.** The `packages/xterm/test/buffer` and `terminal` suites are the safety
net here; they are thorough. Add a test that writes across a `lineFeed` boundary
and across a scrollback eviction.

---

## 4. `getTrimmedLength` scans capacity rather than length

**Severity: low.** Free to fix.

`BufferLine.getTrimmedLength` (`packages/xterm/lib/src/core/buffer/line.dart:280`)
computes `maxCols = _data.length ~/ _cellSize` and, when `cols` is null, scans
from the end of the **allocated capacity** instead of `_length`. Cells past
`_length` are always zero, so the extra iterations find nothing.

Round 1 reduced the allocation granularity (32-cell steps instead of doubling),
so the waste is smaller than it was, but it is still there. Called from `reflow`
and from selection.

**Approach.** Default `cols` to `_length`, and clamp rather than expand.
Double-check callers that pass an explicit `cols` larger than `_length` — the
current clamp to `maxCols` may be load-bearing for one of them.

---

## 5. Hoist the URL `RegExp` out of the tap handler

**Severity: low.** Trivial.

`lib/widgets/xterm_terminal_view.dart:510` builds `RegExp(r'https?://[^\s]+')`
fresh on every tap, and there is a second `RegExp` for trailing punctuation on
the following line. Make both `static final` fields.

---

## 6. Give the cursor its own layer so blinking does not repaint every line

**Severity: low-medium.** Idle battery cost.

`RenderTerminal` is a single repaint boundary (`render.dart:240`) and paints
lines, cursor, selection and highlights into it. The blink timer calls
`markNeedsPaint` roughly every 600 ms, which repaints all visible lines.

After round 1 that is ~50 `drawPicture` calls rather than ~2000 draw calls, so it
is no longer expensive — but it is still a full repaint 1.7 times a second while
the terminal sits idle.

**Approach, cheapest first:**

1. Stop blinking when the terminal has no focus. `_focusNode` is already
   observed (`_onFocusChange`). This alone removes the cost for every background
   tab. Do this one first and measure whether the rest is worth it.
2. Suppress the blink while output is actively arriving — `_resetBlinkPhase`
   already exists and is called from `_onTerminalChange`.
3. Only if still warranted: split the cursor into its own `Layer` so blinking
   composites without repainting the line content. This is a real restructuring
   of `paint` and probably not worth it.

---

## 7. Make the scrollback limit configurable

**Severity: low.** Memory, not speed.

`lib/widgets/xterm_terminal_view.dart:153` hardcodes `maxLines: 10000`, per
session. Each `BufferLine` at 80 columns allocates 96 cells × 4 words × 4 bytes
≈ 1.5 KB, so a full scrollback is ~15 MB per tab.

**Approach.** Add a setting alongside the existing terminal settings (font size,
line height, cursor style — see how those are plumbed through
`XtermTerminalViewController` and `SettingsScreen`). Offer a few presets rather
than a free-form number.

Changing `maxLines` on a live `Terminal` means rebuilding the buffer; check
whether the package supports it or whether the session needs to be recreated. If
it needs a recreation, apply the setting to new sessions only and say so in the
UI.

**i18n**: the setting label, description and preset names all need entries in
`lib/i18n/strings_en.i18n.json`, then `dart run slang`.

---

## 8. Confirm which rendering backend Android is actually using

**Severity: unknown — this is a measurement task, not a change.**

There is no Impeller flag in `android/app/src/main/AndroidManifest.xml` or
`android/gradle.properties`, so the build takes Flutter's default. On recent
Flutter that is Impeller on Vulkan-capable devices with a Skia fallback
otherwise, and the glyph atlas path differs substantially between the two — which
matters a lot for a terminal, since it is almost entirely text.

**Approach.** A/B on the actual target device:

```bash
flutter run --profile                         # default
flutter run --profile --no-enable-impeller    # forced Skia
```

Compare raster thread times in the DevTools timeline. If Impeller is losing on
the target hardware, the manifest flag is how you pin it. Record the numbers
either way — they are worth having written down.

---

## Before you start: get device numbers

Everything above came from reading the code, not from profiling on hardware. No
one has measured this on a real device.

Run `flutter run --profile` on an actual phone and capture DevTools timeline
traces for three scenarios before picking an item:

1. **Idle** with the cursor blinking — tells you whether item 6 matters.
2. **`cat` on a large file** — tells you whether items 2 and 3 matter, and
   whether the 6 ms drain budget in `_drain` is tuned right.
3. **Pinch-zoom on a full scrollback** — tells you how bad item 1 really is.

If the traces show the raster thread saturated rather than the UI thread, items
1–5 will not help much and item 8 becomes the priority instead.
