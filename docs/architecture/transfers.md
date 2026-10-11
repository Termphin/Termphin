# SFTP transfers

Downloads, uploads, copy and move, and where a download lands on each platform.

Every SFTP download and upload runs through one path. `CancelToken` stops one:
`isCancelled` for loops, `whenCancelled` so a stalled read aborts mid-chunk, and
`TransferCancelled` whose `toString` is the `sftp.errors.cancelled` key so
`resolveSftpError` needs no special case. `SftpService` reports bytes, not
fractions - the dialog needs sizes and a rate. `DownloadService` turns that into
`TransferProgress`. The dialog closes by removing its own route, never
`Navigator.pop`, so a finished transfer cannot take some other sheet down with
it.

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
