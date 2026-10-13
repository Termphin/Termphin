# SFTP transfers

Downloads, uploads, copy and move, and where a download lands on each platform.

Every SFTP download and upload runs through one path. `CancelToken` stops one:
`isCancelled` for loops, `whenCancelled` so a stalled read aborts mid-chunk, and
`TransferCancelled` whose `toString` is the `sftp.errors.cancelled` key so
`resolveSftpError` needs no special case. `SftpService` reports bytes, not
fractions - the bar needs sizes and a rate. `DownloadService` turns that into
`TransferProgress`.

**Transfers wait in the session's `TransferQueue`** (`transferQueueProvider`,
keyed by session id) and run one at a time: uploads and downloads from the
browser, the image preview and the terminal, copies and moves too. Nothing
blocks the screen. Every question - overwrite, conflicts, the destination - is
asked before a job is queued, so a waiting job never needs the user, and paths
are settled then too, since the browser may have moved on when it runs. A copy
or move lists its destination and plans names only when it starts, so two
queued into one folder do not pick the same name. A running copy or move
cannot be cancelled; a waiting one can. The queue lives as long as the session
view watches it: closing the tab cancels what is left.

`TransferBar` shows it, drawn like the fast upload strip it replaced and
pinned under the tab strip over both the terminal (laid over, so the terminal
is never resized) and the browser (pushed down, so the path bar stays
visible). Tapping it drops the full list over the content; back folds it away
first. A job that ends well or is cancelled leaves the list at once - its
notification already says so - while a failed one stays, the bar red, until
cleared.

A terminal upload that ends while its terminal is out of sight keeps its paths
and offers them at the cursor when the terminal is back. It types them in
unasked (`uploadAutoPasteSetting`) only if it never waited in the queue and
nothing was typed meanwhile - `uploadPasteAction` decides.

Folders are always walked and copied file by file - no server-side `zip`/`tar`
packing.

**Copy and move never pass through the device** (`sftp_remote_ops.dart`).
SFTP v3 has no copy, so a copy is `cp -RPp` (or `Copy-Item` when the SFTP path
is `/C:/...`) over an exec channel; a move is an SFTP rename, falling back to
`mv`/`Move-Item` when the server refuses one across filesystems. The OpenSSH
`copy-data` extension was considered and dropped: dartssh2 keeps extended
requests and file handles private, and 8.x servers lack it. An account locked
to `internal-sftp` has no shell, so the first copy probes for one (stdin
closed at once, or `internal-sftp` waits on it forever) and copy is withdrawn
for that session - never a silent fallback through the phone. Picked with
`showSftpFolderPicker`; clashes are asked once for the whole batch. The walk is a long silence before any byte moves, so it reports a
`scanning` phase with a running count rather than sitting at 0%.

`DownloadLocation`: on Android, unset means the platform Downloads folder
(MediaStore on Q+), otherwise a SAF tree URI with a persisted grant. Only the
URI is stored - on Android 11+ a path outside the sandbox means nothing. The
grant is re-verified once per launch and on every save; a `FOLDER_UNAVAILABLE`
drops the setting and retries into Downloads rather than failing the transfer.
`DownloadChannel.kt` owns the picker, the `DocumentsContract` writes and the
notifications - which track their own ids so the group summary is cancelled with
the last child, and clear leftover progress notifications at startup.

On iOS the folder is not configurable: downloads land in the documents
directory's Downloads folder, and tapping one opens a share sheet via
`SharePlus` (pass `sharePositionOrigin` to anchor iPad popovers). Completion is
announced by `LocalNotificationsService`; a multi-file selection announces once
with a count, because local notifications carry a fixed id and one per entry
would overwrite itself.
