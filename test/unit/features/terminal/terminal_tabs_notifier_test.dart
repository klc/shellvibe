import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm3/xterm.dart';

import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/hosts/presentation/notifiers/hosts_notifier.dart';
import 'package:shellvibe/features/settings/domain/models/app_settings_model.dart';
import 'package:shellvibe/features/settings/presentation/notifiers/settings_notifier.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_palette.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:shellvibe/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:shellvibe/features/vault/presentation/notifiers/vault_notifier.dart';
import 'package:shellvibe/core/network/local_pty_manager.dart';
import 'package:shellvibe/core/network/providers/network_providers.dart';
import 'package:shellvibe/core/utils/platform_capabilities.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

/// Everything the terminal currently holds, scrollback included. A disposed
/// terminal drops writes, so this is how a test tells a live pane from a dead
/// one without reaching into xterm internals.
String _bufferText(Terminal terminal) {
  final lines = terminal.buffer.lines;
  final text = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    text.write(lines[i].toString());
  }
  return text.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  group('TerminalTabsNotifier Unit Tests', () {
    test('Initial state has no active tabs', () {
      final state = container.read(terminalTabsProvider);
      expect(state.tabs, isEmpty);
      expect(state.activeTabId, isNull);
      expect(state.activeTab, isNull);
    });

    test(
      'does not start Device Link listener without paired records',
      () async {
        final notifier = container.read(terminalTabsProvider.notifier);

        await notifier.ensureDeviceLinkServerForPairedDevices();

        expect(notifier.deviceLinkVaultAvailable, isFalse);
        expect(notifier.isDeviceLinkServerRunning, isFalse);
      },
    );

    test('does not start Device Link listener on mobile', () async {
      debugPlatformCapabilitiesOverride = TargetPlatform.android;
      addTearDown(() => debugPlatformCapabilitiesOverride = null);
      final notifier = container.read(terminalTabsProvider.notifier);

      await notifier.ensureDeviceLinkServerForPairedDevices();

      expect(notifier.deviceLinkVaultAvailable, isFalse);
      expect(notifier.isDeviceLinkServerRunning, isFalse);
    });

    test(
      'does not start Device Link listener while the vault is locked',
      () async {
        final now = DateTime.now();
        await database.pairedDevicesDao.upsert(
          PairedDevicesCompanion.insert(
            id: 'locked-paired-phone',
            name: 'Locked phone',
            platform: 'ios',
            secretHash: 'not-used-while-locked',
            publicKey: 'ephemeral-public-key',
            pairedAt: now,
            lastSeenAt: now,
          ),
        );
        final lockedContainer = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            vaultProvider.overrideWith(() => _LockedVaultNotifier()),
          ],
        );
        addTearDown(lockedContainer.dispose);

        final notifier = lockedContainer.read(terminalTabsProvider.notifier);

        await notifier.ensureDeviceLinkServerForPairedDevices();

        expect(notifier.deviceLinkVaultAvailable, isFalse);
        expect(notifier.isDeviceLinkServerRunning, isFalse);
      },
    );

    test(
      'starts Device Link listener when the vault is unconfigured',
      () async {
        final now = DateTime.now();
        await database.pairedDevicesDao.upsert(
          PairedDevicesCompanion.insert(
            id: 'unconfigured-paired-phone',
            name: 'Unconfigured phone',
            platform: 'ios',
            secretHash: 'not-used-while-unconfigured',
            publicKey: 'ephemeral-public-key',
            pairedAt: now,
            lastSeenAt: now,
          ),
        );
        final unconfiguredContainer = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            vaultProvider.overrideWith(() => _UnconfiguredVaultNotifier()),
          ],
        );
        addTearDown(() async {
          await unconfiguredContainer
              .read(terminalTabsProvider.notifier)
              .stopDeviceLinkServer();
          unconfiguredContainer.dispose();
        });

        await unconfiguredContainer.read(vaultProvider.future);
        final notifier = unconfiguredContainer.read(
          terminalTabsProvider.notifier,
        );

        expect(notifier.deviceLinkVaultAvailable, isTrue);
      },
    );

    test(
      'does not start Device Link listener while the vault is loading',
      () async {
        final now = DateTime.now();
        await database.pairedDevicesDao.upsert(
          PairedDevicesCompanion.insert(
            id: 'loading-paired-phone',
            name: 'Loading phone',
            platform: 'ios',
            secretHash: 'not-used-while-loading',
            publicKey: 'ephemeral-public-key',
            pairedAt: now,
            lastSeenAt: now,
          ),
        );
        final loadingContainer = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            vaultProvider.overrideWith(() => _LoadingVaultNotifier()),
          ],
        );
        addTearDown(loadingContainer.dispose);

        final notifier = loadingContainer.read(terminalTabsProvider.notifier);

        await notifier.ensureDeviceLinkServerForPairedDevices();

        expect(notifier.isDeviceLinkServerRunning, isFalse);
      },
    );

    test(
      'does not start Device Link listener when the vault has no value',
      () async {
        final failedContainer = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            vaultProvider.overrideWith(() => _FailedVaultNotifier()),
          ],
        );
        addTearDown(failedContainer.dispose);

        final notifier = failedContainer.read(terminalTabsProvider.notifier);

        await notifier.ensureDeviceLinkServerForPairedDevices();

        expect(notifier.isDeviceLinkServerRunning, isFalse);
      },
    );

    test('openLocalTab adds a new tab and sets as active', () {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'Test Shell');

      final state = container.read(terminalTabsProvider);
      expect(state.tabs.length, equals(1));
      expect(state.activeTabId, isNotNull);
      expect(state.activeTab!.title, equals('Test Shell'));
    });

    test('setActiveTab switches active tab', () {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'Tab 1');
      final id1 = container.read(terminalTabsProvider).activeTabId!;

      notifier.openLocalTab(title: 'Tab 2');
      final id2 = container.read(terminalTabsProvider).activeTabId!;

      expect(id1, isNot(equals(id2)));
      expect(
        container.read(terminalTabsProvider).activeTab!.title,
        equals('Tab 2'),
      );

      notifier.setActiveTab(id1);
      expect(container.read(terminalTabsProvider).activeTabId, equals(id1));
      expect(
        container.read(terminalTabsProvider).activeTab!.title,
        equals('Tab 1'),
      );
    });

    test('closeTab disposes session and updates active tab', () async {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'Tab 1');
      final id1 = container.read(terminalTabsProvider).activeTabId!;

      notifier.openLocalTab(title: 'Tab 2');
      final id2 = container.read(terminalTabsProvider).activeTabId!;

      await notifier.closeTab(id2);

      final state = container.read(terminalTabsProvider);
      expect(state.tabs.length, equals(1));
      expect(state.activeTabId, equals(id1));
    });

    test(
      'closeTab releases Device Link ownership after its route is disposed',
      () async {
        final notifier = container.read(terminalTabsProvider.notifier);
        final session = TerminalTabSession(
          id: 'device-link-test',
          title: 'Device Link',
          sessionType: TerminalSessionType.local,
          isDeviceLink: true,
          terminal: Terminal(),
          isConnected: true,
        );
        Object? activeController = Object();
        var connectionClosed = false;
        var closeCalls = 0;
        var pairingRouteDisposed = false;

        notifier.registerDeviceLinkSession(
          session,
          onClose: () {
            // The scan/pair route can already be gone when the shared
            // terminal tab is closed. The callback must use its captured
            // notifier/controller rather than touching that route's ref.
            expect(pairingRouteDisposed, isTrue);
            closeCalls++;
            connectionClosed = true;
            activeController = null;
          },
        );

        pairingRouteDisposed = true;
        await notifier.closeTab(session.id);

        expect(connectionClosed, isTrue);
        expect(closeCalls, equals(1));
        expect(activeController, isNull);
        expect(container.read(terminalTabsProvider).tabs, isEmpty);
      },
    );

    test('togglePaneSelection toggles membership and isBroadcasting', () {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'A');
      final a = container.read(terminalTabsProvider).activeTabId!;
      notifier.openLocalTab(title: 'B');
      final b = container.read(terminalTabsProvider).activeTabId!;

      expect(container.read(terminalTabsProvider).isBroadcasting, isFalse);

      notifier.togglePaneSelection(a);
      notifier.togglePaneSelection(b);

      var state = container.read(terminalTabsProvider);
      expect(state.selectedPaneIds, {a, b});
      expect(state.isBroadcasting, isTrue);

      notifier.togglePaneSelection(a);

      state = container.read(terminalTabsProvider);
      expect(state.selectedPaneIds, {b});
      expect(state.isBroadcasting, isFalse);
    });

    test('tapPane modifier click selects and activates; plain click on an '
        'unselected pane clears the selection', () {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'A');
      final a = container.read(terminalTabsProvider).activeTabId!;
      notifier.openLocalTab(title: 'B');
      final b = container.read(terminalTabsProvider).activeTabId!;
      notifier.openLocalTab(title: 'C');
      final c = container.read(terminalTabsProvider).activeTabId!;

      notifier.tapPane(a, broadcastModifier: true);
      notifier.tapPane(b, broadcastModifier: true);

      var state = container.read(terminalTabsProvider);
      expect(state.selectedPaneIds, {a, b});
      expect(state.activeTabId, b); // last modifier click becomes origin

      // Plain click on an unselected pane exits broadcast and focuses it.
      notifier.tapPane(c, broadcastModifier: false);

      state = container.read(terminalTabsProvider);
      expect(state.selectedPaneIds, isEmpty);
      expect(state.activeTabId, c);
    });

    test('closeTab clears the closed pane from the selection', () async {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'A');
      final a = container.read(terminalTabsProvider).activeTabId!;
      notifier.openLocalTab(title: 'B');
      final b = container.read(terminalTabsProvider).activeTabId!;

      notifier.togglePaneSelection(a);
      notifier.togglePaneSelection(b);

      await notifier.closeTab(a);

      final state = container.read(terminalTabsProvider);
      expect(state.selectedPaneIds, {b});
      expect(state.isBroadcasting, isFalse); // only one pane left
    });

    test('sendTextToSelectedPanes is a no-op when nothing is selected', () {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'A');

      expect(() => notifier.sendTextToSelectedPanes('ls'), returnsNormally);
    });

    test('splitTab creates split pane session', () {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'Main Tab');
      final mainId = container.read(terminalTabsProvider).activeTabId!;

      notifier.splitTab(mainId);

      final state = container.read(terminalTabsProvider);
      expect(state.tabs.length, equals(2));
      final splitTab = state.tabs.last;
      expect(splitTab.splitParentId, equals(mainId));
      expect(splitTab.sessionType, equals(TerminalSessionType.local));
    });

    test(
      'closeOther/Left/Right close whole tabs around the one kept',
      () async {
        final notifier = container.read(terminalTabsProvider.notifier);
        final ids = <String>[];
        for (final title in ['A', 'B', 'C', 'D']) {
          notifier.openLocalTab(title: title);
          ids.add(container.read(terminalTabsProvider).activeTabId!);
        }
        // B carries a split, which has to go with it.
        notifier.splitTab(ids[1], direction: Axis.horizontal);

        List<String> titles() => [
          for (final tab in container.read(terminalTabsProvider).tabs)
            if (tab.splitParentId == null) tab.title,
        ];

        await notifier.closeTabsToLeft(ids[2]);
        expect(titles(), ['C', 'D']);
        expect(container.read(terminalTabsProvider).tabs, hasLength(2));

        await notifier.closeTabsToRight(ids[2]);
        expect(titles(), ['C']);

        // Nothing on either side: a no-op, not an error.
        await notifier.closeOtherTabs(ids[2]);
        await notifier.closeTabsToLeft(ids[2]);
        expect(titles(), ['C']);
      },
    );

    test('closeOtherTabs keeps the clicked tab and focuses it', () async {
      final notifier = container.read(terminalTabsProvider.notifier);
      final ids = <String>[];
      for (final title in ['A', 'B', 'C']) {
        notifier.openLocalTab(title: title);
        ids.add(container.read(terminalTabsProvider).activeTabId!);
      }
      // C is focused; B is the one right-clicked.
      await notifier.closeOtherTabs(ids[1]);

      final state = container.read(terminalTabsProvider);
      expect([for (final tab in state.tabs) tab.title], ['B']);
      expect(state.activeTabId, ids[1]);
    });

    test('moveTab reorders root tabs and leaves every split pane alone', () {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'A');
      final a = container.read(terminalTabsProvider).activeTabId!;
      notifier.splitTab(a, direction: Axis.horizontal);
      final aPane = container.read(terminalTabsProvider).tabs.last.id;
      notifier.openLocalTab(title: 'B');
      final b = container.read(terminalTabsProvider).activeTabId!;
      notifier.openLocalTab(title: 'C');
      final c = container.read(terminalTabsProvider).activeTabId!;

      List<String> roots() => [
        for (final tab in container.read(terminalTabsProvider).tabs)
          if (tab.splitParentId == null) tab.id,
      ];

      notifier.moveTab(c, 0);
      expect(roots(), [c, a, b]);

      notifier.moveTab(c, 2);
      expect(roots(), [a, b, c]);

      // An index past the end lands on the last slot rather than throwing.
      notifier.moveTab(a, 99);
      expect(roots(), [b, c, a]);

      final state = container.read(terminalTabsProvider);
      final pane = state.tabs.firstWhere((t) => t.id == aPane);
      expect(pane.splitParentId, a);
      expect(pane.splitDirection, Axis.horizontal);
      // Moving a tab is not selecting it.
      expect(state.activeTabId, c);
    });

    test('moveTab ignores split panes and unknown ids', () {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'A');
      final a = container.read(terminalTabsProvider).activeTabId!;
      notifier.splitTab(a, direction: Axis.horizontal);
      final aPane = container.read(terminalTabsProvider).tabs.last.id;
      notifier.openLocalTab(title: 'B');

      final before = [...container.read(terminalTabsProvider).tabs];
      notifier.moveTab(aPane, 1);
      notifier.moveTab('missing', 0);
      expect(container.read(terminalTabsProvider).tabs, before);
    });

    test('swapPanes exchanges two panes without moving the layout', () {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'Main Tab');
      final root = container.read(terminalTabsProvider).activeTabId!;
      notifier.splitTab(root, direction: Axis.horizontal);
      final second = container.read(terminalTabsProvider).tabs.last.id;
      notifier.setSplitRatio(second, 0.3);
      notifier.splitTab(second, direction: Axis.vertical);
      final third = container.read(terminalTabsProvider).tabs.last.id;
      notifier.setSplitRatio(third, 0.7);

      notifier.swapPanes(second, third);

      final state = container.read(terminalTabsProvider);
      final movedDown = state.tabs.firstWhere((t) => t.id == second);
      final movedUp = state.tabs.firstWhere((t) => t.id == third);
      // The slots keep their shape: the middle one is still a horizontal split
      // at 0.3 of the root, the inner one still a vertical split at 0.7 of the
      // middle. Only which pane sits in each has changed.
      expect(movedUp.splitParentId, equals(root));
      expect(movedUp.splitDirection, equals(Axis.horizontal));
      expect(movedUp.splitRatio, equals(0.3));
      expect(movedDown.splitParentId, equals(third));
      expect(movedDown.splitDirection, equals(Axis.vertical));
      expect(movedDown.splitRatio, equals(0.7));
      // Both sessions stay live: a swap moves positions, never terminals.
      movedUp.terminal.write('alive');
      expect(_bufferText(movedUp.terminal), contains('alive'));
    });

    test('swapPanes keeps the tree walkable when a root pane moves', () {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'Main Tab');
      final root = container.read(terminalTabsProvider).activeTabId!;
      notifier.splitTab(root, direction: Axis.horizontal);
      final middle = container.read(terminalTabsProvider).tabs.last.id;
      notifier.splitTab(middle, direction: Axis.vertical);
      final leaf = container.read(terminalTabsProvider).tabs.last.id;

      // Root and grandchild: the pair that a naive parent-link swap turns into
      // a cycle, which the layout fold would then walk forever.
      notifier.swapPanes(root, leaf);

      final state = container.read(terminalTabsProvider);
      final roots = state.tabs.where((t) => t.splitParentId == null).toList();
      expect(roots.length, equals(1));
      expect(roots.single.id, equals(leaf));
      for (final tab in state.tabs) {
        var current = tab;
        var hops = 0;
        while (current.splitParentId != null) {
          hops++;
          expect(hops, lessThanOrEqualTo(state.tabs.length));
          current = state.tabs.firstWhere((t) => t.id == current.splitParentId);
        }
      }
      // The chain still has one pane per level, in the same shape as before.
      final middlePane = state.tabs.firstWhere((t) => t.id == middle);
      final rootPane = state.tabs.firstWhere((t) => t.id == root);
      expect(middlePane.splitParentId, equals(leaf));
      expect(rootPane.splitParentId, equals(middle));
    });

    test('swapPanes refuses panes of different tabs and unknown ids', () {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'One');
      final firstRoot = container.read(terminalTabsProvider).activeTabId!;
      notifier.openLocalTab(title: 'Two');
      final secondRoot = container.read(terminalTabsProvider).activeTabId!;
      notifier.splitTab(secondRoot, direction: Axis.horizontal);
      final secondPane = container.read(terminalTabsProvider).tabs.last.id;

      notifier.swapPanes(firstRoot, secondPane);
      notifier.swapPanes(firstRoot, 'does-not-exist');
      notifier.swapPanes(firstRoot, firstRoot);

      final state = container.read(terminalTabsProvider);
      expect(
        state.tabs.firstWhere((t) => t.id == firstRoot).splitParentId,
        isNull,
      );
      expect(
        state.tabs.firstWhere((t) => t.id == secondPane).splitParentId,
        equals(secondRoot),
      );
    });

    test('movePaneTo docks a pane against the trailing edge of another', () {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'A');
      final root = container.read(terminalTabsProvider).activeTabId!;
      notifier.splitTab(root, direction: Axis.horizontal);
      final second = container.read(terminalTabsProvider).tabs.last.id;
      notifier.splitTab(second, direction: Axis.horizontal);
      final third = container.read(terminalTabsProvider).tabs.last.id;

      notifier.movePaneTo(third, root, PaneDockEdge.bottom);

      final state = container.read(terminalTabsProvider);
      final moved = state.tabs.firstWhere((t) => t.id == third);
      expect(moved.splitParentId, equals(root));
      expect(moved.splitDirection, equals(Axis.vertical));
      expect(moved.splitRatio, equals(0.5));
      // Innermost child of its new parent, so it splits the root pane's own
      // rectangle rather than the root plus the pane already split off it.
      final rootChildren = state.tabs
          .where((t) => t.splitParentId == root)
          .map((t) => t.id)
          .toList();
      expect(rootChildren, equals([second, third]));
      expect(
        state.tabs.firstWhere((t) => t.id == second).splitDirection,
        equals(Axis.horizontal),
      );
    });

    test('movePaneTo docking to a leading edge puts the pane in front', () {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'A');
      final root = container.read(terminalTabsProvider).activeTabId!;
      notifier.splitTab(root, direction: Axis.horizontal);
      final second = container.read(terminalTabsProvider).tabs.last.id;
      notifier.splitTab(second, direction: Axis.horizontal);
      final third = container.read(terminalTabsProvider).tabs.last.id;

      notifier.movePaneTo(third, root, PaneDockEdge.left);

      // A leading dock is the trailing one with the two panes exchanged: the
      // arriving pane takes the target's slot and the target hangs off it.
      final state = container.read(terminalTabsProvider);
      final arrived = state.tabs.firstWhere((t) => t.id == third);
      final displaced = state.tabs.firstWhere((t) => t.id == root);
      expect(arrived.splitParentId, isNull);
      expect(displaced.splitParentId, equals(third));
      expect(displaced.splitDirection, equals(Axis.horizontal));
      // The pane that was already split off the root stays outside both, so
      // the dock cut the root's rectangle and nothing else.
      final outer = state.tabs.firstWhere((t) => t.id == second);
      expect(outer.splitParentId, equals(third));
      final arrivedChildren = state.tabs
          .where((t) => t.splitParentId == third)
          .map((t) => t.id)
          .toList();
      expect(arrivedChildren, equals([second, root]));
    });

    test('movePaneTo leaves the children of the moved pane behind', () {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'A');
      final root = container.read(terminalTabsProvider).activeTabId!;
      notifier.splitTab(root, direction: Axis.horizontal);
      final middle = container.read(terminalTabsProvider).tabs.last.id;
      notifier.splitTab(middle, direction: Axis.vertical);
      final leaf = container.read(terminalTabsProvider).tabs.last.id;

      notifier.movePaneTo(middle, leaf, PaneDockEdge.right);

      // The child is promoted into the slot the moved pane vacated, exactly as
      // closePane promotes it, and the moved pane arrives as a leaf.
      final state = container.read(terminalTabsProvider);
      final promoted = state.tabs.firstWhere((t) => t.id == leaf);
      final moved = state.tabs.firstWhere((t) => t.id == middle);
      expect(promoted.splitParentId, equals(root));
      expect(promoted.splitDirection, equals(Axis.horizontal));
      expect(moved.splitParentId, equals(leaf));
      expect(moved.splitDirection, equals(Axis.horizontal));
      expect(state.tabs.where((t) => t.splitParentId == middle), isEmpty);
      moved.terminal.write('alive');
      expect(_bufferText(moved.terminal), contains('alive'));
    });

    test('movePaneTo refuses panes of different tabs and unknown ids', () {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'One');
      final firstRoot = container.read(terminalTabsProvider).activeTabId!;
      notifier.openLocalTab(title: 'Two');
      final secondRoot = container.read(terminalTabsProvider).activeTabId!;
      notifier.splitTab(secondRoot, direction: Axis.horizontal);
      final secondPane = container.read(terminalTabsProvider).tabs.last.id;

      notifier.movePaneTo(firstRoot, secondPane, PaneDockEdge.left);
      notifier.movePaneTo(firstRoot, 'does-not-exist', PaneDockEdge.top);
      notifier.movePaneTo(firstRoot, firstRoot, PaneDockEdge.right);

      final state = container.read(terminalTabsProvider);
      expect(
        state.tabs.firstWhere((t) => t.id == firstRoot).splitParentId,
        isNull,
      );
      expect(
        state.tabs.firstWhere((t) => t.id == secondPane).splitParentId,
        equals(secondRoot),
      );
    });

    test('closePane promotes the children of a closed root pane', () async {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'Main Tab');
      final root = container.read(terminalTabsProvider).activeTabId!;
      notifier.splitTab(root, direction: Axis.horizontal);
      final first = container.read(terminalTabsProvider).tabs.last.id;
      notifier.splitTab(root, direction: Axis.vertical);
      final second = container.read(terminalTabsProvider).tabs.last.id;

      await notifier.closePane(root);

      final state = container.read(terminalTabsProvider);
      expect(state.tabs.map((t) => t.id), unorderedEquals([first, second]));
      // The last child takes the closed pane's slot — here that means becoming
      // the tab root — and the earlier one hangs off it.
      final heir = state.tabs.firstWhere((t) => t.id == second);
      final promoted = state.tabs.firstWhere((t) => t.id == first);
      expect(heir.splitParentId, isNull);
      expect(heir.splitDirection, isNull);
      expect(promoted.splitParentId, equals(second));
      expect(promoted.splitDirection, equals(Axis.horizontal));
      expect(state.activeTabId, equals(second));
      // The tab is still open, so the heir's session must be untouched: a
      // disposed terminal drops writes on the floor.
      heir.terminal.write('alive');
      expect(_bufferText(heir.terminal), contains('alive'));
    });

    test('closePane reparents the children of a closed middle pane', () async {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'Main Tab');
      final root = container.read(terminalTabsProvider).activeTabId!;
      notifier.splitTab(root, direction: Axis.horizontal);
      final middle = container.read(terminalTabsProvider).tabs.last.id;
      notifier.splitTab(middle, direction: Axis.vertical);
      final leaf = container.read(terminalTabsProvider).tabs.last.id;

      await notifier.closePane(middle);

      final state = container.read(terminalTabsProvider);
      expect(state.tabs.map((t) => t.id), unorderedEquals([root, leaf]));
      final heir = state.tabs.firstWhere((t) => t.id == leaf);
      // The heir inherits the closed pane's place in the tree, not its own.
      expect(heir.splitParentId, equals(root));
      expect(heir.splitDirection, equals(Axis.horizontal));
      heir.terminal.write('alive');
      expect(_bufferText(heir.terminal), contains('alive'));
    });

    test('closePane on a leaf pane leaves the rest of the tab alone', () async {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'Main Tab');
      final root = container.read(terminalTabsProvider).activeTabId!;
      notifier.splitTab(root, direction: Axis.horizontal);
      final leaf = container.read(terminalTabsProvider).tabs.last.id;

      await notifier.closePane(leaf);

      final state = container.read(terminalTabsProvider);
      expect(state.tabs.map((t) => t.id), equals([root]));
      expect(state.activeTabId, equals(root));
    });

    test('closing a pane keeps focus in its own tab', () async {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'Tab 1');
      final rootA = container.read(terminalTabsProvider).activeTabId!;
      notifier.openLocalTab(title: 'Tab 2');
      final rootB = container.read(terminalTabsProvider).activeTabId!;
      // Split panes are appended after every root tab, so tab 1's second pane
      // sits past tab 2 in the flat list.
      notifier.splitTab(rootA, direction: Axis.vertical);
      final paneA2 = container.read(terminalTabsProvider).activeTabId!;
      notifier.splitTab(rootB, direction: Axis.vertical);

      notifier.setActiveTab(paneA2);
      await notifier.closePane(paneA2);

      final state = container.read(terminalTabsProvider);
      expect(state.activeTabId, equals(rootA));
    });

    test(
      'closing a whole tab focuses a neighbouring tab, not a pane',
      () async {
        final notifier = container.read(terminalTabsProvider.notifier);

        notifier.openLocalTab(title: 'Tab 1');
        final rootA = container.read(terminalTabsProvider).activeTabId!;
        notifier.splitTab(rootA, direction: Axis.vertical);
        notifier.openLocalTab(title: 'Tab 2');
        final rootB = container.read(terminalTabsProvider).activeTabId!;

        await notifier.closeTab(rootB);

        final state = container.read(terminalTabsProvider);
        expect(state.activeTabId, equals(rootA));
      },
    );

    test('closeTab still tears down the whole split tree', () async {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'Main Tab');
      final root = container.read(terminalTabsProvider).activeTabId!;
      notifier.splitTab(root, direction: Axis.horizontal);
      final child = container.read(terminalTabsProvider).tabs.last.id;
      notifier.splitTab(child, direction: Axis.vertical);

      await notifier.closeTab(root);

      expect(container.read(terminalTabsProvider).tabs, isEmpty);
    });

    test(
      'splitTab on an SSH host tab creates an SSH split inheriting host and identity',
      () async {
        final notifier = container.read(terminalTabsProvider.notifier);
        final host = HostModel(
          id: 'host-split',
          workspaceId: 'ws-1',
          label: 'Split Host',
          hostname: '127.0.0.1',
          port: 1,
          createdAt: DateTime.now(),
        );

        final openFuture = notifier.openTabForHost(host);
        final mainId = container.read(terminalTabsProvider).activeTabId!;

        final splitFuture = notifier.splitTab(mainId);
        final state = container.read(terminalTabsProvider);
        final splitTab = state.tabs.last;

        // The split mirrors the parent: an SSH session to the same host.
        expect(splitTab.splitParentId, equals(mainId));
        expect(splitTab.sessionType, equals(TerminalSessionType.ssh));
        expect(splitTab.host?.id, equals(host.id));
        expect(splitTab.isConnecting, isTrue);

        // Await both connection attempts so no in-flight SSH work leaks into
        // teardown (the connection to port 1 fails and is caught internally).
        await Future.wait([openFuture, splitFuture ?? Future<void>.value()]);
      },
    );

    test(
      'splitTab with an explicit host opens that host instead of inheriting the parent',
      () async {
        final notifier = container.read(terminalTabsProvider.notifier);
        final parentHost = HostModel(
          id: 'host-parent',
          workspaceId: 'ws-1',
          label: 'Parent Host',
          hostname: '127.0.0.1',
          port: 1,
          createdAt: DateTime.now(),
        );
        final otherHost = HostModel(
          id: 'host-other',
          workspaceId: 'ws-1',
          label: 'Other Host',
          hostname: '127.0.0.1',
          port: 1,
          createdAt: DateTime.now(),
        );

        final openFuture = notifier.openTabForHost(parentHost);
        final mainId = container.read(terminalTabsProvider).activeTabId!;

        final splitFuture = notifier.splitTab(mainId, host: otherHost);
        final state = container.read(terminalTabsProvider);
        final splitTab = state.tabs.last;

        // Same split tree, different connection.
        expect(splitTab.splitParentId, equals(mainId));
        expect(splitTab.sessionType, equals(TerminalSessionType.ssh));
        expect(splitTab.host?.id, equals(otherHost.id));
        expect(splitTab.title, equals(otherHost.label));
        expect(splitTab.isConnecting, isTrue);

        await Future.wait([openFuture, splitFuture ?? Future<void>.value()]);
      },
    );

    test('splitTab with an explicit host works from a local pane', () async {
      final notifier = container.read(terminalTabsProvider.notifier);
      final host = HostModel(
        id: 'host-from-local',
        workspaceId: 'ws-1',
        label: 'Remote Host',
        hostname: '127.0.0.1',
        port: 1,
        createdAt: DateTime.now(),
      );

      notifier.openLocalTab(title: 'Main Tab');
      final mainId = container.read(terminalTabsProvider).activeTabId!;

      final splitFuture = notifier.splitTab(mainId, host: host);
      final splitTab = container.read(terminalTabsProvider).tabs.last;

      expect(splitTab.sessionType, equals(TerminalSessionType.ssh));
      expect(splitTab.host?.id, equals(host.id));

      await (splitFuture ?? Future<void>.value());
    });

    test(
      'openTabForHost assigns dedicated SSHSessionManager instance per tab',
      () async {
        final notifier = container.read(terminalTabsProvider.notifier);
        final host = HostModel(
          id: 'host-1',
          workspaceId: 'ws-1',
          label: 'Test Host',
          hostname: '127.0.0.1',
          port: 1,
          createdAt: DateTime.now(),
        );

        final future1 = notifier.openTabForHost(host);
        final tab1 = container.read(terminalTabsProvider).tabs.last;

        final future2 = notifier.openTabForHost(host);
        final tab2 = container.read(terminalTabsProvider).tabs.last;

        expect(tab1.id, isNot(equals(tab2.id)));
        expect(tab1.sshSessionManager, isNotNull);
        expect(tab2.sshSessionManager, isNotNull);
        expect(
          identical(tab1.sshSessionManager, tab2.sshSessionManager),
          isFalse,
        );

        final manager1 = tab1.sshSessionManager;

        await notifier.closeTab(tab1.id);
        final remainingTab = container
            .read(terminalTabsProvider)
            .tabs
            .firstWhere((t) => t.id == tab2.id);

        expect(remainingTab.id, equals(tab2.id));
        expect(remainingTab.sshSessionManager, isNotNull);
        expect(identical(remainingTab.sshSessionManager, manager1), isFalse);

        // Await futures to prevent unhandled background errors in test tearDown
        await Future.wait([future1, future2]);
      },
    );

    test(
      'openTabForHost parses user@hostname and resolves effective username correctly',
      () async {
        final notifier = container.read(terminalTabsProvider.notifier);

        final hostWithUserInName = HostModel(
          id: 'host-user',
          workspaceId: 'ws-1',
          label: 'Parsed Host',
          hostname: 'admin@192.168.1.100',
          port: 1,
          createdAt: DateTime.now(),
        );

        final future = notifier.openTabForHost(hostWithUserInName);
        final tab = container.read(terminalTabsProvider).tabs.last;
        expect(tab.host?.hostname, equals('admin@192.168.1.100'));

        await future;
      },
    );

    test('reconnectTab re-attempts connection on a failed SSH tab', () async {
      final notifier = container.read(terminalTabsProvider.notifier);
      final host = HostModel(
        id: 'host-reconnect',
        workspaceId: 'ws-1',
        label: 'Reconnect Host',
        hostname: '127.0.0.1',
        port: 1,
        createdAt: DateTime.now(),
      );

      await notifier.openTabForHost(host);
      final preTab = container.read(terminalTabsProvider).tabs.last;
      expect(preTab.isConnected, isFalse);
      expect(preTab.errorMessage, isNotNull);
      final oldManager = preTab.sshSessionManager;

      // The reconnect flips the tab to connecting and clears the error
      // synchronously, before the new handshake is in flight.
      final reconnectFuture = notifier.reconnectTab(preTab.id);
      final midTab = container.read(terminalTabsProvider).tabs.last;
      expect(midTab.isConnecting, isTrue);
      expect(midTab.errorMessage, isNull);
      expect(midTab.isConnected, isFalse);

      await reconnectFuture;

      // The attempt failed (port 1 is unreachable) but the tab survived with
      // a fresh session manager; closing the tab is no longer required to
      // retry.
      final afterTab = container.read(terminalTabsProvider).tabs.last;
      expect(container.read(terminalTabsProvider).tabs.length, equals(1));
      expect(afterTab.id, equals(preTab.id));
      expect(afterTab.isConnecting, isFalse);
      expect(afterTab.isConnected, isFalse);
      expect(afterTab.errorMessage, isNotNull);
      expect(afterTab.sshSessionManager, isNotNull);
      expect(identical(afterTab.sshSessionManager, oldManager), isFalse);
    });

    test('reconnectTab clears modes the dead session left latched', () async {
      final notifier = container.read(terminalTabsProvider.notifier);
      final host = HostModel(
        id: 'host-modes',
        workspaceId: 'ws-1',
        label: 'Modes Host',
        hostname: '127.0.0.1',
        port: 1,
        createdAt: DateTime.now(),
      );

      await notifier.openTabForHost(host);
      final tab = container.read(terminalTabsProvider).tabs.last;

      // What htop turns on: alternate screen, drag-reporting mouse in SGR
      // encoding, bracketed paste, application cursor keys. A link that drops
      // mid-session means none of it is ever turned back off.
      tab.terminal.write(
        '\x1b[?1049h\x1b[?1002h\x1b[?1006h\x1b[?2004h\x1b[?1h',
      );
      expect(tab.terminal.isUsingAltBuffer, isTrue);
      expect(tab.terminal.mouseMode, isNot(MouseMode.none));
      expect(tab.terminal.bracketedPasteMode, isTrue);

      await notifier.reconnectTab(tab.id);

      // Otherwise the reconnected shell is handed `\x1b[<65;62;41M` on every
      // scroll and echoes it across the prompt.
      final afterTab = container.read(terminalTabsProvider).tabs.last;
      expect(afterTab.terminal.isUsingAltBuffer, isFalse);
      expect(afterTab.terminal.mouseMode, MouseMode.none);
      expect(afterTab.terminal.mouseReportMode, MouseReportMode.normal);
      expect(afterTab.terminal.bracketedPasteMode, isFalse);
      expect(afterTab.terminal.cursorKeysMode, isFalse);
    });

    test(
      'reconnectTab is a no-op for non-SSH tabs and connecting tabs',
      () async {
        final notifier = container.read(terminalTabsProvider.notifier);

        notifier.openLocalTab(title: 'Local');
        final localId = container.read(terminalTabsProvider).activeTabId!;
        final localTabBefore = container.read(terminalTabsProvider).tabs.last;

        await notifier.reconnectTab(localId);
        final localTabAfter = container.read(terminalTabsProvider).tabs.last;
        expect(identical(localTabBefore, localTabAfter), isTrue);

        final host = HostModel(
          id: 'host-connecting',
          workspaceId: 'ws-1',
          label: 'Connecting Host',
          hostname: '127.0.0.1',
          port: 1,
          createdAt: DateTime.now(),
        );
        final openFuture = notifier.openTabForHost(host);
        final connectingTab = container.read(terminalTabsProvider).tabs.last;
        expect(connectingTab.isConnecting, isTrue);

        // Guarded: no restart while a connect is already in flight.
        final reconnectFuture = notifier.reconnectTab(connectingTab.id);
        expect(
          container.read(terminalTabsProvider).tabs.last.isConnecting,
          isTrue,
        );

        await Future.wait([openFuture, reconnectFuture]);

        // Only a single connection attempt ran; the tab failed once.
        final finalTab = container.read(terminalTabsProvider).tabs.last;
        expect(finalTab.isConnecting, isFalse);
        expect(finalTab.errorMessage, isNotNull);
      },
    );

    test(
      'reconnectTab picks up a host edited after the tab was opened',
      () async {
        // Needs a real store: the refresh reads the host back out of it.
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final dbContainer = ProviderContainer(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
        );
        addTearDown(dbContainer.dispose);

        final notifier = dbContainer.read(terminalTabsProvider.notifier);
        final repository = dbContainer.read(hostsRepositoryProvider);

        final saved = await repository.saveHost(
          workspaceId: 'ws-1',
          label: 'Editable Host',
          hostname: '127.0.0.1',
          port: 1,
        );
        await notifier.openTabForHost(saved);
        final tab = dbContainer.read(terminalTabsProvider).tabs.last;
        expect(tab.host!.protocol, equals('ssh'));

        // The user switches the host to Mosh while the tab is open. The tab
        // still holds the copy it was opened with.
        await repository.saveHost(
          id: saved.id,
          workspaceId: saved.workspaceId,
          label: saved.label,
          hostname: saved.hostname,
          port: saved.port,
          protocol: 'mosh',
        );
        expect(tab.host!.protocol, equals('ssh'));

        await notifier.reconnectTab(tab.id);

        // The connect still fails (port 1 is unreachable), but it was attempted
        // with the current settings rather than the snapshot.
        final after = dbContainer.read(terminalTabsProvider).tabs.last;
        expect(after.host!.protocol, equals('mosh'));
      },
    );

    test('reconnectTab still works when the host row is gone', () async {
      // The tab's own copy is a valid target on its own, so a deleted host
      // must not turn reconnect into a dead end.
      final notifier = container.read(terminalTabsProvider.notifier);
      final host = HostModel(
        id: 'host-never-saved',
        workspaceId: 'ws-1',
        label: 'Unsaved Host',
        hostname: '127.0.0.1',
        port: 1,
        createdAt: DateTime.now(),
      );

      await notifier.openTabForHost(host);
      final tab = container.read(terminalTabsProvider).tabs.last;

      await notifier.reconnectTab(tab.id);

      final after = container.read(terminalTabsProvider).tabs.last;
      expect(after.host!.id, equals('host-never-saved'));
      expect(after.isConnecting, isFalse);
      expect(after.sshSessionManager, isNotNull);
    });

    test('rehomeMoshSessions is a no-op when no tab is running Mosh', () {
      final notifier = container.read(terminalTabsProvider.notifier);
      notifier.openLocalTab(title: 'Local');

      // Roaming reaches for the network stack, which does not exist here.
      // Nothing may be touched until a Mosh session actually opens.
      expect(notifier.rehomeMoshSessions, returnsNormally);
    });

    test(
      'a mosh host whose bootstrap cannot run still ends up on SSH',
      () async {
        final notifier = container.read(terminalTabsProvider.notifier);
        final host = HostModel(
          id: 'host-mosh',
          workspaceId: 'ws-1',
          label: 'Mosh Host',
          hostname: '127.0.0.1',
          port: 1,
          protocol: 'mosh',
          createdAt: DateTime.now(),
        );

        // Port 1 refuses the SSH connect, so this only proves the mosh branch
        // does not change how a failed connect is reported. The Mosh path itself
        // needs a real server and is covered by tool/mosh/smoke.dart.
        await notifier.openTabForHost(host);

        final tab = container.read(terminalTabsProvider).tabs.last;
        expect(tab.isConnected, isFalse);
        expect(tab.errorMessage, isNotNull);
        expect(tab.moshSessionManager, isNull);
        expect(tab.isMosh, isFalse);
      },
    );
  });

  group('MCP tabs', () {
    test('an agent session opens a badged, read-only tab', () {
      final notifier = container.read(terminalTabsProvider.notifier);

      final tabId = notifier.openMcpTab(
        mcpSessionId: 'mcp-1',
        title: 'prod-web-01',
        onClose: () {},
      );

      final tab = notifier.tabById(tabId)!;
      expect(tab.isMcp, isTrue);
      expect(tab.mcpSessionId, 'mcp-1');
      expect(tab.title, 'prod-web-01');
      // Opening it must not steal the user out of whatever tab they are in.
      expect(container.read(terminalTabsProvider).activeTabId, isNot(tabId));
    });

    test('closing the tab ends the agent session', () async {
      final notifier = container.read(terminalTabsProvider.notifier);
      var sessionClosed = false;

      final tabId = notifier.openMcpTab(
        mcpSessionId: 'mcp-1',
        title: 'prod-web-01',
        onClose: () => sessionClosed = true,
      );
      await notifier.closeTab(tabId);

      expect(sessionClosed, isTrue);
      expect(notifier.tabById(tabId), isNull);
    });

    test('a session that ends on its own closes its tab without calling back '
        'into the pool', () async {
      final notifier = container.read(terminalTabsProvider.notifier);
      var sessionClosed = false;

      final tabId = notifier.openMcpTab(
        mcpSessionId: 'mcp-1',
        title: 'prod-web-01',
        onClose: () => sessionClosed = true,
      );
      await notifier.closeMcpTab(tabId);

      expect(notifier.tabById(tabId), isNull);
      // The pool is already tearing the session down; calling back would
      // close it a second time and, through the mirror, re-enter this.
      expect(sessionClosed, isFalse);
    });

    test('an AI tab cannot join a broadcast selection', () {
      final notifier = container.read(terminalTabsProvider.notifier);
      final tabId = notifier.openMcpTab(
        mcpSessionId: 'mcp-1',
        title: 'prod-web-01',
        onClose: () {},
      );

      notifier.togglePaneSelection(tabId);

      // Broadcast types the same keystrokes into every selected pane, and
      // this pane takes no typing at all.
      expect(container.read(terminalTabsProvider).selectedPaneIds, isEmpty);
    });
  });

  group('Local shell environment', () {
    Future<List<Map<String, String>?>> spawnedEnvironments(
      TerminalPalette palette, {
      bool split = false,
    }) async {
      final manager = _RecordingPtyManager();
      final scoped = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          localPtyManagerProvider.overrideWithValue(manager),
          settingsProvider.overrideWith(
            () => _FixedSettingsNotifier(
              AppSettingsModel(terminalPalette: palette),
            ),
          ),
        ],
      );
      addTearDown(scoped.dispose);
      // The app keeps settings watched from launch; hold them loaded the same
      // way before the shell is opened.
      scoped.listen(settingsProvider, (_, _) {});
      await scoped.read(settingsProvider.future);

      final notifier = scoped.read(terminalTabsProvider.notifier);
      notifier.openLocalTab();
      await pumpEventQueue();
      if (split) {
        await notifier.splitTab(scoped.read(terminalTabsProvider).activeTabId!);
      }
      return manager.environments;
    }

    test('a light palette starts the shell with TERM_THEME=light', () async {
      final envs = await spawnedEnvironments(TerminalPalette.catppuccinLatte);
      expect(envs.single, containsPair('TERM_THEME', 'light'));
    });

    test('a dark palette starts the shell with TERM_THEME=dark', () async {
      final envs = await spawnedEnvironments(TerminalPalette.oled);
      expect(envs.single, containsPair('TERM_THEME', 'dark'));
    });

    test('a local split pane gets TERM_THEME too', () async {
      final envs = await spawnedEnvironments(
        TerminalPalette.catppuccinLatte,
        split: true,
      );
      expect(envs, hasLength(2));
      expect(envs.last, containsPair('TERM_THEME', 'light'));
    });
  });
}

class _LockedVaultNotifier extends VaultNotifier {
  @override
  Future<VaultState> build() async {
    return const VaultState(status: VaultStatus.locked);
  }
}

class _UnconfiguredVaultNotifier extends VaultNotifier {
  @override
  Future<VaultState> build() async {
    return const VaultState(status: VaultStatus.unconfigured);
  }
}

class _LoadingVaultNotifier extends VaultNotifier {
  @override
  Future<VaultState> build() => Completer<VaultState>().future;
}

class _FailedVaultNotifier extends VaultNotifier {
  @override
  Future<VaultState> build() async {
    throw StateError('vault state unavailable');
  }
}

class _FixedSettingsNotifier extends SettingsNotifier {
  _FixedSettingsNotifier(this._settings);

  final AppSettingsModel _settings;

  @override
  Future<AppSettingsModel> build() async => _settings;
}

/// Records the environment each shell was asked to start with, and starts
/// none.
class _RecordingPtyManager extends LocalPtyManager {
  final environments = <Map<String, String>?>[];

  @override
  Future<TerminalLocalPtyBridge?> startAndBridge(
    Terminal terminal, {
    String? executable,
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
    int rows = 24,
    int columns = 80,
    void Function(Uint8List bytes)? outputTap,
  }) async {
    environments.add(environment);
    return null;
  }
}
