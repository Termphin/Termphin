import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/utils/format_size.dart';

void main() {
  test('null renders as an empty string', () {
    expect(formatFileSize(null), '');
  });

  test('bytes below 1 KiB have no unit scaling', () {
    expect(formatFileSize(0), '0 B');
    expect(formatFileSize(512), '512 B');
    expect(formatFileSize(1023), '1023 B');
  });

  test('kilobytes use one decimal place', () {
    expect(formatFileSize(1024), '1.0 KB');
    expect(formatFileSize(1536), '1.5 KB');
    expect(formatFileSize(1024 * 1024 - 1), '1024.0 KB');
  });

  test('megabytes use one decimal place', () {
    expect(formatFileSize(1024 * 1024), '1.0 MB');
    expect(formatFileSize(1024 * 1024 * 512), '512.0 MB');
  });

  test('gigabytes and above use two decimal places', () {
    expect(formatFileSize(1024 * 1024 * 1024), '1.00 GB');
    expect(formatFileSize(1024 * 1024 * 1024 * 1024), '1.00 TB');
    expect(formatFileSize(3 * 1024 * 1024 * 1024 * 1024), '3.00 TB');
  });
}
