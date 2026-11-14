import 'package:termphin/services/analytics/analytics_backend.dart';

/// What would have left the device, kept instead of sent.
class RecordingAnalyticsBackend implements AnalyticsBackend {
  /// Every call in order: `enable`, `disable`, `event:<name>`, `error`.
  final calls = <String>[];

  final events = <({String name, Map<String, Object> parameters})>[];

  final errors = <Object>[];

  /// Called for every event as it is logged, for tests that keep their own
  /// tally.
  void Function(String name, Map<String, Object> parameters)? onEvent;

  void clear() {
    onEvent = null;
    calls.clear();
    events.clear();
    errors.clear();
  }

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    calls.add(enabled ? 'enable' : 'disable');
  }

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async {
    calls.add('event:$name');
    events.add((name: name, parameters: parameters));
    onEvent?.call(name, parameters);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  }) async {
    calls.add('error');
    errors.add(error);
  }
}

/// The recorder every test runs against; see `flutter_test_config.dart`.
final analyticsRecorder = RecordingAnalyticsBackend();
