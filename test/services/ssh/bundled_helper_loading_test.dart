import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/services/ssh/remote_agent_service.dart';

/// Assets by path, as a built app would hold them.
class _Assets extends CachingAssetBundle {
  _Assets(this.files);

  final Map<String, List<int>> files;

  @override
  Future<ByteData> load(String key) async {
    final bytes = files[key];
    if (bytes == null) throw FlutterError('Unable to load asset: "$key".');
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

void main() {
  final helper = List<int>.generate(4096, (i) => i % 251);

  test('reads the gzipped helper where the build kept it', () async {
    final assets = _Assets({'a/helper.gz': gzip.encode(helper)});

    expect(await loadBundledHelper(assets, 'a/helper.gz'), helper);
  });

  test('reads the helper an Android build unpacked and renamed', () async {
    final assets = _Assets({'a/helper': helper});

    expect(await loadBundledHelper(assets, 'a/helper.gz'), helper);
  });

  test('a helper missing under both names is still an error', () async {
    expect(
      () => loadBundledHelper(_Assets({}), 'a/helper.gz'),
      throwsA(isA<FlutterError>()),
    );
  });
}
