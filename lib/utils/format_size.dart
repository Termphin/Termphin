String formatFileSize(int? bytes) {
  if (bytes == null) return '';
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  const tb = gb * 1024;
  if (bytes < kb) return '$bytes B';
  if (bytes < mb) return '${(bytes / kb).toStringAsFixed(1)} KB';
  if (bytes < gb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  if (bytes < tb) return '${(bytes / gb).toStringAsFixed(2)} GB';
  return '${(bytes / tb).toStringAsFixed(2)} TB';
}
