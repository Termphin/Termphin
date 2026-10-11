import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The widgets the framework rebuilt while [action] ran, one entry each.
///
/// A field whose `onChanged` calls `setState` marks its whole screen dirty,
/// so a keystroke rebuilds every widget on it - the input itself included.
/// That is invisible to an ordinary widget test, which sees the same pixels
/// either way, so this records the rebuilds instead.
Future<List<String>> recordRebuilds(
  WidgetTester tester,
  Future<void> Function() action,
) async {
  final built = <String>[];
  final previousPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null && message.startsWith('Building ')) built.add(message);
  };
  debugPrintRebuildDirtyWidgets = true;
  try {
    await action();
  } finally {
    debugPrintRebuildDirtyWidgets = false;
    debugPrint = previousPrint;
  }
  return built;
}

/// Whether any widget whose description starts with [name] was rebuilt.
bool rebuilt(List<String> records, String name) =>
    records.any((r) => r.startsWith('Building $name'));
