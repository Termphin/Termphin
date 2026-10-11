import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../analytics/analytics_service.dart';

/// One persisted preference: its key, its default, how it is read back, and
/// its current value.
///
/// Every setting in the app used to be a hand-written `loadX()`/`saveX()`
/// pair plus, for the ones anything had to react to, a loose top-level
/// `ValueNotifier` that each writer had to remember to update. Three of those
/// four pieces are the same every time, and the one that is not - clamping,
/// falling back when a stored value is no longer a legal one - is where the
/// bugs were. A [Setting] carries all four together, so a value cannot be
/// written without being broadcast and cannot be read back out of range.
///
/// It is a [ValueNotifier], so anything already built to depend on one -
/// `ValueListenableBuilder`, `Listenable.merge`, a Riverpod notifier - can
/// listen without an adapter.
class Setting<T> extends ValueNotifier<T> {
  Setting({
    required this.key,
    required this.fallback,
    required T Function(SharedPreferences preferences) read,
    required Future<void> Function(SharedPreferences preferences, T value)
    write,
    this.track = true,
    Object? Function(T value)? describe,
  }) : _read = read,
       _write = write,
       _describe = describe,
       super(fallback);

  final String key;

  /// Whether a write reports itself to analytics.
  ///
  /// Off for the settings that are a side effect of a gesture rather than a
  /// choice - the action dock's position is rewritten at the end of every
  /// drag, and counting those says nothing about which settings people use.
  final bool track;

  final Object? Function(T value)? _describe;

  /// What the setting reads as before anything has been stored, and whatever
  /// a stored value that is no longer legal falls back to.
  final T fallback;

  final T Function(SharedPreferences preferences) _read;
  final Future<void> Function(SharedPreferences preferences, T value) _write;

  /// Reads the stored value into [value]. Until this runs the setting reads
  /// as its [fallback], which is why `loadAppSettings()` runs before the
  /// first frame.
  Future<T> load() async {
    value = _read(await SharedPreferences.getInstance());
    return value;
  }

  /// Stores [next] and tells every listener, in that order - a listener that
  /// reacts by reading from disk must not race the write it is reacting to.
  Future<void> set(T next) async {
    await _write(await SharedPreferences.getInstance(), next);
    value = next;
    if (track) {
      unawaited(AnalyticsService.instance.settingChanged(key, analyticsValue));
    }
  }

  /// What a write reports as the new value, or null when nothing about it can
  /// be reduced to a scalar.
  ///
  /// A list reports its length and never its entries: a custom toolbar key is
  /// an escape sequence the user typed, and the point of this is which
  /// settings get changed, not what was put in them.
  Object? get analyticsValue {
    final describe = _describe;
    if (describe != null) return describe(value);
    return switch (value) {
      final bool flag => flag,
      final num number => number,
      final Enum option => option.name,
      final String text => text,
      final Iterable<Object?> entries => entries.length,
      _ => null,
    };
  }

  Future<void> reset() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(key);
    value = fallback;
  }

  static Setting<bool> boolean(
    String key, {
    required bool fallback,
    bool track = true,
  }) => Setting<bool>(
    key: key,
    fallback: fallback,
    track: track,
    read: (preferences) => preferences.getBool(key) ?? fallback,
    write: (preferences, value) => preferences.setBool(key, value),
  );

  /// [min] and [max] are applied on the way out, not on the way in: a stored
  /// value can predate a range that has since narrowed.
  static Setting<double> number(
    String key, {
    required double fallback,
    double? min,
    double? max,
    bool track = true,
  }) => Setting<double>(
    key: key,
    fallback: fallback,
    track: track,
    read: (preferences) {
      final stored = preferences.getDouble(key) ?? fallback;
      return stored.clamp(min ?? stored, max ?? stored).toDouble();
    },
    write: (preferences, value) => preferences.setDouble(key, value),
  );

  static Setting<int> integer(
    String key, {
    required int fallback,
    int? min,
    int? max,
  }) => Setting<int>(
    key: key,
    fallback: fallback,
    read: (preferences) {
      final stored = preferences.getInt(key) ?? fallback;
      return stored.clamp(min ?? stored, max ?? stored);
    },
    write: (preferences, value) => preferences.setInt(key, value),
  );

  /// [allowed], where given, is the set of values that still mean something -
  /// a colour scheme dropped from the app reads as [fallback] rather than
  /// leaving the terminal painted in nothing.
  static Setting<String> text(
    String key, {
    required String fallback,
    Set<String>? allowed,
  }) => Setting<String>(
    key: key,
    fallback: fallback,
    read: (preferences) {
      final stored = preferences.getString(key);
      if (stored == null) return fallback;
      if (allowed != null && !allowed.contains(stored)) return fallback;
      return stored;
    },
    write: (preferences, value) => preferences.setString(key, value),
  );

  /// An enum stored by `name`, so a reordered enum does not reinterpret what
  /// is already on disk.
  static Setting<E> option<E extends Enum>(
    String key, {
    required E fallback,
    required List<E> values,
    bool track = true,
  }) => Setting<E>(
    key: key,
    fallback: fallback,
    track: track,
    read: (preferences) {
      final stored = preferences.getString(key);
      for (final option in values) {
        if (option.name == stored) return option;
      }
      return fallback;
    },
    write: (preferences, value) => preferences.setString(key, value.name),
  );

  /// [accept] filters entries that no longer parse - a custom key whose
  /// encoding changed, an action removed from the app - rather than letting
  /// one bad entry throw away the list.
  static Setting<List<String>> textList(
    String key, {
    List<String> fallback = const [],
    bool Function(String entry)? accept,
  }) => Setting<List<String>>(
    key: key,
    fallback: fallback,
    read: (preferences) {
      final stored = preferences.getStringList(key);
      if (stored == null) return fallback;
      return accept == null ? stored : stored.where(accept).toList();
    },
    write: (preferences, value) => preferences.setStringList(key, value),
  );
}
