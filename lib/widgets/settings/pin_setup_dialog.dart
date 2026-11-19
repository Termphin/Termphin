import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../i18n/strings.g.dart';
import '../../services/security/lock_service.dart';
import '../../theme/theme.dart';
import '../../utils/platform_info.dart';
import '../ui/pin_keys.dart';

/// The keypad dialog that chooses and confirms a PIN, used both to turn the
/// lock on and to change an existing PIN.
class PinSetupDialog extends StatefulWidget {
  const PinSetupDialog({super.key});

  @override
  State<PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<PinSetupDialog> {
  String _pin = '';
  String _confirm = '';
  bool _confirming = false;
  String _error = '';

  /// Up to six digits; a six-digit PIN moves on by itself, a shorter one
  /// waits for the tick. The confirmation knows the length and checks on the
  /// last digit.
  void _onDigit(String d) {
    if (_confirming) {
      if (_confirm.length >= _pin.length) return;
      setState(() {
        _confirm += d;
        _error = '';
      });
      if (_confirm.length == _pin.length) _finish();
    } else {
      if (_pin.length >= kMaxPinLength) return;
      setState(() => _pin += d);
      if (_pin.length == kMaxPinLength) _next();
    }
  }

  void _next() {
    if (_pin.length < kMinPinLength) return;
    setState(() => _confirming = true);
  }

  void _onDelete() {
    if (_confirming) {
      if (_confirm.isEmpty) {
        setState(() {
          _confirming = false;
          _confirm = '';
        });
      } else {
        setState(() => _confirm = _confirm.substring(0, _confirm.length - 1));
      }
    } else {
      if (_pin.isNotEmpty) {
        setState(() => _pin = _pin.substring(0, _pin.length - 1));
      }
    }
  }

  void _finish() {
    if (_pin == _confirm) {
      Navigator.of(context).pop(_pin);
    } else {
      setState(() {
        _confirm = '';
        _error = Translations.of(context).lock.pinMismatch;
      });
    }
  }

  /// The PIN can be typed: digits from the row or the number pad, Backspace
  /// to take one back, Enter to go on with a shorter PIN, Esc to cancel.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final digit = pinDigitFor(event);
    if (digit != null) {
      _onDigit(digit);
      return KeyEventResult.handled;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace) {
      _onDelete();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (!_confirming) _next();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final current = _confirming ? _confirm : _pin;
    final t = Translations.of(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kPinDialogMaxWidth),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space20,
              AppTheme.space24,
              AppTheme.space20,
              AppTheme.space16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _confirming ? t.lock.confirmPin : t.lock.setPin,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppTheme.space20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _confirming ? _pin.length : kMaxPinLength,
                    (i) {
                      final filled = i < current.length;
                      final optional = !_confirming && i >= kMinPinLength;
                      return Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.symmetric(
                          horizontal: AppTheme.space8,
                        ),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: filled
                              ? context.colors.primary
                              : context.colors.primary.invisible,
                          border: Border.all(
                            color: filled
                                ? context.colors.primary
                                : optional
                                ? context.colors.surfaceDivider
                                : context.colors.surfaceBorder,
                            width: 2,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (!_confirming) ...[
                  const SizedBox(height: AppTheme.space8),
                  Text(
                    isDesktopPlatform
                        ? t.lock.pinLengthHintDesktop
                        : t.lock.pinLengthHint,
                    style: TextStyle(
                      color: context.colors.textTertiary,
                      fontSize: AppTheme.font12,
                    ),
                  ),
                ],
                const SizedBox(height: AppTheme.space8),
                AnimatedOpacity(
                  opacity: _error.isNotEmpty ? 1 : 0,
                  duration: AppTheme.interactiveDuration,
                  child: Text(
                    _error,
                    style: TextStyle(
                      color: context.colors.error,
                      fontSize: AppTheme.font12,
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.space12),
                for (final row in [
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9'],
                  ['', '0', 'del'],
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppTheme.space2,
                    ),
                    child: Row(
                      children: row.map((k) {
                        if (k.isEmpty) {
                          final ready =
                              !_confirming && _pin.length >= kMinPinLength;
                          return Expanded(
                            child: Opacity(
                              opacity: ready ? 1 : 0,
                              child: _DialogKey(
                                onTap: ready ? _next : () {},
                                child: Tooltip(
                                  message: t.lock.pinNext,
                                  child: Icon(
                                    PhosphorIconsRegular.check,
                                    size: AppTheme.icon20,
                                    color: context.colors.primary,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                        if (k == 'del') {
                          return Expanded(
                            child: _DialogKey(
                              onTap: _onDelete,
                              child: Icon(
                                PhosphorIconsFill.backspace,
                                size: AppTheme.icon18,
                                color: context.colors.textSecondary,
                              ),
                            ),
                          );
                        }
                        return Expanded(
                          child: _DialogKey(
                            child: Text(
                              k,
                              style: TextStyle(
                                fontSize: AppTheme.font20,
                                color: context.colors.textPrimary,
                              ),
                            ),
                            onTap: () => _onDigit(k),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                const SizedBox(height: AppTheme.space8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t.common.cancel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How wide the PIN dialog grows: a keypad, not a form, which on a desktop
/// would otherwise stretch to the dialog theme's width with its keys.
const double kPinDialogMaxWidth = 320;

class _DialogKey extends StatelessWidget {
  const _DialogKey({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space4),
      child: Material(
        color: context.colors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: SizedBox(height: 44, child: Center(child: child)),
        ),
      ),
    );
  }
}
