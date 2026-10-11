import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:terminal_view/terminal_view.dart';

import 'package:termphin/services/settings/terminal_settings.dart';
import 'package:termphin/theme/theme.dart';
import 'package:termphin/widgets/terminal/action_dock_menu.dart';
import 'package:termphin/widgets/terminal/terminal_scheme_theme.dart';
import 'package:termphin/widgets/ui/action_dock_tile.dart';

double _channel(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  // Both the chrome scheme and the settings behind it are process-wide, so
  // each test starts from unread and from the stored defaults.
  setUp(() async {
    resetTerminalChromeScheme();
    SharedPreferences.setMockInitialValues({});
    await terminalSettings.load();
  });

  test('every listed scheme resolves to its own colours', () {
    final seen = <String, TerminalColorScheme>{};
    for (final id in kTerminalSchemeLabels.keys) {
      final scheme = AppTheme.terminalSchemeForId(id);
      if (id != 'default') {
        // A missing case in `terminalSchemeForId` silently falls through to
        // the default, which is exactly what this catches.
        expect(
          scheme,
          isNot(same(AppTheme.terminalSchemeDefault)),
          reason: 'scheme "$id" falls back to the default',
        );
      }
      seen[id] = scheme;
    }
    expect(seen.length, kTerminalSchemeLabels.length);
  });

  test('the chrome palette a scheme implies stays readable', () {
    for (final id in kTerminalSchemeLabels.keys) {
      final scheme = AppTheme.terminalSchemeForId(id);
      final c = AppColors.fromTerminalScheme(scheme);

      expect(c.backgroundPrimary, scheme.background);
      expect(c.textPrimary, scheme.foreground);
      expect(
        _contrast(c.textPrimary, c.backgroundPrimary),
        greaterThan(4.5),
        reason: '$id body text',
      );
      // Faded, but never past the floor the palette holds itself to.
      expect(
        _contrast(c.textTertiary, c.backgroundPrimary),
        greaterThan(2.9),
        reason: '$id muted text',
      );
      expect(
        _contrast(c.textSecondary, c.backgroundPrimary),
        greaterThan(3.9),
        reason: '$id secondary text',
      );
      // Same rule as the app palettes: a hint, not an outline.
      expect(
        _contrast(c.surfaceBorder, c.surfaceCard),
        lessThan(1.5),
        reason: '$id border',
      );
      expect(
        _contrast(c.surfaceBorderStrong, c.surfaceCard),
        greaterThan(_contrast(c.surfaceBorder, c.surfaceCard)),
        reason: '$id strong border',
      );
    }
  });

  test('a light scheme yields a light chrome, a dark one a dark chrome', () {
    expect(
      AppColors.fromTerminalScheme(AppTheme.terminalSchemeGruvboxLight).isDark,
      isFalse,
    );
    expect(
      AppColors.fromTerminalScheme(
        AppTheme.terminalSchemeCatppuccinLatte,
      ).isDark,
      isFalse,
    );
    expect(
      AppColors.fromTerminalScheme(AppTheme.terminalSchemeDracula).isDark,
      isTrue,
    );
  });

  testWidgets('the terminal subtree is painted in the selected scheme', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kTerminalSchemePrefsKey: 'gruvbox-light',
    });
    await terminalSettings.load();

    late AppColors seen;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: TerminalSchemeTheme(
          child: Builder(
            builder: (context) {
              seen = context.colors;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    // The setting is read before the first frame, so the chrome is painted
    // in the scheme straight away rather than flashing the app palette first.
    expect(
      seen.backgroundPrimary,
      AppTheme.terminalSchemeGruvboxLight.background,
    );
    expect(seen.isDark, isFalse);
  });

  testWidgets('system bar icons follow a light scheme under a dark app', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kTerminalSchemePrefsKey: 'gruvbox-light',
    });
    await terminalSettings.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        // What app.dart puts above every screen.
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: AppTheme.systemOverlayStyleFor(context.colors),
          child: child!,
        ),
        home: const TerminalSchemeTheme(child: SizedBox.expand()),
      ),
    );

    // Where the engine samples them: the top and bottom edges of the view.
    final size = tester.view.physicalSize;
    final layer = tester.binding.renderViews.first.debugLayer!;
    final status = layer.find<SystemUiOverlayStyle>(Offset(size.width / 2, 1));
    final navigation = layer.find<SystemUiOverlayStyle>(
      Offset(size.width / 2, size.height - 1),
    );
    expect(status?.statusBarIconBrightness, Brightness.dark);
    expect(navigation?.systemNavigationBarIconBrightness, Brightness.dark);
  });

  testWidgets('switching the scheme repaints the chrome with it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({kTerminalSchemePrefsKey: 'nord'});
    await terminalSettings.load();

    late AppColors seen;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: TerminalSchemeTheme(
          child: Builder(
            builder: (context) {
              seen = context.colors;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(seen.backgroundPrimary, AppTheme.terminalSchemeNord.background);

    await terminalSettings.scheme.set('dracula');
    await tester.pumpAndSettle();

    expect(seen.backgroundPrimary, AppTheme.terminalSchemeDracula.background);
  });

  testWidgets('what the terminal opens outside its own subtree follows too', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kTerminalSchemePrefsKey: 'gruvbox-light',
    });
    await terminalSettings.load();

    final buttonKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: TerminalSchemeTheme(
          child: Builder(
            builder: (context) => Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: TextButton(
                  key: buttonKey,
                  onPressed: () {
                    final box =
                        buttonKey.currentContext!.findRenderObject()
                            as RenderBox;
                    showActionDockMenu(
                      context,
                      anchorRect: box.localToGlobal(Offset.zero) & box.size,
                      tools: [
                        SpotlightTool(
                          icon: Icons.bolt,
                          label: 'Paste',
                          onSelect: () {},
                        ),
                      ],
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The menu is an overlay entry at the root, which inherits nothing from
    // where it was opened.
    final tileContext = tester.element(find.byType(ActionDockTile).first);
    expect(
      tileContext.colors.backgroundPrimary,
      AppTheme.terminalSchemeGruvboxLight.background,
    );
  });

  test('a light scheme keeps its bright colours lighter, not darker', () {
    const pairs = {
      'black': 'brightBlack',
      'red': 'brightRed',
      'green': 'brightGreen',
      'yellow': 'brightYellow',
      'blue': 'brightBlue',
      'magenta': 'brightMagenta',
      'cyan': 'brightCyan',
      'white': 'brightWhite',
    };

    for (final id in kTerminalSchemeLabels.keys) {
      final s = AppTheme.terminalSchemeForId(id);
      if (_luminance(s.background) < 0.4) continue;

      final base = <String, Color>{
        'black': s.black,
        'red': s.red,
        'green': s.green,
        'yellow': s.yellow,
        'blue': s.blue,
        'magenta': s.magenta,
        'cyan': s.cyan,
        'white': s.white,
      };
      final bright = <String, Color>{
        'brightBlack': s.brightBlack,
        'brightRed': s.brightRed,
        'brightGreen': s.brightGreen,
        'brightYellow': s.brightYellow,
        'brightBlue': s.brightBlue,
        'brightMagenta': s.brightMagenta,
        'brightCyan': s.brightCyan,
        'brightWhite': s.brightWhite,
      };

      pairs.forEach((dim, lit) {
        // On a light page a "bright" colour that is darker than its base
        // reads as heavier, not brighter - backwards from what the escape
        // code means.
        expect(
          _luminance(bright[lit]!),
          greaterThanOrEqualTo(_luminance(base[dim]!)),
          reason: '$id $lit is darker than $dim',
        );
      });

      // Black is the one that should be heavy; nothing else may be.
      expect(_contrast(s.black, s.background), greaterThan(7), reason: id);
      for (final entry in base.entries) {
        if (entry.key == 'black') continue;
        expect(
          _contrast(entry.value, s.background),
          lessThan(6.5),
          reason: '$id ${entry.key} is muddy on a light background',
        );
      }
    }
  });

  testWidgets('hiding and showing the terminal leaves a full-screen program '
      'its scroll', (tester) async {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add)
      ..write('\x1b[?1049h\x1b[?1000h\x1b[?1006h');
    late StateSetter rebuildShell;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuildShell = setState;
            return TerminalSchemeTheme(
              child: Scaffold(body: TerminalView(terminal)),
            );
          },
        ),
      ),
    );
    rebuildShell(() {});
    await tester.pumpAndSettle();

    await tester.drag(find.byType(TerminalView), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(output.join(), contains('\x1b[<65;'));
  });
}
