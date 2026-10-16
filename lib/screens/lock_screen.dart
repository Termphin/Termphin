import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../i18n/strings.g.dart';
import '../services/analytics/analytics_service.dart';
import '../services/security/lock_service.dart';
import '../theme/theme.dart';

/// Where the PIN entry is: taking digits, checking them, or paused after too
/// many wrong ones.
enum _Phase { entering, checking, lockedOut }

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

/// The keypad is as large as the available height allows: roomy on a phone
/// held upright, still fitting on screen when held sideways.
class _LockScreenState extends State<LockScreen>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  int _pinLength = kMinPinLength;
  String _message = '';
  _Phase _phase = _Phase.entering;
  Duration _lockout = Duration.zero;
  Timer? _countdown;
  bool _biometricEnabled = false;
  bool _faceUnlock = false;
  bool _checkingBiometric = false;

  /// The PIN's length is read before a digit is taken, or a six-digit PIN
  /// typed fast would be checked after four.
  bool _ready = false;

  /// A wrong PIN shakes the dots, the way the system lock screen does.
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: AppTheme.motionShake,
  );

  bool get _keysEnabled =>
      _ready && _phase == _Phase.entering && !_checkingBiometric;

  @override
  void initState() {
    super.initState();
    unawaited(AnalyticsService.instance.screen(AnalyticsScreen.lock));
    unawaited(_start());
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _shake.dispose();
    super.dispose();
  }

  /// A pause from before the app was closed still applies.
  Future<void> _start() async {
    final lockout = await LockService.instance.lockoutRemaining();
    final biometric = await LockService.instance.isBiometricEnabled;
    final length = await LockService.instance.pinLength;
    final face = biometric && await LockService.instance.unlocksWithFace;
    if (!mounted) return;
    setState(() {
      _biometricEnabled = biometric;
      _faceUnlock = face;
      _pinLength = length;
      _ready = true;
    });
    if (lockout > Duration.zero) _startLockout(lockout);
    if (biometric) await _tryBiometric();
  }

  Future<void> _tryBiometric() async {
    if (!_biometricEnabled || _checkingBiometric) return;
    setState(() => _checkingBiometric = true);
    final ok = await LockService.instance.authenticateBiometric();
    if (!mounted) return;
    setState(() => _checkingBiometric = false);
    if (ok) {
      await LockService.instance.resetAttempts();
      _countdown?.cancel();
      widget.onUnlocked();
    }
  }

  void _onDigit(String d) {
    if (!_keysEnabled || _pin.length >= _pinLength) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pin += d;
      _message = '';
    });
    if (_pin.length == _pinLength) unawaited(_verify());
  }

  void _onDelete() {
    if (!_keysEnabled || _pin.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _verify() async {
    setState(() => _phase = _Phase.checking);
    final attempt = await LockService.instance.attemptPin(_pin);
    if (!mounted) return;
    if (attempt.unlocked) {
      widget.onUnlocked();
      return;
    }
    unawaited(HapticFeedback.heavyImpact());
    unawaited(_shake.forward(from: 0));
    final t = Translations.of(context);
    setState(() {
      _pin = '';
      _phase = _Phase.entering;
      _message = attempt.triesLeft > 0
          ? t.lock.incorrectPinTriesLeft(
              n: attempt.triesLeft,
              count: attempt.triesLeft,
            )
          : t.lock.incorrectPin;
    });
    if (attempt.lockout > Duration.zero) _startLockout(attempt.lockout);
  }

  void _startLockout(Duration lockout) {
    _countdown?.cancel();
    final until = DateTime.now().add(lockout);
    setState(() {
      _phase = _Phase.lockedOut;
      _lockout = lockout;
    });
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      final left = until.difference(DateTime.now());
      if (!mounted) return timer.cancel();
      if (left <= Duration.zero) {
        timer.cancel();
        setState(() {
          _phase = _Phase.entering;
          _message = '';
        });
        return;
      }
      setState(() => _lockout = left);
    });
  }

  String _clock(Duration d) {
    final seconds = (d.inMilliseconds / 1000).ceil();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final status = switch (_phase) {
      _Phase.checking => t.lock.checking,
      _Phase.lockedOut => t.lock.tooManyAttempts(time: _clock(_lockout)),
      _Phase.entering => _message,
    };
    final statusColor = _phase == _Phase.checking
        ? colors.textSecondary
        : colors.error;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > constraints.maxHeight;
            final keypadHeight = wide
                ? constraints.maxHeight - 32
                : constraints.maxHeight * 0.52;
            final key = ((keypadHeight - 3 * AppTheme.space14) / 4).clamp(
              52.0,
              80.0,
            );

            final header = _Header(
              pin: _pin,
              length: _pinLength,
              phase: _phase,
              status: status,
              statusColor: statusColor,
              shake: _shake,
            );
            final keypad = _Keypad(
              keySize: key,
              enabled: _keysEnabled,
              showBiometric: _biometricEnabled,
              biometricBusy: _checkingBiometric,
              faceUnlock: _faceUnlock,
              onDigit: _onDigit,
              onDelete: _onDelete,
              onBiometric: _tryBiometric,
            );
            if (wide) {
              return Row(
                children: [
                  Expanded(child: Center(child: header)),
                  Expanded(child: Center(child: keypad)),
                ],
              );
            }
            return Column(
              children: [
                Expanded(child: Center(child: header)),
                keypad,
                SizedBox(height: key * 0.5),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.pin,
    required this.length,
    required this.phase,
    required this.status,
    required this.statusColor,
    required this.shake,
  });

  final String pin;
  final int length;
  final _Phase phase;
  final String status;
  final Color statusColor;
  final Animation<double> shake;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          child: Image.asset('assets/logo.png', width: 84, height: 84),
        ),
        const SizedBox(height: AppTheme.space16),
        Text(
          'Termphin',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppTheme.space6),
        Text(
          t.lock.enterPin,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppTheme.space24),
        AnimatedBuilder(
          animation: shake,
          builder: (context, child) => Transform.translate(
            offset: Offset(
              math.sin(shake.value * math.pi * 6) * 12 * (1 - shake.value),
              0,
            ),
            child: child,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(length, (i) {
              final filled = i < pin.length;
              return AnimatedContainer(
                duration: AppTheme.motionFast,
                width: 16,
                height: 16,
                margin: const EdgeInsets.symmetric(
                  horizontal: AppTheme.space10,
                ),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled
                      ? colors.primary.withValues(
                          alpha: phase == _Phase.checking ? 0.5 : 1,
                        )
                      : colors.primary.invisible,
                  border: Border.all(
                    color: filled ? colors.primary : colors.surfaceBorderStrong,
                    width: 2,
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: AppTheme.space20),
        SizedBox(
          height: 22,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (phase == _Phase.checking) ...[
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: AppTheme.space8),
              ],
              Text(
                status,
                style: TextStyle(color: statusColor, fontSize: AppTheme.font14),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.keySize,
    required this.enabled,
    required this.showBiometric,
    required this.biometricBusy,
    required this.faceUnlock,
    required this.onDigit,
    required this.onDelete,
    required this.onBiometric,
  });

  final double keySize;
  final bool enabled;
  final bool showBiometric;
  final bool biometricBusy;

  /// Face ID rather than a fingerprint, which changes the key's icon.
  final bool faceUnlock;
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final VoidCallback onBiometric;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget digit(String d) => _PadKey(
      size: keySize,
      enabled: enabled,
      onTap: () => onDigit(d),
      child: Text(
        d,
        style: TextStyle(
          fontSize: keySize * 0.38,
          color: colors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    final gap = SizedBox(width: keySize * 0.3);
    return AnimatedOpacity(
      duration: AppTheme.motionSlow,
      opacity: enabled ? 1 : 0.45,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ]) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [digit(row[0]), gap, digit(row[1]), gap, digit(row[2])],
            ),
            const SizedBox(height: AppTheme.space14),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              showBiometric
                  ? _PadKey(
                      size: keySize,
                      enabled: !biometricBusy,
                      plain: true,
                      onTap: onBiometric,
                      child: Icon(
                        faceUnlock
                            ? PhosphorIconsRegular.scanSmiley
                            : PhosphorIconsRegular.fingerprint,
                        size: keySize * 0.42,
                        color: colors.primary,
                      ),
                    )
                  : SizedBox(width: keySize),
              gap,
              digit('0'),
              gap,
              _PadKey(
                size: keySize,
                enabled: enabled,
                plain: true,
                onTap: onDelete,
                child: Icon(
                  PhosphorIconsRegular.backspace,
                  size: keySize * 0.36,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PadKey extends StatelessWidget {
  const _PadKey({
    required this.size,
    required this.enabled,
    required this.onTap,
    required this.child,
    this.plain = false,
  });

  final double size;
  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  /// Delete and biometric: no fill, so the digits read as the keypad.
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox.square(
      dimension: size,
      child: Material(
        color: plain ? colors.backgroundPrimary.invisible : colors.surfaceCard,
        shape: CircleBorder(
          side: plain
              ? BorderSide.none
              : BorderSide(color: colors.surfaceBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Center(child: child),
        ),
      ),
    );
  }
}
