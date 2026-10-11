import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/widgets/ui/text_input_dialog.dart';

import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('returns the trimmed text on confirm', (tester) async {
    await pumpTestApp(
      tester,
      const _TextInputHost(initialValue: '  hello  '),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('returns null on cancel', (tester) async {
    await pumpTestApp(tester, const _TextInputHost(initialValue: 'hello'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('null'), findsOneWidget);
  });

  testWidgets('a validator blocks submission', (tester) async {
    await pumpTestApp(
      tester,
      _TextInputHost(
        initialValue: 'hello',
        validator: (value) => 'always invalid',
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('always invalid'), findsOneWidget);
    expect(find.text('pending'), findsOneWidget);
  });

  testWidgets('submitting from the keyboard confirms', (tester) async {
    await pumpTestApp(tester, const _TextInputHost(initialValue: 'hello'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'typed');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('typed'), findsOneWidget);
  });
}

class _TextInputHost extends StatefulWidget {
  const _TextInputHost({required this.initialValue, this.validator});

  final String initialValue;
  final FormFieldValidator<String>? validator;

  @override
  State<_TextInputHost> createState() => _TextInputHostState();
}

class _TextInputHostState extends State<_TextInputHost> {
  String? _result;
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ElevatedButton(
            onPressed: () async {
              final value = await showTextInputDialog(
                context,
                title: 'Rename',
                confirmLabel: 'Save',
                initialValue: widget.initialValue,
                labelText: 'Name',
                validator: widget.validator,
              );
              setState(() {
                _result = value;
                _submitted = true;
              });
            },
            child: const Text('open'),
          ),
          Text(_submitted ? (_result ?? 'null') : 'pending'),
        ],
      ),
    );
  }
}
