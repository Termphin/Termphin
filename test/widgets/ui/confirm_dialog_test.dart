import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:termphin/theme/theme.dart';
import 'package:termphin/widgets/ui/confirm_dialog.dart';

import '../../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host({bool destructive = false, String confirmLabel = 'Confirm'}) {
    return _ConfirmHost(destructive: destructive, confirmLabel: confirmLabel);
  }

  testWidgets('true on confirm', (tester) async {
    await pumpTestApp(tester, host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('true'), findsOneWidget);
  });

  testWidgets('false on cancel', (tester) async {
    await pumpTestApp(tester, host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('false'), findsOneWidget);
  });

  testWidgets('false on barrier dismiss', (tester) async {
    await pumpTestApp(tester, host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('false'), findsOneWidget);
  });

  testWidgets('a destructive confirm button is drawn in the error colour', (
    tester,
  ) async {
    await pumpTestApp(tester, host(destructive: true, confirmLabel: 'Delete'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final button = tester.widget<Text>(find.text('Delete'));
    final context = tester.element(find.text('Delete'));
    expect(button.style?.color, context.colors.error);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
  });

  testWidgets('a non-destructive confirm button keeps the default colour', (
    tester,
  ) async {
    await pumpTestApp(tester, host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final button = tester.widget<Text>(find.text('Confirm'));
    expect(button.style, isNull);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
  });
}

class _ConfirmHost extends StatefulWidget {
  const _ConfirmHost({required this.destructive, required this.confirmLabel});

  final bool destructive;
  final String confirmLabel;

  @override
  State<_ConfirmHost> createState() => _ConfirmHostState();
}

class _ConfirmHostState extends State<_ConfirmHost> {
  bool? _result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ElevatedButton(
            onPressed: () async {
              final confirmed = await showConfirmDialog(
                context,
                title: 'Title',
                message: 'Message',
                confirmLabel: widget.confirmLabel,
                destructive: widget.destructive,
              );
              setState(() => _result = confirmed);
            },
            child: const Text('open'),
          ),
          Text(_result?.toString() ?? 'pending'),
        ],
      ),
    );
  }
}
