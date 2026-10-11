import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/widgets/terminal/terminal_pane.dart';

void main() {
  const cellHeight = 14.4;

  double padding({required double availableHeight}) => terminalBottomPadding(
    availableHeight: availableHeight,
    lineHeight: 1.2,
    cellHeight: cellHeight,
  );

  test('leaves the breathing room under the last line when there is room', () {
    expect(padding(availableHeight: 800), closeTo(4.8, 0.01));
  });

  test('never eats into the last three rows', () {
    final result = padding(availableHeight: cellHeight * 3 + 1.8);

    expect(result, closeTo(1.8, 0.01));
  });

  test('a pane too short for the floor still keeps its padding at zero', () {
    expect(padding(availableHeight: 20), 0);
  });

  test('an unbounded pane is left to its own devices', () {
    expect(padding(availableHeight: double.infinity), closeTo(4.8, 0.01));
  });
}
