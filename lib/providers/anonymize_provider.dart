import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings/anonymize_setting.dart';

class AnonymizeNotifier extends Notifier<bool> {
  @override
  bool build() {
    void publish() => state = anonymizeSetting.value;
    anonymizeSetting.addListener(publish);
    ref.onDispose(() => anonymizeSetting.removeListener(publish));
    return anonymizeSetting.value;
  }

  Future<void> setEnabled(bool enabled) => anonymizeSetting.set(enabled);
}

final anonymizeProvider = NotifierProvider<AnonymizeNotifier, bool>(
  AnonymizeNotifier.new,
);
