import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/window/desktop_tray_menu.dart';
import 'package:tray_manager/tray_manager.dart';

void main() {
  /// Labels of a submenu's items, separators left out.
  List<String> submenu(Menu menu, String titlePrefix) {
    final parent = menu.items!.firstWhere(
      (item) => item.label?.startsWith(titlePrefix) ?? false,
    );
    return [
      for (final item in parent.submenu!.items!)
        if (item.type != 'separator') item.label!,
    ];
  }

  /// Key of the item with [label] anywhere in [menu].
  String? keyOf(Menu menu, String label) {
    for (final item in menu.items!) {
      if (item.label == label) return item.key;
      final inner = item.submenu;
      if (inner != null) {
        final found = keyOf(inner, label);
        if (found != null) return found;
      }
    }
    return null;
  }

  List<String?> topLevel(Menu menu) => [
    for (final item in menu.items!)
      item.type == 'separator' ? '---' : item.label,
  ];

  group('buildTrayMenu', () {
    test('an empty tray still offers every section, in order', () {
      final menu = buildTrayMenu(const TrayMenuData());

      expect(topLevel(menu), [
        'Show ShellVibe',
        '---',
        'Sessions (0)',
        'Tunnels',
        '---',
        'Favorites',
        'Templates',
        '---',
        'Quit ShellVibe',
      ]);
      expect(submenu(menu, 'Sessions'), ['No open sessions']);
      expect(submenu(menu, 'Tunnels'), ['No tunnels']);
      expect(submenu(menu, 'Favorites'), ['No favorites']);
      expect(submenu(menu, 'Templates'), ['No templates']);
    });

    test('sessions carry their state and their tab id', () {
      final menu = buildTrayMenu(
        const TrayMenuData(
          sessions: [
            TraySession(
              tabId: 'a',
              title: 'prod-db',
              state: TraySessionState.connected,
            ),
            TraySession(
              tabId: 'b',
              title: 'staging',
              state: TraySessionState.disconnected,
            ),
            TraySession(
              tabId: 'c',
              title: 'edge',
              state: TraySessionState.connecting,
            ),
          ],
        ),
      );

      expect(submenu(menu, 'Sessions (3)'), [
        '● prod-db',
        '○ staging — disconnected',
        '◌ edge — connecting',
      ]);
      expect(keyOf(menu, '● prod-db'), 'tab:a');
      expect(keyOf(menu, '○ staging — disconnected'), 'tab:b');
    });

    test('running tunnels stop and saved ones start', () {
      final menu = buildTrayMenu(
        const TrayMenuData(
          activeTunnels: [TrayTunnel(ruleId: 'r1', label: 'db · L 8080 → x:1')],
          idleTunnels: [TrayTunnel(ruleId: 'r2', label: 'web · D 1080')],
        ),
      );

      expect(submenu(menu, 'Tunnels (1 active)'), [
        'Stop  db · L 8080 → x:1',
        'Start  web · D 1080',
      ]);
      expect(keyOf(menu, 'Stop  db · L 8080 → x:1'), 'tunnel.stop:r1');
      expect(keyOf(menu, 'Start  web · D 1080'), 'tunnel.start:r2');
    });

    test('saved tunnels alone leave the title without a count', () {
      final menu = buildTrayMenu(
        const TrayMenuData(
          idleTunnels: [TrayTunnel(ruleId: 'r2', label: 'web · D 1080')],
        ),
      );

      expect(submenu(menu, 'Tunnels'), ['Start  web · D 1080']);
      expect(topLevel(menu), contains('Tunnels'));
    });

    test('favorites list hosts, then templates', () {
      final menu = buildTrayMenu(
        const TrayMenuData(
          favoriteHosts: [TrayTarget(id: 'h1', label: 'prod')],
          favoriteTemplates: [TrayTarget(id: 't1', label: 'Dev layout')],
          templates: [
            TrayTarget(id: 't1', label: 'Dev layout'),
            TrayTarget(id: 't2', label: 'Ops'),
          ],
        ),
      );

      expect(submenu(menu, 'Favorites'), ['prod', 'Dev layout']);
      expect(submenu(menu, 'Templates'), ['Dev layout', 'Ops']);
      expect(keyOf(menu, 'prod'), 'host:h1');
      expect(keyOf(menu, 'Ops'), 'template:t2');
    });

    test('a long list is capped and says how much it left out', () {
      final menu = buildTrayMenu(
        TrayMenuData(
          sessions: [
            for (var i = 0; i < 13; i++)
              TraySession(
                tabId: 't$i',
                title: 'tab $i',
                state: TraySessionState.connected,
              ),
          ],
          templates: [
            for (var i = 0; i < 10; i++) TrayTarget(id: 't$i', label: 'tpl $i'),
          ],
        ),
      );

      final sessions = submenu(menu, 'Sessions (13)');
      expect(sessions, hasLength(kTrayMenuSubmenuLimit + 1));
      expect(sessions.last, '+3 more in ShellVibe');
      // Exactly at the cap: nothing to report.
      expect(submenu(menu, 'Templates'), hasLength(kTrayMenuSubmenuLimit));
    });

    test('a label too long for a menu is cut to one line', () {
      final menu = buildTrayMenu(
        TrayMenuData(
          favoriteHosts: [TrayTarget(id: 'h', label: 'a\nb ${'x' * 100}')],
        ),
      );

      final label = submenu(menu, 'Favorites').single;
      expect(label, isNot(contains('\n')));
      expect(label.length, lessThanOrEqualTo(48));
      expect(label, endsWith('…'));
    });
  });

  group('a locked vault', () {
    test('leaves an unlock entry, the counts and Quit', () {
      final menu = buildTrayMenu(
        const TrayMenuData(locked: true, sessionCount: 2, activeTunnelCount: 1),
      );

      expect(topLevel(menu), [
        'Unlock ShellVibe…',
        '---',
        '2 open sessions',
        '1 active tunnel',
        '---',
        'Quit ShellVibe',
      ]);
      expect(keyOf(menu, 'Unlock ShellVibe…'), 'show');
      expect(menu.items!.every((item) => item.submenu == null), isTrue);
    });

    test('says one session in the singular', () {
      final menu = buildTrayMenu(
        const TrayMenuData(locked: true, sessionCount: 1),
      );

      expect(topLevel(menu), contains('1 open session'));
      expect(topLevel(menu), contains('0 active tunnels'));
    });

    test('is not the same data as the unlocked menu', () {
      expect(const TrayMenuData(locked: true), isNot(const TrayMenuData()));
    });
  });

  group('TrayAction.parse', () {
    test('decodes every key the menu builds', () {
      expect(TrayAction.parse('show'), isA<TrayShow>());
      expect(TrayAction.parse('quit'), isA<TrayQuit>());
      expect((TrayAction.parse('tab:abc') as TrayFocusTab).tabId, 'abc');
      expect(
        (TrayAction.parse('tunnel.stop:r1') as TrayStopTunnel).ruleId,
        'r1',
      );
      expect(
        (TrayAction.parse('tunnel.start:r1') as TrayStartTunnel).ruleId,
        'r1',
      );
      expect((TrayAction.parse('host:h1') as TrayConnectHost).hostId, 'h1');
      expect(
        (TrayAction.parse('template:t1') as TrayRunTemplate).templateId,
        't1',
      );
    });

    test('an id that itself contains a colon survives', () {
      expect(
        (TrayAction.parse('host:prompt:h1') as TrayConnectHost).hostId,
        'prompt:h1',
      );
    });

    test('unknown, empty and missing keys decode to nothing', () {
      expect(TrayAction.parse(null), isNull);
      expect(TrayAction.parse(''), isNull);
      expect(TrayAction.parse('tab:'), isNull);
      expect(TrayAction.parse('nope:1'), isNull);
    });
  });

  group('tunnelRouteLabel', () {
    test('reads like the ssh flag it came from', () {
      expect(
        tunnelRouteLabel(
          type: 'local',
          localPort: 8080,
          remoteHost: 'db',
          remotePort: 5432,
        ),
        'L 8080 → db:5432',
      );
      expect(
        tunnelRouteLabel(
          type: 'remote',
          localPort: 3000,
          remoteHost: 'localhost',
          remotePort: 9000,
        ),
        'R 9000 → localhost:3000',
      );
      expect(
        tunnelRouteLabel(type: 'dynamic', localPort: 1080),
        'D 1080 (SOCKS5)',
      );
    });
  });

  group('TrayMenuData', () {
    test('equal content compares equal, a changed state does not', () {
      const a = TrayMenuData(
        sessions: [
          TraySession(
            tabId: 'a',
            title: 'x',
            state: TraySessionState.connected,
          ),
        ],
      );
      const same = TrayMenuData(
        sessions: [
          TraySession(
            tabId: 'a',
            title: 'x',
            state: TraySessionState.connected,
          ),
        ],
      );
      const dropped = TrayMenuData(
        sessions: [
          TraySession(
            tabId: 'a',
            title: 'x',
            state: TraySessionState.disconnected,
          ),
        ],
      );

      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(a, isNot(dropped));
    });
  });
}
