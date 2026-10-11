import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class ClipboardMock {
  String? text;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              text = (call.arguments as Map?)?['text'] as String?;
            case 'Clipboard.getData':
              return text == null ? null : <String, Object?>{'text': text};
          }
          return null;
        });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }
}
