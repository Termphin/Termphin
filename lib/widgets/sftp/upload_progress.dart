/// Bytes sent so far, and the total when the local file's size was known
/// upfront (it always is - the only null case is nothing in flight yet).
class UploadProgress {
  const UploadProgress({
    required this.bytes,
    this.total,
    this.index,
    this.count,
  });

  final int bytes;
  final int? total;

  /// Which file of the batch is in flight, 1-based, and how many there are.
  /// Null for a single-file upload, where a counter would say nothing.
  final int? index;
  final int? count;

  bool get isBatch => (count ?? 1) > 1;

  double? get fraction =>
      total == null || total! <= 0 ? null : (bytes / total!).clamp(0.0, 1.0);
}
