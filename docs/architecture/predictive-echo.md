# Predictive echo

mosh-style local echo. Read this before touching the engine, and run `test/services/terminal/predictive_echo_fuzz_test.dart` after every change.

`PredictiveEcho` (`lib/services/terminal/predictive_echo.dart`) is mosh's
local echo: typed characters are drawn before the server's echo arrives. It
lives here, not in `terminal_view` - the public package only exposes the
generic hooks it is built on, `Terminal.overlay` (`TerminalOverlay`) and
`Terminal.onAfterWrite`. **Keep the engine out of that repo.**

**`predictive_echo_fuzz_test.dart` is the arbiter.** A fake readline/zsh shell
(autosuggestions, a `sudo` password, jobs finishing mid-typing), random keys,
latency with spikes, and an oracle terminal: nothing on screen may disagree
with a state the server actually passes through, and nothing may be left once
it goes quiet. Every rule below came out of a failing seed. Change the engine,
run it; a new behaviour gets a fake-shell mode.

- **Fed from `SshSessionManager.sendInput`**, via `ActiveSessionView.inputStream`
  (sync, numbered), not from `Terminal.onOutput`: the session's Shift/Alt/Ctrl
  modes rewrite bytes after the terminal emits them, and snippets bypass the
  terminal entirely. It has to see what the server sees.
- **The cursor is tracked, never re-read mid-flight.** The screen shows the
  state before whatever keys are still travelling, so reading the cursor off it
  while any are is reading a stale position - that was the "cursor does not
  move" and garbage-in-the-prompt class of bug. Any key with an unknowable
  effect (Enter, Tab, right arrow, any control key or escape, a paste) stops
  prediction until the server has **caught up**, and only then is the cursor
  re-read.
- **Caught up is known from receipts.** After a write, `sendInput` sends a
  keepalive (`SshService.confirmReceipt`) - sshd answers it in order behind the
  channel data, so its reply means everything before it arrived; one out at a
  time, later input covered by the next. `inputReceipts` hands the numbers to
  `PredictiveEcho.acknowledge`. 120ms of grace after a receipt covers the
  program's own echo following it. Without receipts the fallback is max(1s,
  4x echo time) of quiet - safe, predicts far less.
- **What is predicted**: printable keys at the end of the text; backspace and
  left arrow within what was typed on this line (`_inputStart`), never into the
  prompt. Backspace moves the cursor only - what replaces the character is not
  always a blank (zsh brings the suggestion back). With text after the cursor a
  key is held until its echo, except the character already under the cursor,
  which is typing along a suggestion. "The end" stops at two blanks, so a
  right-hand prompt does not count.
- **Epochs are the safety.** A new epoch, after anything unpredictable, stays
  hidden until one of its predictions is confirmed by output - what keeps a
  password typed after `sudo` off the screen.
- A program cursor on a different row than the predicted one means something
  unforeseen was drawn (a job's `Done` line): everything is dropped. Cells off
  the program's cursor line are judged at once. A prediction that already
  matches the screen is settled at once, credit or not.
- Keyed by `BufferLine`, not screen row, so scrolling output carries them.
- **Shown only on a slow link**, judged from its own echo round trip (over
  60ms on, 40ms off; dimmed over 160ms). On by default for that reason. Off in
  the alt buffer - vim, less, htop - where its timer stops too; keys typed
  there still count as in flight, since the one that quits lands the shell
  somewhere not yet on screen.
- **Never repaints a held frame.** `onChanged` skips the repaint while
  `Terminal.isHoldingFrame` (a synchronized update): a TUI mid-frame shown on
  our say-so is the torn UI that only a resize used to clear.
