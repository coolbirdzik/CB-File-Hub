import 'package:cb_file_manager/services/tab_activity/tab_activity_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('10 TabActivityManager', () {
    late DateTime fakeNow;
    late TabActivityManager manager;

    setUp(() {
      fakeNow = DateTime(2026, 1, 1, 12, 0, 0);
      manager = TabActivityManager(clock: () => fakeNow);
    });

    tearDown(() {
      try {
        manager.dispose();
      } catch (_) {
        // Tests that already dispose explicitly will throw on second dispose;
        // ignore to keep teardown simple.
      }
    });

    test('10.01 focuses a new tab and tracks it', () {
      manager.onTabFocused('tab1', path: 'C:\\foo');
      expect(manager.focusedTabId, 'tab1');
      expect(manager.stateOf('tab1'), TabActivityState.focused);
      expect(manager.trackedTabCount, 1);
    });

    test('10.02 demotes previously focused tab when focus changes', () {
      manager.onTabFocused('tab1');
      manager.onTabFocused('tab2');

      expect(manager.stateOf('tab1'), TabActivityState.backgroundActive);
      expect(manager.stateOf('tab2'), TabActivityState.focused);
      expect(manager.focusedTabId, 'tab2');
    });

    test('10.03 does not transition to inactive before threshold', () {
      manager.onTabFocused('tab1');
      manager.onTabFocused('tab2'); // tab1 -> background

      // Advance just under threshold for tab1.
      fakeNow = fakeNow.add(const Duration(minutes: 59));
      final transitioned = manager.evaluateInactiveTabs();

      expect(transitioned, isEmpty);
      expect(manager.stateOf('tab1'), TabActivityState.backgroundActive);
    });

    test('10.04 transitions tab to inactive after threshold', () {
      manager.onTabFocused('tab1');
      manager.onTabFocused('tab2'); // tab1 -> background

      fakeNow = fakeNow.add(const Duration(hours: 1, seconds: 1));
      final transitioned = manager.evaluateInactiveTabs();

      expect(transitioned, ['tab1']);
      expect(manager.stateOf('tab1'), TabActivityState.inactive);
      expect(manager.needsReload('tab1'), isTrue);
    });

    test('10.05 does not transition focused tab regardless of age', () {
      manager.onTabFocused('tab1');

      fakeNow = fakeNow.add(const Duration(hours: 5));
      final transitioned = manager.evaluateInactiveTabs();

      expect(transitioned, isEmpty);
      expect(manager.stateOf('tab1'), TabActivityState.focused);
    });

    test('10.06 interaction resets idle counter and prevents inactive', () {
      manager.onTabFocused('tab1');
      manager.onTabFocused('tab2');

      fakeNow = fakeNow.add(const Duration(minutes: 50));
      manager.onTabInteraction('tab1');

      fakeNow = fakeNow.add(const Duration(minutes: 30));
      final transitioned = manager.evaluateInactiveTabs();

      expect(transitioned, isEmpty);
      expect(manager.stateOf('tab1'), TabActivityState.backgroundActive);
    });

    test('10.07 refocusing inactive tab promotes it and flags reload', () {
      manager.onTabFocused('tab1');
      manager.onTabFocused('tab2');

      fakeNow = fakeNow.add(const Duration(hours: 1, seconds: 1));
      manager.evaluateInactiveTabs();
      expect(manager.stateOf('tab1'), TabActivityState.inactive);

      manager.onTabFocused('tab1');
      expect(manager.stateOf('tab1'), TabActivityState.focused);
      expect(manager.consumeReloadFlag('tab1'), isTrue);
      // Reload flag is consumed once.
      expect(manager.consumeReloadFlag('tab1'), isFalse);
    });

    test(
      '10.08 inactive listener fires on transition with last known path',
      () {
        String? receivedTabId;
        String? receivedPath;
        manager.addInactiveListener((tabId, path) {
          receivedTabId = tabId;
          receivedPath = path;
        });

        manager.onTabFocused('tab1', path: 'D:\\videos');
        manager.onTabFocused('tab2');
        fakeNow = fakeNow.add(const Duration(hours: 1, seconds: 1));
        manager.evaluateInactiveTabs();

        expect(receivedTabId, 'tab1');
        expect(receivedPath, 'D:\\videos');
      },
    );

    test('10.09 closing a tab fires close listener and clears tracking', () {
      String? closedTabId;
      manager.addClosedListener((tabId, _) => closedTabId = tabId);

      manager.onTabFocused('tab1', path: 'C:\\a');
      manager.onTabClosed('tab1');

      expect(closedTabId, 'tab1');
      expect(manager.stateOf('tab1'), isNull);
      expect(manager.focusedTabId, isNull);
    });

    test('10.10 snapshotOf reflects current state', () {
      manager.onTabFocused('tab1', path: 'C:\\b');
      final snap = manager.snapshotOf('tab1');
      expect(snap, isNotNull);
      expect(snap!.tabId, 'tab1');
      expect(snap.isFocused, isTrue);
      expect(snap.isInactive, isFalse);
    });

    test('10.11 disposing prevents further state mutations', () {
      manager.onTabFocused('tab1');
      manager.dispose();
      manager.onTabFocused('tab2');
      // After dispose the manager is inert.
      expect(manager.focusedTabId, anyOf(isNull, equals('tab1')));
    });

    test('10.12 changing the threshold at runtime affects evaluation', () {
      manager.onTabFocused('tab1');
      manager.onTabFocused('tab2');

      // Tighten threshold to 10 minutes.
      manager.setInactiveThreshold(const Duration(minutes: 10));

      fakeNow = fakeNow.add(const Duration(minutes: 11));
      final transitioned = manager.evaluateInactiveTabs();

      expect(transitioned, ['tab1']);
      expect(manager.stateOf('tab1'), TabActivityState.inactive);
    });

    test(
      '10.13 zero threshold disables auto-suspend and revives inactive tabs',
      () {
        manager.onTabFocused('tab1');
        manager.onTabFocused('tab2');

        fakeNow = fakeNow.add(const Duration(hours: 1, seconds: 1));
        manager.evaluateInactiveTabs();
        expect(manager.stateOf('tab1'), TabActivityState.inactive);

        manager.setInactiveThreshold(Duration.zero);

        // Disabled: previously inactive tab is revived to background.
        expect(manager.isAutoSuspendEnabled, isFalse);
        expect(manager.stateOf('tab1'), TabActivityState.backgroundActive);

        // Further evaluations are no-ops.
        fakeNow = fakeNow.add(const Duration(hours: 5));
        final transitioned = manager.evaluateInactiveTabs();
        expect(transitioned, isEmpty);
        expect(manager.stateOf('tab1'), TabActivityState.backgroundActive);
      },
    );

    test(
      '10.14 markInactive transitions a background tab and fires listener',
      () {
        String? receivedTabId;
        manager.addInactiveListener((tabId, _) => receivedTabId = tabId);

        manager.onTabFocused('tab1', path: 'C:\\x');
        manager.onTabFocused('tab2');

        final ok = manager.markInactive('tab1');
        expect(ok, isTrue);
        expect(manager.stateOf('tab1'), TabActivityState.inactive);
        expect(manager.needsReload('tab1'), isTrue);
        expect(receivedTabId, 'tab1');
      },
    );

    test('10.15 markInactive refuses focused or unknown tabs', () {
      manager.onTabFocused('tab1');
      expect(manager.markInactive('tab1'), isFalse);
      expect(manager.markInactive('does-not-exist'), isFalse);
    });

    test('10.16 markInactive is idempotent for already-inactive tabs', () {
      manager.onTabFocused('tab1');
      manager.onTabFocused('tab2');
      fakeNow = fakeNow.add(const Duration(hours: 1, seconds: 1));
      manager.evaluateInactiveTabs();

      expect(manager.stateOf('tab1'), TabActivityState.inactive);
      expect(manager.markInactive('tab1'), isFalse);
    });

    test(
      '10.17 focusing a manually-inactive tab reactivates it and triggers reload',
      () {
        manager.onTabFocused('tab1', path: 'C:\\one');
        manager.onTabFocused('tab2', path: 'C:\\two');

        // Manual mark via right-click menu equivalent.
        expect(manager.markInactive('tab1'), isTrue);
        expect(manager.stateOf('tab1'), TabActivityState.inactive);
        expect(manager.needsReload('tab1'), isTrue);

        // User clicks the tab header — equivalent to SwitchToTab.
        manager.onTabFocused('tab1');

        expect(manager.stateOf('tab1'), TabActivityState.focused);
        expect(manager.focusedTabId, 'tab1');
        // Reload is consumed exactly once on refocus.
        expect(manager.consumeReloadFlag('tab1'), isTrue);
        expect(manager.consumeReloadFlag('tab1'), isFalse);
      },
    );

    test(
      '10.18 always-active pin excludes a tab from automatic inactive transition',
      () {
        manager.onTabFocused('tab1', path: 'C:\\pinned');
        manager.onTabFocused('tab2');

        // Pin tab1 while it sits in background.
        manager.setAlwaysActive('tab1', true);
        expect(manager.isAlwaysActive('tab1'), isTrue);

        // Age past the threshold — pinned tab must not transition.
        fakeNow = fakeNow.add(const Duration(hours: 5));
        final transitioned = manager.evaluateInactiveTabs();
        expect(transitioned, isEmpty);
        expect(manager.stateOf('tab1'), TabActivityState.backgroundActive);

        // Unpinning re-enables normal evaluation immediately.
        manager.setAlwaysActive('tab1', false);
        final after = manager.evaluateInactiveTabs();
        expect(after, ['tab1']);
        expect(manager.stateOf('tab1'), TabActivityState.inactive);
      },
    );

    test('10.19 always-active pin makes markInactive return false', () {
      manager.onTabFocused('tab1', path: 'C:\\pinned');
      manager.onTabFocused('tab2');

      manager.setAlwaysActive('tab1', true);
      expect(manager.markInactive('tab1'), isFalse);
      expect(manager.stateOf('tab1'), TabActivityState.backgroundActive);
    });

    test(
      '10.20 pinning an inactive tab promotes it back to background and notifies',
      () {
        manager.onTabFocused('tab1', path: 'C:\\one');
        manager.onTabFocused('tab2');

        // Force inactive.
        fakeNow = fakeNow.add(const Duration(hours: 1, seconds: 1));
        manager.evaluateInactiveTabs();
        expect(manager.stateOf('tab1'), TabActivityState.inactive);

        var listenerFires = 0;
        manager.addListener(() => listenerFires++);

        manager.setAlwaysActive('tab1', true);

        expect(manager.stateOf('tab1'), TabActivityState.backgroundActive);
        expect(manager.isAlwaysActive('tab1'), isTrue);
        expect(listenerFires, 1);
      },
    );

    test('10.21 toggling pin state fires listener exactly once per change', () {
      manager.onTabFocused('tab1');
      manager.onTabFocused('tab2');

      var fires = 0;
      manager.addListener(() => fires++);

      manager.setAlwaysActive('tab1', true);
      manager.setAlwaysActive('tab1', true); // no-op
      manager.setAlwaysActive('tab1', false);
      manager.setAlwaysActive('tab1', false); // no-op

      expect(fires, 2);
    });
  });
}
