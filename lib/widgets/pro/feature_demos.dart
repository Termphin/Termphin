import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import '../../utils/platform_info.dart';

/// Which Pro feature a demo shows.
enum FeatureDemoKind { notifications, live }

/// Which phone a demo is drawn in: the one the user holds, so an iPhone
/// shows an iPhone and everything else a Pixel.
enum PhoneLook {
  pixel,
  iphone;

  static PhoneLook get current =>
      isIOSPlatform || isMacOSPlatform ? PhoneLook.iphone : PhoneLook.pixel;
}

/// A Pro feature shown on the top of a phone, as the store screenshots draw
/// it - the same frames, lock screens and notifications, cut off under the
/// last one. The pictures are rendered from the store deck outside this
/// repository into `assets/feature_demos/<phone>/`.
///
/// Notifications are the locked phone with notices dropping in one by one,
/// a short loop: a backup's notice already there, a deploy's arriving, then
/// an agent waiting, which turns the deploy's "now" into minutes ago. Live
/// status is the app's real home screen, rendered with sample machines and
/// sessions, in the theme's brightness. With less motion asked for, the
/// notifications hold the moment all of them have arrived.
class FeatureDemo extends StatefulWidget {
  const FeatureDemo({super.key, required this.kind, this.look});

  /// How tall the demo stands.
  static const double height = 340;

  /// How long one loop of the notifications takes.
  static const period = Duration(seconds: 10);

  final FeatureDemoKind kind;

  /// The phone to draw; the one the user holds when null.
  final PhoneLook? look;

  @override
  State<FeatureDemo> createState() => _FeatureDemoState();
}

/// Where the pictures of one phone sit, as fractions of the phone's width,
/// measured by the generator when it rendered them.
class _Phone {
  const _Phone({
    required this.aspect,
    required this.notesLeft,
    required this.notesTop,
    required this.notesWidth,
    required this.gap,
    required this.agentHeight,
    required this.noticeHeight,
  });

  /// Width over height of the cut-off phone.
  final double aspect;
  final double notesLeft;
  final double notesTop;
  final double notesWidth;
  final double gap;

  /// The agent's notice runs to two lines on an iPhone.
  final double agentHeight;
  final double noticeHeight;

  static const pixel = _Phone(
    aspect: 0.7759,
    notesLeft: 0.0726,
    notesTop: 0.6659,
    notesWidth: 0.8471,
    gap: 0.014,
    agentHeight: 0.1751,
    noticeHeight: 0.1751,
  );

  static const iphone = _Phone(
    aspect: 0.6908,
    notesLeft: 0.084,
    notesTop: 0.7896,
    notesWidth: 0.8327,
    gap: 0.022,
    agentHeight: 0.2124,
    noticeHeight: 0.1656,
  );
}

/// When each notice comes in, in seconds into the loop.
const _dumpAt = 0.2;
const _deployAt = 1.6;
const _agentAt = 4.2;

class _FeatureDemoState extends State<FeatureDemo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: FeatureDemo.period,
  );

  /// The moment shown when nothing moves: every notification has arrived.
  static const _still = 6.5;

  bool get _animated => widget.kind == FeatureDemoKind.notifications;

  PhoneLook get _look => widget.look ?? PhoneLook.current;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_animated || MediaQuery.disableAnimationsOf(context)) {
      _clock
        ..stop()
        ..value = _still / FeatureDemo.period.inSeconds;
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
    if (_animated) {
      for (final name in _Picture.loop) {
        precacheImage(AssetImage(_Picture.path(_look, name)), context);
      }
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).proDemo;
    final look = _look;
    final phone = look == PhoneLook.iphone ? _Phone.iphone : _Phone.pixel;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: FeatureDemo.height,
      child: Center(
        child: AspectRatio(
          aspectRatio: phone.aspect,
          child: Semantics(
            image: true,
            label: switch (widget.kind) {
              FeatureDemoKind.notifications => t.notifications,
              FeatureDemoKind.live => t.liveScreenshot,
            },
            child: ExcludeSemantics(
              child: switch (widget.kind) {
                FeatureDemoKind.notifications => LayoutBuilder(
                  builder: (context, box) => Stack(
                    children: [
                      Positioned.fill(
                        child: _Picture(look: look, name: _Picture.lock),
                      ),
                      Positioned(
                        left: phone.notesLeft * box.maxWidth,
                        top: phone.notesTop * box.maxWidth,
                        width: phone.notesWidth * box.maxWidth,
                        child: AnimatedBuilder(
                          animation: _clock,
                          builder: (context, _) => _Notices(
                            seconds:
                                _clock.value * FeatureDemo.period.inSeconds,
                            look: look,
                            phone: phone,
                            unit: box.maxWidth,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                FeatureDemoKind.live => _Picture(
                  key: const ValueKey('liveScreenshot'),
                  look: look,
                  name: dark ? _Picture.liveDark : _Picture.liveLight,
                ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the pictures rendered for a phone.
class _Picture extends StatelessWidget {
  const _Picture({super.key, required this.look, required this.name});

  static const lock = 'lock';
  static const liveDark = 'live-dark';
  static const liveLight = 'live-light';
  static const agent = 'note-agent';
  static const deploy = 'note-deploy';
  static const deployNow = 'note-deploy-now';
  static const dump = 'note-dump';
  static const loop = [lock, agent, deploy, deployNow, dump];

  static String path(PhoneLook look, String name) =>
      'assets/feature_demos/${look.name}/$name.webp';

  final PhoneLook look;
  final String name;

  @override
  Widget build(BuildContext context) =>
      Image.asset(path(look, name), fit: BoxFit.fill, gaplessPlayback: true);
}

/// 0 before [start], 1 from [start] plus [length] on, eased in between.
double _arrive(double seconds, double start, [double length = 0.5]) {
  final linear = ((seconds - start) / length).clamp(0.0, 1.0);
  return Curves.easeOutCubic.transform(linear);
}

/// The notices fade at the end of a loop, so it starts over cleanly.
double _loopFade(double seconds) =>
    1 -
    ((seconds - (FeatureDemo.period.inSeconds - 1.2)) / 0.8).clamp(0.0, 1.0);

/// The notices on the lock screen [seconds] into the loop, newest on top.
class _Notices extends StatelessWidget {
  const _Notices({
    required this.seconds,
    required this.look,
    required this.phone,
    required this.unit,
  });

  final double seconds;
  final PhoneLook look;
  final _Phone phone;

  /// The phone's width; every size here is a fraction of it.
  final double unit;

  @override
  Widget build(BuildContext context) {
    final agentArrived = _arrive(seconds, _agentAt, 0.4);
    return Opacity(
      opacity: _loopFade(seconds),
      child: Column(
        children: [
          _arriving(
            key: const ValueKey(_Picture.agent),
            progress: _arrive(seconds, _agentAt),
            height: phone.agentHeight,
            child: _Picture(look: look, name: _Picture.agent),
          ),
          _arriving(
            key: const ValueKey(_Picture.deploy),
            progress: _arrive(seconds, _deployAt),
            height: phone.noticeHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: 1 - agentArrived,
                  child: _Picture(look: look, name: _Picture.deployNow),
                ),
                Opacity(
                  opacity: agentArrived,
                  child: _Picture(look: look, name: _Picture.deploy),
                ),
              ],
            ),
          ),
          _arriving(
            key: const ValueKey(_Picture.dump),
            progress: _arrive(seconds, _dumpAt),
            height: phone.noticeHeight,
            child: _Picture(look: look, name: _Picture.dump),
          ),
        ],
      ),
    );
  }

  /// A notice dropping in from above and taking its place, the ones under
  /// it moving down to make room.
  Widget _arriving({
    required Key key,
    required double progress,
    required double height,
    required Widget child,
  }) {
    return Align(
      key: key,
      alignment: Alignment.topCenter,
      heightFactor: progress,
      child: Opacity(
        opacity: progress,
        child: Transform.translate(
          offset: Offset(0, -unit * 0.06 * (1 - progress)),
          child: Padding(
            padding: EdgeInsets.only(bottom: unit * phone.gap),
            child: SizedBox(height: unit * height, child: child),
          ),
        ),
      ),
    );
  }
}
