import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import '../../services/assistant/assistant_session.dart';
import '../../theme/theme.dart';
import '../pro/feature_demos.dart';
import 'assistant_overlay.dart';
import 'assistant_panel.dart';

/// Phin at work, for "How it works" and the what's-new popup: the app's
/// real terminal screen where a site answers 502, in the phone the user
/// holds, and the real assistant over it playing one task in a loop -
/// asked, it checks nginx and its log, finds the cause, proposes a fix, runs
/// it once approved and folds away - with a camera leaning in on each step.
/// Nothing reaches a server or a model; the conversation is played into a
/// session on a timer. The phones are rendered outside this repository into
/// `assets/feature_demos/<phone>/phin.webp`.
class PhinDemo extends StatefulWidget {
  const PhinDemo({super.key, this.height = defaultHeight, this.look});

  /// How tall it stands where nothing says otherwise.
  static const double defaultHeight = AppTheme.assistantDemoHeight;

  /// How tall it stands; it is as wide as it may be.
  final double height;

  /// The phone to draw; the one the user holds when null.
  final PhoneLook? look;

  @override
  State<PhinDemo> createState() => _PhinDemoState();
}

/// One phone of the demo: the picture's shape, where the screen sits in it
/// as fractions, and the app's screen behind it in logical pixels - its
/// size, the system's insets and the height of the bottom chrome Phin sits
/// above. Printed by the generator that rendered the picture.
class _PhinPhone {
  const _PhinPhone({
    required this.aspect,
    required this.screen,
    required this.size,
    required this.statusBar,
    required this.gestureBar,
    required this.clearance,
  });

  final double aspect;
  final Rect screen;
  final Size size;

  /// The system's insets at the top and bottom of the screen, which the app
  /// pads for itself.
  final double statusBar;
  final double gestureBar;

  EdgeInsets get insets => EdgeInsets.only(top: statusBar, bottom: gestureBar);
  final double clearance;

  /// The whole phone in logical pixels, so its screen is the app's size.
  Size get scene {
    final width = size.width / screen.width;
    return Size(width, width / aspect);
  }

  static const pixel = _PhinPhone(
    aspect: 0.4775,
    screen: Rect.fromLTWH(0.0426, 0.0207, 0.9072, 0.9589),
    size: Size(411.43, 914.29),
    statusBar: 52,
    gestureBar: 24,
    clearance: 130,
  );

  static const iphone = _PhinPhone(
    aspect: 0.4871,
    screen: Rect.fromLTWH(0.0521, 0.02, 0.8967, 0.9595),
    size: Size(430, 932),
    statusBar: 59,
    gestureBar: 34,
    clearance: 140,
  );
}

/// Where the camera looks at a moment of the loop: how close it is - 0 the
/// whole phone, 1 the phone's width filling the frame, more closer still -
/// and the point it centres on, as fractions of the phone.
typedef _Shot = ({int at, double close, Offset focus});

class _PhinDemoState extends State<PhinDemo>
    with SingleTickerProviderStateMixin {
  static const _loop = Duration(milliseconds: 15000);

  /// The camera's path through one loop, like a screen recording edited to
  /// lean in on each step: the question and checks, the proposed fix and its
  /// Run button, the answer, then back out to the whole screen.
  static const List<_Shot> _shots = [
    (at: 0, close: 0, focus: Offset(0.5, 0.5)),
    (at: 2300, close: 0, focus: Offset(0.5, 0.5)),
    (at: 3100, close: 1, focus: Offset(0.5, 0.64)),
    (at: 5600, close: 1, focus: Offset(0.5, 0.62)),
    (at: 6500, close: 1, focus: Offset(0.5, 0.66)),
    (at: 8300, close: 1.25, focus: Offset(0.62, 0.74)),
    (at: 9300, close: 1.25, focus: Offset(0.62, 0.74)),
    (at: 10200, close: 1, focus: Offset(0.5, 0.68)),
    (at: 12000, close: 1, focus: Offset(0.5, 0.68)),
    (at: 12900, close: 0, focus: Offset(0.5, 0.5)),
    (at: 15000, close: 0, focus: Offset(0.5, 0.5)),
  ];

  PhoneLook get _look => widget.look ?? PhoneLook.current;

  _PhinPhone get _phone =>
      _look == PhoneLook.iphone ? _PhinPhone.iphone : _PhinPhone.pixel;

  late final _camera = AnimationController(vsync: this, duration: _loop);

  final _session = AssistantSession(settleAfter: const Duration(seconds: 2));
  final _overlay = GlobalKey<AssistantOverlayState>();
  late final _clearance = ValueNotifier<double>(_phone.clearance);
  final _timers = <Timer>[];
  var _round = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_timers.isEmpty) _play();
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _camera.dispose();
    _session.dispose();
    _clearance.dispose();
    super.dispose();
  }

  void _at(int milliseconds, VoidCallback action) {
    _timers.add(
      Timer(Duration(milliseconds: milliseconds), () {
        if (mounted) action();
      }),
    );
  }

  void _play() {
    final t = Translations.of(context).assistant;
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    _session.reset();
    _overlay.currentState?.minimize();
    setState(() => _round++);
    if (!MediaQuery.disableAnimationsOf(context)) {
      unawaited(_camera.forward(from: 0));
    }

    var nginx = -1, log = -1, fix = -1;
    _at(1600, () => _overlay.currentState?.open());
    _at(2400, () => _session.ask(t.demoAsk));
    _at(3200, () {
      _session.setMood(AssistantMood.working, activity: t.demoCheckNginx);
      nginx = _session.add(
        AssistantCheck(
          title: t.demoCheckNginx,
          command: 'systemctl status nginx',
        ),
      );
    });
    _at(4000, () {
      _session.replace(
        nginx,
        AssistantCheck(
          title: t.demoCheckNginx,
          command: 'systemctl status nginx',
          status: AssistantStepStatus.done,
          output: 'Active: active (running)',
        ),
      );
      _session.setMood(AssistantMood.working, activity: t.demoCheckLog);
      log = _session.add(
        AssistantCheck(
          title: t.demoCheckLog,
          command: 'tail -n 20 /var/log/nginx/error.log',
        ),
      );
    });
    _at(4900, () {
      _session.replace(
        log,
        AssistantCheck(
          title: t.demoCheckLog,
          command: 'tail -n 20 /var/log/nginx/error.log',
          status: AssistantStepStatus.done,
          output: 'connect() failed (111: Connection refused)',
        ),
      );
      _session.setMood(AssistantMood.thinking);
    });
    _at(5700, () => _session.add(AssistantNote(t.demoFound)));
    _at(6600, () {
      fix = _session.add(
        AssistantProposal(
          why: t.demoWhy,
          commands: const [
            'cp /srv/app/.env.bak /srv/app/.env',
            'sudo systemctl restart app',
          ],
        ),
      );
      _session.setMood(AssistantMood.waiting);
    });
    _at(8800, () {
      final step = _session.steps[fix] as AssistantProposal;
      _session.replace(
        fix,
        step.copyWith(state: AssistantProposalState.running),
      );
      _session.setMood(AssistantMood.working);
    });
    _at(9800, () {
      final step = _session.steps[fix] as AssistantProposal;
      _session.replace(fix, step.copyWith(state: AssistantProposalState.done));
      _session.add(AssistantNote(t.demoDone));
      _session.setMood(AssistantMood.done);
    });
    _at(12600, () => _overlay.currentState?.minimize());
    _at(_loop.inMilliseconds, _play);
  }

  /// The camera's transform at [t], 0 to 1 through the loop, for a frame
  /// of [view]: the scene scaled between fitting whole and the shot's
  /// closeness, its focus brought to the middle, centred where it is smaller
  /// than the frame and kept from showing past its edges where larger.
  Matrix4 _cameraAt(double t, Size view) {
    final ms = t * _loop.inMilliseconds;
    var from = _shots.first;
    var to = _shots.last;
    for (var i = 0; i < _shots.length - 1; i++) {
      if (ms >= _shots[i].at && ms <= _shots[i + 1].at) {
        from = _shots[i];
        to = _shots[i + 1];
        break;
      }
    }
    final span = to.at - from.at;
    final k = Curves.easeInOutCubic.transform(
      span == 0 ? 1 : ((ms - from.at) / span).clamp(0.0, 1.0),
    );
    final close = from.close + (to.close - from.close) * k;
    final phone = _phone.scene;
    final fraction = Offset.lerp(from.focus, to.focus, k)!;
    final focus = Offset(fraction.dx * phone.width, fraction.dy * phone.height);
    final fit = math.min(view.width / phone.width, view.height / phone.height);
    final fill = view.width / phone.width;
    final scale = math.max(fit, fit + (fill - fit) * close);
    double place(double viewSide, double sceneSide, double at) {
      final scaled = sceneSide * scale;
      if (scaled <= viewSide) return (viewSide - scaled) / 2;
      return (viewSide / 2 - at * scale).clamp(viewSide - scaled, 0.0);
    }

    return Matrix4.identity()
      ..translateByDouble(
        place(view.width, phone.width, focus.dx),
        place(view.height, phone.height, focus.dy),
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final phone = _phone;
    final scene = phone.scene;
    final media = MediaQuery.of(context);
    final picture = IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/feature_demos/${_look.name}/phin.webp',
              fit: BoxFit.fill,
              gaplessPlayback: true,
            ),
          ),
          Positioned(
            left: phone.screen.left * scene.width,
            top: phone.screen.top * scene.height,
            width: phone.screen.width * scene.width,
            height: phone.screen.height * scene.height,
            child: FittedBox(
              fit: BoxFit.fill,
              child: SizedBox.fromSize(
                size: phone.size,
                child: MediaQuery(
                  data: media.copyWith(
                    size: phone.size,
                    padding: phone.insets,
                    viewPadding: phone.insets,
                    viewInsets: EdgeInsets.zero,
                  ),
                  child: AssistantOverlay(
                    key: _overlay,
                    session: _session,
                    bubbleClearance: _clearance,
                    hintKey: 'demo-$_round',
                    actions: AssistantActions(
                      onSubmit: (_) {},
                      onApprove: (_) {},
                      onSkip: (_) {},
                      onStop: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, box) {
          final view = Size(
            box.maxWidth.isFinite ? box.maxWidth : widget.height * phone.aspect,
            widget.height,
          );
          return SizedBox.fromSize(
            size: view,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              child: AnimatedBuilder(
                animation: _camera,
                builder: (context, child) => Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      width: scene.width,
                      height: scene.height,
                      child: Transform(
                        transform: _cameraAt(_camera.value, view),
                        child: child,
                      ),
                    ),
                  ],
                ),
                child: picture,
              ),
            ),
          );
        },
      ),
    );
  }
}
