import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kErrorReportsPrefsKey = 'error_reports';

/// One uncaught error, as kept on the device until the user sends or
/// clears it.
///
/// [count] is how many times the same error came back to back: a broken
/// widget throws on every frame, and one entry saying so beats a list
/// flooded with copies.
class ErrorReport {
  const ErrorReport({
    required this.time,
    required this.message,
    required this.stack,
    this.count = 1,
  });

  factory ErrorReport.fromJson(Map<String, Object?> json) => ErrorReport(
    time: DateTime.parse(json['time']! as String),
    message: json['message']! as String,
    stack: json['stack']! as String,
    count: json['count'] as int? ?? 1,
  );

  final DateTime time;
  final String message;
  final String stack;
  final int count;

  Map<String, Object?> toJson() => {
    'time': time.toIso8601String(),
    'message': message,
    'stack': stack,
    'count': count,
  };

  ErrorReport repeated() =>
      ErrorReport(time: time, message: message, stack: stack, count: count + 1);

  String format() {
    final times = count > 1 ? ' (x$count)' : '';
    return '${time.toIso8601String()}$times\n$message\n$stack'.trimRight();
  }
}

/// Uncaught errors kept on the device so the user can send them with a bug
/// report - alongside PostHog's error tracking, not instead of it.
///
/// Works with analytics off and nothing ever leaves the device unless the
/// user sends it. Stored in shared preferences rather than memory so an
/// error that took the app down is still there after the restart. Capped at
/// [capacity] reports with the stack cut to [maxStackLines] frames; a
/// dropped socket, ordinary for an SSH client, is not an error worth
/// reporting and is skipped, as PostHog does.
class ErrorReports extends ChangeNotifier {
  ErrorReports({this.capacity = 20, this.maxStackLines = 20});

  static final ErrorReports instance = ErrorReports();

  final int capacity;
  final int maxStackLines;
  List<ErrorReport> _reports = const [];

  /// Newest first.
  List<ErrorReport> get reports => _reports;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(kErrorReportsPrefsKey);
    if (raw == null) return;
    try {
      _reports = [
        for (final item in jsonDecode(raw) as List)
          ErrorReport.fromJson((item as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      _reports = const [];
    }
    notifyListeners();
  }

  Future<void> record(Object error, StackTrace? stack, {DateTime? time}) async {
    if (error is SocketException) return;
    final message = error.toString().trim();
    final frames = (stack ?? StackTrace.empty)
        .toString()
        .trimRight()
        .split('\n')
        .take(maxStackLines)
        .join('\n');
    final latest = _reports.firstOrNull;
    if (latest != null && latest.message == message && latest.stack == frames) {
      _reports = [latest.repeated(), ..._reports.skip(1)];
    } else {
      _reports = [
        ErrorReport(
          time: time ?? DateTime.now(),
          message: message,
          stack: frames,
        ),
        ..._reports,
      ].take(capacity).toList();
    }
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    _reports = const [];
    notifyListeners();
    await _save();
  }

  /// Every report as one text, newest first, under [header].
  String export({required String header}) =>
      [header, for (final report in _reports) report.format()].join('\n\n');

  Future<void> _save() async {
    final preferences = await SharedPreferences.getInstance();
    if (_reports.isEmpty) {
      await preferences.remove(kErrorReportsPrefsKey);
    } else {
      await preferences.setString(
        kErrorReportsPrefsKey,
        jsonEncode([for (final report in _reports) report.toJson()]),
      );
    }
  }

  /// Hooks into `FlutterError.onError` and `PlatformDispatcher.onError`,
  /// handing every error on to whatever handled it before. Called from
  /// `main` before PostHog starts; PostHog chains to the handler it finds,
  /// so both see every error.
  void install() {
    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      unawaited(record(details.exception, details.stack));
      previousFlutterError?.call(details);
    };

    final dispatcher = PlatformDispatcher.instance;
    final previousPlatformError = dispatcher.onError;
    dispatcher.onError = (error, stack) {
      unawaited(record(error, stack));
      return previousPlatformError?.call(error, stack) ?? false;
    };
  }
}
