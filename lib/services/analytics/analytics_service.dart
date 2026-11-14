import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase/firebase_service.dart';
import 'analytics_backend.dart';

const kAnalyticsConsentPrefsKey = 'analytics_consent';

/// The only events this app ever sends. Deliberately an enum rather than a
/// free-form string - automatic screen reporting is off and nothing is
/// logged anywhere but through [AnalyticsService.capture], so this list is
/// the event catalog. Google Analytics adds its own automatic events
/// (`first_open`, `session_start`, `user_engagement`) once consent is given;
/// the policy lists those too.
///
/// It is also what the privacy policy's event table is written from, so a name
/// added here without being added there makes the policy wrong.
enum AnalyticsEvent {
  appOpened('app_opened'),

  /// Sent by hand from the places that switch screens, not by automatic
  /// screen reporting, which stays off: the four main destinations are
  /// tabs in one Stack rather than routes, so a navigator observer would miss
  /// them and a mounted-widget hook would report all four at once.
  screenViewed('screen_viewed'),
  settingChanged('setting_changed'),

  /// The activation step. Without it there is no way to tell someone who
  /// installed the app and bounced off an empty list from someone who set a
  /// server up and then could not reach it.
  profileCreated('profile_created'),
  connectionSuccess('connection_success'),
  connectionFailed('connection_failed'),

  /// A connection that was established and then died on its own, which is a
  /// different failure from one that never came up.
  connectionDropped('connection_dropped'),
  sessionResumed('session_resumed'),

  /// Play never reports whether its dialog appeared, let alone what was
  /// rated - that the ask was made is the only measurable part.
  reviewPromptRequested('review_prompt_requested'),
  reviewStoreOpened('review_store_opened'),

  /// The Pro funnel: a hint offered Pro, the paywall opened (and from
  /// where), a plan was tapped, the store said it went through.
  proPromptShown('pro_prompt_shown'),
  paywallViewed('paywall_viewed'),
  purchaseStarted('purchase_started'),
  purchaseCompleted('purchase_completed');

  const AnalyticsEvent(this.eventName);
  final String eventName;
}

/// The complete vocabulary of property names, closed for the same reason
/// [AnalyticsEvent] is: what is sent has to be readable off one list, both to
/// keep the privacy policy honest and to keep a hostname or a path from ever
/// being handed to [AnalyticsService.capture] under an ad-hoc key.
enum AnalyticsProperty {
  screen('screen'),
  setting('setting'),
  value('value'),
  reason('reason'),
  authMethod('auth_method'),
  multiplexer('multiplexer'),
  viaJumpHost('via_jump_host'),
  usedFallback('used_fallback'),
  fallbackCount('fallback_count'),
  portForwards('port_forwards'),
  retry('retry'),

  /// How long the attempt took, in milliseconds. A first connect to a machine
  /// uploads the agent and a later one does not, so without this the two are
  /// one number and there is no way to tell a slow host from a slow install.
  durationMs('duration_ms'),
  agentInstalled('agent_installed'),

  /// How a lost connection was noticed: the keepalive's silence limit, a probe
  /// after a network change or a resume, or the transport closing on its own.
  lostVia('lost_via'),

  /// From a drop being noticed to the session being back, in milliseconds.
  downtimeMs('downtime_ms'),

  /// Whether a reconnect continued the terminal on screen instead of replaying
  /// the session's history into a new one.
  inPlace('in_place'),

  /// Where the paywall was opened from, or which hint was shown: a fixed
  /// name from [ProSource], never anything the user typed.
  source('source'),

  /// `annual`, `monthly` or `lifetime`.
  plan('plan');

  const AnalyticsProperty(this.propertyName);
  final String propertyName;
}

/// Screens, as analytics sees them. Names are ours, not widget class names,
/// so renaming a class does not silently split a funnel in two.
enum AnalyticsScreen {
  home('home'),
  snippets('snippets'),
  snippetRuns('snippet_runs'),
  keyManager('key_manager'),
  settings('settings'),
  terminal('terminal'),
  lock('lock'),
  terminalAppearance('terminal_appearance'),
  toolbarSettings('toolbar_settings'),
  actionDockSettings('action_dock_settings'),
  fastUploadSettings('fast_upload_settings'),
  knownHosts('known_hosts'),
  releaseNotes('release_notes'),
  export('export'),
  sftpEditor('sftp_editor'),
  editorSettings('editor_settings'),
  sftpImagePreview('sftp_image_preview'),
  manual('manual'),

  /// The new or edit machine form, so an abandoned first profile is visible
  /// next to the ones that got saved.
  profileForm('profile_form'),
  serverGuide('server_guide');

  const AnalyticsScreen(this.screenName);
  final String screenName;
}

/// Whether [error] is nothing but a transport closing.
///
/// A dropped SSH socket is this app's ordinary weather, and its message
/// carries the address and port of the machine the user reached, which must
/// not leave the device.
@visibleForTesting
bool isTransportOnlyError(Object error) => error is SocketException;

/// Gates analytics and crash reports behind explicit consent.
///
/// Both are off in the manifest and `Info.plist` until switched on here, so
/// nothing is collected before the user has answered the prompt, or after
/// they turn it off in Settings. Automatic screen reporting and the
/// advertising id stay off either way - only the events in [AnalyticsEvent],
/// captured explicitly through [capture], and the errors handed to
/// [recordError] ever leave the device.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  /// Stands in for Firebase in tests, which watch what would have been sent.
  @visibleForTesting
  static AnalyticsBackend? Function()? backendOverride;

  /// Where events go, or null in a build with no Firebase project, where
  /// analytics is simply off. Firebase may not be up yet; [_ensureStarted]
  /// brings it up when there is consent to act on.
  AnalyticsBackend? get _backend {
    final override = backendOverride;
    if (override != null) return override();
    if (!FirebaseService.instance.available) return null;
    return _firebase ??= FirebaseAnalyticsBackend();
  }

  Future<bool> _ensureStarted() async {
    if (backendOverride != null) return true;
    return FirebaseService.instance.start();
  }

  FirebaseAnalyticsBackend? _firebase;

  /// Whether the user has been asked and, if so, what they answered. Null
  /// means the prompt has never been shown.
  Future<bool?> loadConsent() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(kAnalyticsConsentPrefsKey);
  }

  /// Whether collection is on in this process.
  bool _enabled = false;

  /// This is a singleton, so a test that switches collection on would
  /// otherwise leave it on for every test after it.
  @visibleForTesting
  void resetForTest() => _enabled = false;

  /// Acts on the answer on record. A yes starts Firebase and switches
  /// collection on. Anything else leaves Firebase alone - until something
  /// else starts it, at which point the answer is put in force again, so an
  /// account or push never brings back what was switched off.
  Future<void> init() async {
    final backend = _backend;
    if (backend == null) return;
    FirebaseService.instance.onStart(() async {
      final consent = await loadConsent();
      if (backendOverride == null) await _apply(backend, consent == true);
    });
    if (await loadConsent() != true) return;
    if (!await _ensureStarted()) return;
    if (backendOverride != null) await _apply(backend, true);
  }

  /// Records the user's choice and acts on it immediately - from the initial
  /// prompt, or later from Settings. The `app_opened` for the launch that
  /// asked is already gone by this point; counting it would mean capturing
  /// before the answer.
  Future<void> setConsent(bool granted) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(kAnalyticsConsentPrefsKey, granted);
    final backend = _backend;
    if (backend == null) return;
    if (!await _ensureStarted()) return;
    await _apply(backend, granted);
  }

  Future<void> _apply(AnalyticsBackend backend, bool enabled) async {
    try {
      await backend.setCollectionEnabled(enabled);
      _enabled = enabled;
    } catch (_) {
      _enabled = false;
    }
  }

  /// Captures [event]. A no-op until consent has switched collection on, so
  /// callers never need to check consent first. Callers fire this and forget
  /// it, so a failure (no network, platform channel unavailable in a test) is
  /// swallowed rather than surfacing somewhere unrelated.
  ///
  /// [properties] carries dimensions, never content: an enum name, a flag or
  /// a count. Nothing derived from a host, a username, a path, a command or
  /// an error message goes in one - see [_assertSafe] for the tripwire that
  /// catches the obvious shapes of that in debug. Google Analytics takes no
  /// booleans, so a flag goes out as `true` or `false` spelled out.
  Future<void> capture(
    AnalyticsEvent event, {
    Map<AnalyticsProperty, Object>? properties,
  }) async {
    final backend = _backend;
    if (backend == null || !_enabled) return;
    assert(_assertSafe(properties));
    try {
      await backend.logEvent(event.eventName, {
        for (final MapEntry(key: property, :value)
            in (properties ?? {}).entries)
          property.propertyName: value is bool ? '$value' : value,
      });
    } catch (_) {}
  }

  /// Sends [error] as a crash report, once consent is on. A transport
  /// closing is not a crash and names the machine, so it never goes.
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  }) async {
    final backend = _backend;
    if (backend == null || !_enabled || isTransportOnlyError(error)) return;
    try {
      await backend.recordError(error, stack, fatal: fatal);
    } catch (_) {}
  }

  /// Hands every uncaught error to [recordError] and on to whatever handled
  /// it before. Called from `main` after `ErrorReports.install`, so both see
  /// every error.
  void installErrorHandlers() {
    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      unawaited(
        recordError(details.exception, details.stack, fatal: !details.silent),
      );
      previousFlutterError?.call(details);
    };

    final dispatcher = PlatformDispatcher.instance;
    final previousPlatformError = dispatcher.onError;
    dispatcher.onError = (error, stack) {
      unawaited(recordError(error, stack, fatal: true));
      return previousPlatformError?.call(error, stack) ?? false;
    };
  }

  /// Records that [screen] came to the front.
  Future<void> screen(AnalyticsScreen screen) => capture(
    AnalyticsEvent.screenViewed,
    properties: {AnalyticsProperty.screen: screen.screenName},
  );

  /// Records that a persisted preference was written. Called from
  /// `Setting.set`, so no individual settings screen has to remember to.
  ///
  /// [value] is null for settings whose value is not a single scalar - a
  /// toolbar layout, a list of custom keys - where the count or nothing at
  /// all is all that can be said without shipping what the user typed.
  Future<void> settingChanged(String key, Object? value) => capture(
    AnalyticsEvent.settingChanged,
    properties: {
      AnalyticsProperty.setting: key,
      AnalyticsProperty.value: ?value,
    },
  );

  /// Debug-only shape check on property values.
  ///
  /// Not a proof that nothing sensitive is being sent - only the call sites
  /// can be that - but every string that would carry an address, a path or a
  /// user account has one of these characters in it, so a mistake of that
  /// kind trips here instead of shipping.
  bool _assertSafe(Map<AnalyticsProperty, Object>? properties) {
    if (properties == null) return true;
    for (final entry in properties.entries) {
      final value = entry.value;
      if (value is bool || value is num) continue;
      if (value is String &&
          value.length <= 64 &&
          !value.contains(RegExp(r'[@/\\\n\r]'))) {
        continue;
      }
      debugPrint('Analytics: unsafe value for ${entry.key.propertyName}');
      return false;
    }
    return true;
  }
}
