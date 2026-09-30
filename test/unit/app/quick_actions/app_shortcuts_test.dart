import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/quick_actions/app_shortcuts.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';

HostModel _host(String id, {String? label, String protocol = 'ssh'}) =>
    HostModel(
      id: id,
      workspaceId: 'default',
      label: label ?? 'Host $id',
      hostname: '$id.example.com',
      protocol: protocol,
      createdAt: DateTime(2026),
    );

void main() {
  group('buildAppShortcuts', () {
    test('lists bookmarked hosts in bookmark order, then Quick connect', () {
      final shortcuts = buildAppShortcuts(
        hosts: [_host('a'), _host('b'), _host('c')],
        bookmarkedHostIds: ['c', 'a'],
      );

      expect(shortcuts.map((s) => s.type), [
        'host:c',
        'host:a',
        kQuickConnectShortcutType,
      ]);
      expect(shortcuts.first.title, 'Host c');
      expect(shortcuts.first.subtitle, 'c.example.com');
    });

    test('caps hosts at three and the whole menu at four', () {
      final hosts = [for (final id in 'abcde'.split('')) _host(id)];
      final shortcuts = buildAppShortcuts(
        hosts: hosts,
        bookmarkedHostIds: ['a', 'b', 'c', 'd', 'e'],
      );

      expect(shortcuts.map((s) => s.type), [
        'host:a',
        'host:b',
        'host:c',
        kQuickConnectShortcutType,
      ]);
    });

    test('a local terminal shares the four places with the hosts', () {
      final hosts = [for (final id in 'abcde'.split('')) _host(id)];
      final shortcuts = buildAppShortcuts(
        hosts: hosts,
        bookmarkedHostIds: ['a', 'b', 'c', 'd', 'e'],
        supportsLocalTerminal: true,
      );

      expect(shortcuts, hasLength(kMaxAppShortcuts));
      expect(shortcuts.map((s) => s.type), [
        'host:a',
        'host:b',
        kLocalTerminalShortcutType,
        kQuickConnectShortcutType,
      ]);
    });

    test('omits the local terminal where there is none', () {
      final shortcuts = buildAppShortcuts(hosts: [], bookmarkedHostIds: []);

      expect(shortcuts.map((s) => s.type), [kQuickConnectShortcutType]);
    });

    test('skips bookmarks whose host is gone and duplicate bookmarks', () {
      final shortcuts = buildAppShortcuts(
        hosts: [_host('a')],
        bookmarkedHostIds: ['ghost', 'a', 'a'],
      );

      expect(shortcuts.map((s) => s.type), [
        'host:a',
        kQuickConnectShortcutType,
      ]);
    });

    test('ignores hosts that are not bookmarked', () {
      final shortcuts = buildAppShortcuts(
        hosts: [_host('a'), _host('b')],
        bookmarkedHostIds: ['b'],
      );

      expect(shortcuts.map((s) => s.type), [
        'host:b',
        kQuickConnectShortcutType,
      ]);
    });

    test('a local-protocol host is skipped where there is no local shell', () {
      final hosts = [_host('a', protocol: 'local'), _host('b')];

      expect(
        buildAppShortcuts(
          hosts: hosts,
          bookmarkedHostIds: ['a', 'b'],
        ).map((s) => s.type),
        ['host:b', kQuickConnectShortcutType],
      );
      expect(
        buildAppShortcuts(
          hosts: hosts,
          bookmarkedHostIds: ['a', 'b'],
          supportsLocalTerminal: true,
        ).map((s) => s.type),
        [
          'host:a',
          'host:b',
          kLocalTerminalShortcutType,
          kQuickConnectShortcutType,
        ],
      );
    });

    test('a locked vault withholds every host name', () {
      final shortcuts = buildAppShortcuts(
        hosts: [_host('a')],
        bookmarkedHostIds: ['a'],
        locked: true,
      );

      expect(shortcuts.map((s) => s.type), [kQuickConnectShortcutType]);
      expect(
        shortcuts.any((s) => s.title.contains('Host') || s.subtitle != null),
        isFalse,
      );
    });
  });

  group('parseQuickActionType', () {
    test('routes each known type to its action', () {
      expect(parseQuickActionType('host:abc'), const ConnectHostAction('abc'));
      expect(parseQuickActionType('quick_connect'), isA<QuickConnectAction>());
      expect(
        parseQuickActionType('local_terminal'),
        isA<OpenLocalTerminalAction>(),
      );
    });

    test('keeps everything after the prefix as the host id', () {
      expect(parseQuickActionType('host:a:b'), const ConnectHostAction('a:b'));
    });

    test('ignores unknown types and host shortcuts with no id', () {
      expect(parseQuickActionType('host:'), isNull);
      expect(parseQuickActionType('something_else'), isNull);
      expect(parseQuickActionType(''), isNull);
    });

    test('round-trips the type a host shortcut is registered with', () {
      expect(
        parseQuickActionType(hostShortcutType('x1')),
        const ConnectHostAction('x1'),
      );
    });
  });
}
