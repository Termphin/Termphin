/// Opening a file in the editor means holding all of it at once: the bytes,
/// the decoded string and the editor's own line model, measured at roughly
/// 2.7x the file size (a 192 MB log grew the process by over 500 MB). A phone
/// does not survive that, and a file only reaches the editor because its first
/// 8 KB looked like text - a multi-gigabyte log passes that test easily.
const kMaxEditableBytes = 10 * 1024 * 1024;

/// A null size is a server that did not say, which is not a reason to refuse:
/// virtual files report no size and are tiny, and the read is capped anyway.
bool isTooLargeToEdit(int? size) => size != null && size > kMaxEditableBytes;
