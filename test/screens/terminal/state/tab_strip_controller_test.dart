import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/screens/terminal/state/tab_strip_controller.dart';
import 'package:termphin/widgets/terminal/session_view.dart';

import '../../../support/fixtures.dart';

void main() {
  final profile = profileFixture();

  TabStripController controllerWith(List<String> ids, {int activeIndex = 0}) =>
      TabStripController(
        sessions: [for (final id in ids) (id, profile)],
        activeIndex: activeIndex,
      );

  group('add and remove', () {
    test('add appends and makes the new tab active', () {
      final controller = controllerWith(['a', 'b']);
      final id = controller.add(profile);

      expect(controller.sessionIds, ['a', 'b', id]);
      expect(controller.active.$1, id);
      expect(controller.activeIndex, 2);
    });

    test('add reuses a given id and lands it beside its split partner', () {
      final controller = controllerWith(['a', 'b']);
      controller.add(profile, sessionId: 'c', splitWith: 'a');

      expect(controller.sessionIds, ['a', 'c', 'b']);
      expect(controller.entries, [
        ['a', 'c'],
        ['b'],
      ]);
    });

    test('removing the active tab moves the selection to what follows it', () {
      final controller = controllerWith(['a', 'b', 'c'], activeIndex: 1);
      controller.dropTabs({'b'}, persist: () {});

      expect(controller.sessionIds, ['a', 'c']);
      expect(controller.active.$1, 'c');
    });

    test(
      'removing a tab before the active one keeps the active one active',
      () {
        final controller = controllerWith(['a', 'b', 'c'], activeIndex: 2);
        controller.dropTabs({'a'}, persist: () {});

        expect(controller.sessionIds, ['b', 'c']);
        expect(controller.active.$1, 'c');
      },
    );

    test('removing a tab after the active one keeps the active one active', () {
      final controller = controllerWith(['a', 'b', 'c'], activeIndex: 0);
      controller.dropTabs({'c'}, persist: () {});

      expect(controller.sessionIds, ['a', 'b']);
      expect(controller.active.$1, 'a');
    });

    test('removing several at once repairs the selection once', () {
      final controller = controllerWith(['a', 'b', 'c', 'd'], activeIndex: 1);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.dropTabs({'b', 'c'}, persist: () {});

      expect(controller.sessionIds, ['a', 'd']);
      expect(controller.active.$1, 'd');
      expect(notifications, 1);
    });

    test('removing the last tab leaves an empty strip', () {
      final controller = controllerWith(['a']);
      controller.dropTabs({'a'}, persist: () {});

      expect(controller.sessionIds, isEmpty);
    });

    test('dropTabs calls persist after the splits are forgotten but before '
        'the sessions are removed', () {
      final controller = controllerWith(['a', 'b']);
      controller.split('b', 'a');
      List<String>? seenIds;
      controller.dropTabs(
        {'a'},
        persist: () {
          seenIds = controller.sessionIds;
        },
      );

      expect(seenIds, ['a', 'b']);
      expect(controller.isSplit('b'), isFalse);
    });

    test('dropTabs is a no-op when none of the ids are open', () {
      final controller = controllerWith(['a', 'b']);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.dropTabs({'z'}, persist: () => fail('must not persist'));

      expect(controller.sessionIds, ['a', 'b']);
      expect(notifications, 0);
    });

    test('forgetFailedRestore calls persist after the session is removed', () {
      final controller = controllerWith(['a', 'b']);
      List<String>? seenIds;
      controller.forgetFailedRestore(
        'a',
        persist: () {
          seenIds = controller.sessionIds;
        },
      );

      expect(seenIds, ['b']);
      expect(controller.sessionIds, ['b']);
    });
  });

  group('select, mode and focus', () {
    test('select moves the active tab and reports the change', () {
      final controller = controllerWith(['a', 'b']);
      final changed = controller.select('b');

      expect(changed, isTrue);
      expect(controller.activeIndex, 1);
    });

    test('select on the already-active tab reports no change and does not '
        'notify', () {
      final controller = controllerWith(['a', 'b']);
      var notifications = 0;
      controller.addListener(() => notifications++);

      final changed = controller.select('a');

      expect(changed, isFalse);
      expect(notifications, 0);
    });

    test('select on an id that is not open returns null', () {
      final controller = controllerWith(['a']);
      expect(controller.select('missing'), isNull);
    });

    test('setMode changes the tab and leaves others alone', () {
      final controller = controllerWith(['a', 'b']);
      controller.setMode('a', SessionViewMode.sftp);

      expect(controller.modeFor('a'), SessionViewMode.sftp);
      expect(controller.modeFor('b'), SessionViewMode.terminal);
    });

    test('setMode to the same mode does not notify', () {
      final controller = controllerWith(['a']);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setMode('a', SessionViewMode.terminal);

      expect(notifications, 0);
    });

    test('focusOf picks whichever of a split last had focus', () {
      final controller = controllerWith(['a', 'b']);
      controller.noteFocus('a');
      controller.noteFocus('b');

      expect(controller.focusOf(['a', 'b']), 'b');
    });

    test('selectEntry resolves the entry to its last-focused tab and always '
        'notifies', () {
      final controller = controllerWith(['a', 'b', 'c']);
      controller.split('b', 'a');
      controller.noteFocus('b');
      var notifications = 0;
      controller.addListener(() => notifications++);

      final id = controller.selectEntry(0);

      expect(id, 'b');
      expect(controller.active.$1, 'b');
      expect(notifications, 1);
    });
  });

  group('reorder', () {
    test('reorder moves a split as one unit', () {
      final controller = controllerWith(['a', 'b', 'c']);
      controller.split('b', 'a');

      final ids = controller.reorder(0, 1);

      expect(ids, ['c', 'a', 'b']);
      expect(controller.entries.first, ['c']);
      expect(controller.entries.last, ['a', 'b']);
    });
  });

  group('split, swap and unsplit', () {
    test('split joins two tabs into one entry', () {
      final controller = controllerWith(['a', 'b', 'c']);
      final ids = controller.split('b', 'a');

      expect(ids, ['a', 'b', 'c']);
      expect(controller.entries, [
        ['a', 'b'],
        ['c'],
      ]);
      expect(controller.isSplit('a'), isTrue);
      expect(controller.isSplit('b'), isTrue);
    });

    test('canJoin refuses a tab already in a split', () {
      final controller = controllerWith(['a', 'b', 'c']);
      controller.split('b', 'a');

      expect(controller.canJoin('c', 'a'), isFalse);
    });

    test('swap trades the two halves and keeps each pane its own size', () {
      final controller = controllerWith(['a', 'b', 'c']);
      controller.split('b', 'a');
      controller.setRatio('a', 0.3);

      final ids = controller.swap('a');

      expect(ids, ['b', 'a', 'c']);
      expect(controller.ratioOf('b'), closeTo(0.7, 1e-9));
    });

    test('unsplit leaves both halves as plain tabs', () {
      final controller = controllerWith(['a', 'b']);
      controller.split('b', 'a');
      controller.unsplit('a');

      expect(controller.isSplit('a'), isFalse);
      expect(controller.isSplit('b'), isFalse);
      expect(controller.entries, [
        ['a'],
        ['b'],
      ]);
    });

    test('setRatio is clamped and shared by both halves', () {
      final controller = controllerWith(['a', 'b']);
      controller.split('b', 'a');
      controller.setRatio('a', 0.01);

      expect(controller.ratioOf('a'), 0.2);
      expect(controller.ratioOf('b'), 0.2);
    });
  });

  group('restoreSplits', () {
    test('restores a saved split between two open tabs', () {
      final controller = controllerWith(['a', 'b', 'c']);
      final changed = controller.restoreSplits([
        (first: 'a', second: 'c', ratio: 0.4),
      ]);

      expect(changed, isTrue);
      expect(controller.entries, [
        ['a', 'c'],
        ['b'],
      ]);
      expect(controller.ratioOf('a'), 0.4);
    });

    test('ignores a pair naming an id that is not open', () {
      final controller = controllerWith(['a', 'b']);
      final changed = controller.restoreSplits([
        (first: 'a', second: 'missing', ratio: 0.4),
      ]);

      expect(changed, isFalse);
      expect(controller.sessionIds, ['a', 'b']);
      expect(controller.isSplit('a'), isFalse);
    });

    test('does not notify when nothing changed', () {
      final controller = controllerWith(['a', 'b']);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.restoreSplits([(first: 'a', second: 'missing', ratio: 0.4)]);

      expect(notifications, 0);
    });
  });

  group('notifications', () {
    test('each mutator notifies exactly once', () {
      final controller = controllerWith(['a', 'b', 'c']);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setMode('a', SessionViewMode.sftp);
      expect(notifications, 1);

      controller.select('b');
      expect(notifications, 2);

      controller.reorder(0, 2);
      expect(notifications, 3);

      controller.split('c', 'a');
      expect(notifications, 4);

      controller.swap('a');
      expect(notifications, 5);

      controller.setRatio('a', 0.3);
      expect(notifications, 6);

      controller.unsplit('a');
      expect(notifications, 7);

      controller.add(profile);
      expect(notifications, 8);
    });
  });
}
