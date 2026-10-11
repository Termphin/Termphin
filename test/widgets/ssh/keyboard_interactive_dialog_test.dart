import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/app.dart';
import 'package:termphin/i18n/strings.g.dart';
import 'package:termphin/services/ssh/ssh_prompts.dart';
import 'package:termphin/theme/theme.dart';
import 'package:termphin/widgets/ssh/keyboard_interactive_dialog.dart';

KeyboardInteractiveRequest _request({
  String name = '',
  String instruction = '',
  List<KeyboardInteractiveQuestion> questions = const [
    KeyboardInteractiveQuestion(prompt: 'Verification code:', echo: true),
  ],
}) => KeyboardInteractiveRequest(
  name: name,
  instruction: instruction,
  questions: questions,
);

Future<void> _pumpHost(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        navigatorKey: navigatorKey,
        theme: AppTheme.darkTheme,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    ),
  );
}

bool _obscured(WidgetTester tester, String label) {
  final field = tester.widget<TextField>(
    find.ancestor(of: find.text(label), matching: find.byType(TextField)),
  );
  return field.obscureText;
}

void main() {
  final t = AppLocale.en.buildSync();

  testWidgets('with no navigator the round is cancelled, not answered', (
    tester,
  ) async {
    expect(navigatorKey.currentContext, isNull);
    expect(await showKeyboardInteractivePrompt(_request()), isNull);
  });

  testWidgets('asks the server\'s question and returns what was typed', (
    tester,
  ) async {
    await _pumpHost(tester);
    final answer = showKeyboardInteractivePrompt(_request());
    await tester.pumpAndSettle();

    expect(find.text('Verification code:'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text(t.keyboardInteractive.submit));
    await tester.pumpAndSettle();

    expect(await answer, ['123456']);
  });

  testWidgets('cancelling answers null rather than an empty string', (
    tester,
  ) async {
    await _pumpHost(tester);
    final answer = showKeyboardInteractivePrompt(_request());
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.common.cancel));
    await tester.pumpAndSettle();
    expect(await answer, isNull);
  });

  testWidgets('a tap outside decides nothing', (tester) async {
    await _pumpHost(tester);
    var answered = false;
    final answer = showKeyboardInteractivePrompt(_request()).then((value) {
      answered = true;
      return value;
    });
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(answered, isFalse);

    await tester.tap(find.text(t.common.cancel));
    await tester.pumpAndSettle();
    expect(await answer, isNull);
  });

  testWidgets('answers several questions in the order they were asked', (
    tester,
  ) async {
    await _pumpHost(tester);
    final answer = showKeyboardInteractivePrompt(
      _request(
        questions: const [
          KeyboardInteractiveQuestion(prompt: 'Password:', echo: false),
          KeyboardInteractiveQuestion(prompt: 'One-time code:', echo: true),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'hunter2');
    await tester.enterText(find.byType(TextField).last, '999111');
    await tester.tap(find.text(t.keyboardInteractive.submit));
    await tester.pumpAndSettle();

    expect(await answer, ['hunter2', '999111']);
  });

  testWidgets('hides a secret and shows one the server says is echoed', (
    tester,
  ) async {
    await _pumpHost(tester);
    showKeyboardInteractivePrompt(
      _request(
        questions: const [
          KeyboardInteractiveQuestion(prompt: 'Password:', echo: false),
          KeyboardInteractiveQuestion(prompt: 'One-time code:', echo: true),
        ],
      ),
    ).ignore();
    await tester.pumpAndSettle();

    expect(_obscured(tester, 'Password:'), isTrue);
    expect(_obscured(tester, 'One-time code:'), isFalse);
  });

  testWidgets('shows the heading and instruction the server sent', (
    tester,
  ) async {
    await _pumpHost(tester);
    showKeyboardInteractivePrompt(
      _request(
        name: 'Password Expired',
        instruction: 'Your password must be changed before you can log in.',
      ),
    ).ignore();
    await tester.pumpAndSettle();

    expect(find.text('Password Expired'), findsOneWidget);
    expect(
      find.text('Your password must be changed before you can log in.'),
      findsOneWidget,
    );
    expect(find.text(t.keyboardInteractive.title), findsNothing);
  });

  testWidgets('falls back to its own wording when the server sends none', (
    tester,
  ) async {
    await _pumpHost(tester);
    showKeyboardInteractivePrompt(
      _request(
        name: '   ',
        instruction: '  ',
        questions: const [KeyboardInteractiveQuestion(prompt: ' ', echo: true)],
      ),
    ).ignore();
    await tester.pumpAndSettle();

    expect(find.text(t.keyboardInteractive.title), findsOneWidget);
    expect(find.text(t.keyboardInteractive.fallbackPrompt), findsOneWidget);
  });

  testWidgets('submitting from the last field is the same as the button', (
    tester,
  ) async {
    await _pumpHost(tester);
    final answer = showKeyboardInteractivePrompt(_request());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '246810');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(await answer, ['246810']);
  });

  testWidgets('an unanswered question comes back as an empty answer', (
    tester,
  ) async {
    await _pumpHost(tester);
    final answer = showKeyboardInteractivePrompt(
      _request(
        questions: const [
          KeyboardInteractiveQuestion(prompt: 'First:', echo: true),
          KeyboardInteractiveQuestion(prompt: 'Second:', echo: true),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'only-the-second');
    await tester.tap(find.text(t.keyboardInteractive.submit));
    await tester.pumpAndSettle();

    expect(await answer, ['', 'only-the-second']);
  });
}
