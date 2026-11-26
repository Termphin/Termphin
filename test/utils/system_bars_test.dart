import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/utils/system_bars.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('on Android the app draws under the system bars, so the navigation '
      "bar's height is counted once", () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await drawBehindSystemBars();
    expect(
      calls.where(
        (call) =>
            call.method == 'SystemChrome.setEnabledSystemUIMode' &&
            call.arguments == 'SystemUiMode.edgeToEdge',
      ),
      hasLength(1),
    );
  });

  test('elsewhere the system bars are left alone', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await drawBehindSystemBars();
    expect(calls, isEmpty);
  });
}
