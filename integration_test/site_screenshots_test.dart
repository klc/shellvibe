@Tags(['screenshots'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dartssh2/dartssh2.dart';
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shellvibe/app/app.dart';
import 'package:shellvibe/app/router/app_router.dart';
import 'package:shellvibe/app/window/desktop_tray.dart';
import 'package:shellvibe/app/window/launch_at_login.dart';
import 'package:shellvibe/core/network/local_pty_manager.dart';
import 'package:shellvibe/core/network/providers/network_providers.dart';
import 'package:shellvibe/core/network/ssh_session_manager.dart';
import 'package:shellvibe/core/network/tunnel_engine.dart';
import 'package:shellvibe/features/bookmarks/presentation/notifiers/bookmarks_notifier.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/hosts/presentation/notifiers/hosts_notifier.dart';
import 'package:shellvibe/features/mcp/data/mcp_server_controller.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_client_repository.dart';
import 'package:shellvibe/features/mcp/presentation/notifiers/mcp_activity_notifier.dart';
import 'package:shellvibe/features/mcp/presentation/notifiers/mcp_settings_notifier.dart';
import 'package:shellvibe/features/mcp/presentation/widgets/mcp_access_settings_section.dart';
import 'package:shellvibe/features/settings/presentation/notifiers/settings_notifier.dart';
import 'package:shellvibe/features/sftp/data/sftp_service.dart';
import 'package:shellvibe/features/sftp/domain/models/sftp_file_item.dart';
import 'package:shellvibe/features/sftp/presentation/providers/sftp_providers.dart';
import 'package:shellvibe/features/snippets/presentation/notifiers/snippets_notifier.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:shellvibe/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:shellvibe/features/tunnels/domain/models/tunnel_rule_model.dart';
import 'package:shellvibe/features/tunnels/presentation/providers/tunnels_providers.dart';
import 'package:shellvibe/features/vault/presentation/notifiers/identities_notifier.dart';
import 'package:shellvibe/features/workspaces/presentation/notifiers/workspaces_notifier.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/database/daos/mcp_dao.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';
import 'package:window_manager/window_manager.dart';
import 'package:xterm3/xterm.dart';

/// The product screenshots on shellvibe.dev and in the README.
///
/// Drives the real app over a throwaway in-memory database and a mocked
/// keychain, so no real host, address or credential reaches an image. The
/// two terminal panes run a real shell: `git log` over this repository and
/// `htop` limited to root's processes. SSH, SFTP, tunnels and the MCP server
/// are faked at their providers.
///
/// Writes 2560x1600 PNGs (1280x800 at 2x) into SHOTS_DIR:
///
///   flutter test integration_test/site_screenshots_test.dart -d macos \
///     --dart-define=SHOTS_DIR=$PWD/build/screenshots \
///     --dart-define=REPO_DIR=$PWD
///
/// then `python3 tool/finish_screenshots.py` frames and scales them.
const _shotsDir = String.fromEnvironment('SHOTS_DIR');
const _repoDir = String.fromEnvironment('REPO_DIR');
const _ws = 'default';

final _boundary = GlobalKey();

/// Starts a clean zsh in a demo home, so the prompt and paths name no one.
class _DemoPtyManager extends LocalPtyManager {
  _DemoPtyManager(this.home);

  final String home;

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
  }) => super.startAndBridge(
    terminal,
    executable: '/bin/zsh',
    arguments: const ['-f'],
    workingDirectory: home,
    environment: {
      'HOME': home,
      'PATH': '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin',
      'TERM': 'xterm-256color',
      'COLORTERM': 'truecolor',
      'LANG': 'en_US.UTF-8',
      'PS1': '%F{green}deploy@workstation%f %F{blue}%~%f %# ',
      'GIT_CONFIG_NOSYSTEM': '1',
    },
    rows: rows,
    columns: columns,
    outputTap: outputTap,
  );
}

class _FakeController extends McpServerController {
  _FakeController()
    : super(
        transportFactory: ({required onRequest, required authenticate}) =>
            throw UnimplementedError(),
        clients: McpClientRepository(_NoDao()),
        onRequest: (_, _, _) async => null,
        isVaultAvailable: () => true,
        activeWorkspaceId: () => _ws,
      );

  bool _running = false;

  @override
  bool get isRunning => _running;

  @override
  String? get workspaceId => _running ? _ws : null;

  @override
  int? get port => _running ? 7433 : null;

  @override
  Future<void> start({bool reinstate = false}) async => _running = true;

  // Never touches ~/.shellvibe/mcp-endpoint.json, which the real stop()
  // deletes: that file belongs to the user's running ShellVibe.
  @override
  Future<void> stop() async => _running = false;
}

class _NoDao implements McpDao {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The AI Activity panel's live view, which needs an open MCP session.
var _activity = McpActivityState.empty;

class _FakeActivity extends McpActivityNotifier {
  @override
  Future<McpActivityState> build() async => _activity;
}

class _FakeSftp implements SftpClient {
  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSsh implements SSHClient {
  @override
  bool get isClosed => false;

  @override
  Future<SftpClient> sftp() async => _FakeSftp();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSession implements SSHSessionManager {
  @override
  final SSHClient client = _FakeSsh();

  @override
  bool get isConnected => true;

  @override
  Stream<SSHClient?> get clientChanges => const Stream.empty();

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A remote web root, served without a server.
class _DemoSftpService extends SftpService {
  @override
  Future<List<SftpFileItem>> listDirectory(
    SftpClient client,
    String path,
  ) async {
    final at = DateTime(2026, 11, 12, 18, 40);
    SftpFileItem dir(String name, int day) => SftpFileItem(
      name: name,
      path: '$path/$name',
      size: 0,
      permissions: 'drwxr-xr-x',
      modifyTime: DateTime(2026, 11, day, 9, 12),
      isDirectory: true,
    );
    SftpFileItem file(String name, int size) => SftpFileItem(
      name: name,
      path: '$path/$name',
      size: size,
      permissions: '-rw-r--r--',
      modifyTime: at,
      isDirectory: false,
    );
    return [
      dir('app', 12),
      dir('bootstrap', 3),
      dir('config', 9),
      dir('public', 12),
      dir('resources', 12),
      dir('routes', 9),
      dir('storage', 13),
      file('.env', 1180),
      file('artisan', 425),
      file('composer.json', 2310),
      file('composer.lock', 412880),
      file('package.json', 512),
      file('vite.config.js', 1064),
    ];
  }
}

var _activeTunnels = <ActiveTunnel>[];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('site screenshots', (tester) async {
    expect(_shotsDir, isNotEmpty, reason: 'pass --dart-define=SHOTS_DIR');
    expect(_repoDir, isNotEmpty, reason: 'pass --dart-define=REPO_DIR');
    Directory(_shotsDir).createSync(recursive: true);

    // A short, fixed path: the SFTP screen prints the local one in full.
    const home = '/tmp/shellvibe-demo';
    final stale = Directory(home);
    if (stale.existsSync()) stale.deleteSync(recursive: true);
    stale.createSync();
    Link('$home/shellvibe').createSync(_repoDir);
    final downloads = Directory('$home/Downloads/release-1.13')
      ..createSync(recursive: true);
    for (final (name, size) in [
      ('backup-2026-11-12.sql.gz', 18342210),
      ('deploy.sh', 4210),
      ('nginx-access.log', 179812),
      ('RELEASE-NOTES.md', 6120),
      ('shellvibe-1.13.0-macos.dmg', 41203112),
    ]) {
      File('${downloads.path}/$name').writeAsBytesSync(Uint8List(size));
    }

    // main.dart does this; the app's window calls crash without it.
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1280, 800));

    FlutterSecureStorage.setMockInitialValues({});
    debugTrayHostAvailableOverride = false;
    debugMcpAgentEnvironmentOverride = const {'HOME': '/Users/demo'};
    debugMcpResolvedExecutableOverride =
        '/Applications/ShellVibe.app/Contents/MacOS/ShellVibe';
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      RepaintBoundary(
        key: _boundary,
        child: ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            localPtyManagerProvider.overrideWithValue(_DemoPtyManager(home)),
            launchAtLoginProvider.overrideWithValue(UnsupportedLaunchAtLogin()),
            mcpServerControllerProvider.overrideWith(
              (ref) => _FakeController(),
            ),
            mcpActivityProvider.overrideWith(_FakeActivity.new),
            sftpServiceProvider.overrideWithValue(_DemoSftpService()),
            activeTunnelsStreamProvider.overrideWith(
              (ref) => Stream.value(_activeTunnels),
            ),
          ],
          child: const ShellVibeApp(),
        ),
      ),
    );
    await _wait(tester, 2000);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellVibeApp)),
    );
    final settings = container.read(settingsProvider.notifier);
    await settings.setThemeMode(ThemeMode.dark);
    await settings.setKeepRunningInTray(false);

    final hosts = await _seed(container, db);
    final router = container.read(appRouterProvider);
    await _wait(tester, 500);

    // Terminal: git log beside htop, in one tab.
    router.go('/terminal');
    await _wait(tester, 500);
    final tabs = container.read(terminalTabsProvider.notifier);
    final left = container.read(terminalTabsProvider).tabs.single;
    left.terminal.textInput(
      'cd ~/shellvibe && clear && git --no-pager log --oneline --decorate --first-parent --color=always -n 26\r',
    );
    await tabs.splitTab(left.id, direction: Axis.horizontal);
    await _wait(tester, 1500);
    final right = container
        .read(terminalTabsProvider)
        .tabs
        .firstWhere((t) => t.id != left.id);
    right.terminal.textInput('htop -u root --sort-key=PERCENT_CPU\r');
    await _wait(tester, 3000);
    await _shot(tester, 'terminal-split');

    // The pane menu, over the git log.
    final pane = tester.getCenter(find.byKey(ValueKey(left.id)));
    final gesture = await tester.startGesture(
      pane - const Offset(120, 60),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await _wait(tester, 800);
    await _shot(tester, 'pane-menu');
    Navigator.of(
      tester.element(find.byKey(const Key('terminal_menu_paste'))),
    ).pop();
    await _wait(tester, 500);

    await tester.tap(find.byKey(const Key('command_palette_button')));
    await _wait(tester, 800);
    await _shot(tester, 'command-palette');
    Navigator.of(
      tester.element(find.byKey(const Key('command_palette_search'))),
    ).pop();
    await _wait(tester, 500);

    // One live SSH session, so a host shows connected and SFTP has a remote.
    final web = hosts['prod-web-01']!;
    final ssh = TerminalTabSession(
      id: 'demo-ssh',
      title: web.label,
      sessionType: TerminalSessionType.ssh,
      host: web,
      terminal: Terminal(),
      isConnected: true,
    )..sshSessionManager = _FakeSession();
    tabs.registerDeviceLinkSession(ssh);
    await _wait(tester, 500);

    router.push('/sftp?tab=${ssh.id}&label=${web.label}');
    await _wait(tester, 1000);
    final sftp = container.read(sftpProvider.notifier);
    await sftp.loadLocalDirectory(downloads.path);
    await sftp.loadRemoteDirectory('/var/www/shellvibe.dev');
    await _wait(tester, 1000);
    await _shot(tester, 'sftp');
    router.pop();
    await _wait(tester, 500);

    for (final (path, name) in [
      ('/hosts', 'hosts'),
      ('/tunnels', 'tunnels'),
      ('/snippets', 'snippets'),
      ('/vault', 'vault'),
      ('/workspaces', 'workspaces'),
      ('/ai-access', 'ai-access'),
      ('/settings/terminal', 'terminal-settings'),
    ]) {
      router.go(path);
      await _wait(tester, 1200);
      if (name == 'ai-access') {
        // The live panel is the point of this one; bring it up the page.
        await Scrollable.ensureVisible(
          tester.element(find.text('AI Activity')),
          alignment: 0.45,
        );
        await _wait(tester, 400);
      }
      await _shot(tester, name);
    }

    // The empty terminal, last: it needs every tab closed.
    for (final tab in [...container.read(terminalTabsProvider).tabs]) {
      await tabs.closeTab(tab.id);
    }
    router.go('/terminal');
    await _wait(tester, 1200);
    await _shot(tester, 'terminal-empty');
  });
}

Future<Map<String, HostModel>> _seed(
  ProviderContainer container,
  AppDatabase db,
) async {
  // autoDispose notifiers: hold them for the length of the run.
  container.listen(hostsProvider, (_, _) {});
  container.listen(snippetsProvider, (_, _) {});
  container.listen(identitiesProvider, (_, _) {});
  container.listen(tunnelsProvider, (_, _) {});
  container.listen(bookmarksProvider, (_, _) {});

  final workspaces = container.read(workspaceManagerProvider.notifier);
  await workspaces.rename(_ws, 'Demo');
  await workspaces.create('Homelab');
  await workspaces.create('Staging');

  final repo = container.read(hostsRepositoryProvider);
  final groups = {
    for (final name in ['prod', 'staging', 'home'])
      name: (await repo.saveHostGroup(workspaceId: _ws, name: name)).id,
  };

  final notifier = container.read(hostsProvider.notifier);
  final hosts = <String, HostModel>{};
  for (final (label, user, address, group) in [
    ('prod-web-01', 'deploy', '10.10.4.21', 'prod'),
    ('prod-db-01', 'postgres', '10.10.4.34', 'prod'),
    ('staging-api', 'deploy', '10.20.7.12', 'staging'),
    ('build-runner', 'ci', '10.30.1.5', null),
    ('homelab-nas', 'admin', '192.168.1.20', 'home'),
  ]) {
    hosts[label] = await notifier.addHost(
      workspaceId: _ws,
      label: label,
      hostname: address,
      username: user,
      groupIds: [if (group != null) groups[group]!],
    );
  }
  final bookmarks = container.read(bookmarksProvider.notifier);
  await bookmarks.toggleHost(hosts['prod-web-01']!.id);
  await bookmarks.toggleHost(hosts['staging-api']!.id);

  final tunnels = container.read(tunnelsProvider.notifier);
  await tunnels.addRule(
    TunnelRuleModel(
      id: 'tunnel-web',
      hostId: hosts['prod-web-01']!.id,
      type: 'local',
      localPort: 8080,
      remoteHost: '127.0.0.1',
      remotePort: 80,
    ),
  );
  await tunnels.addRule(
    TunnelRuleModel(
      id: 'tunnel-db',
      hostId: hosts['prod-db-01']!.id,
      type: 'local',
      localPort: 15432,
      remoteHost: '127.0.0.1',
      remotePort: 5432,
    ),
  );
  await tunnels.addRule(
    TunnelRuleModel(
      id: 'tunnel-socks',
      hostId: hosts['staging-api']!.id,
      type: 'dynamic',
      localPort: 1080,
    ),
  );
  _activeTunnels = [
    ActiveTunnel(
      ruleId: 'tunnel-web',
      hostId: hosts['prod-web-01']!.id,
      type: 'local',
      localPort: 8080,
      remoteHost: '127.0.0.1',
      remotePort: 80,
      bytesTransferred: 48213504,
      speedBytesPerSec: 182400,
    ),
  ];
  container.invalidate(activeTunnelsStreamProvider);

  final snippets = container.read(snippetsProvider.notifier);
  for (final (title, code, tag) in [
    ('Tail a service log', r'journalctl -u ${INPUT:service} -n 200 -f', 'logs'),
    (
      'Restart a service',
      r'sudo systemctl restart ${INPUT:service}',
      'systemd',
    ),
    (
      'Disk usage by folder',
      r'du -h --max-depth=1 ${INPUT:path} | sort -h',
      'disk',
    ),
    (
      'Deploy a release',
      r'cd /srv/app && git fetch --tags && git checkout ${INPUT:tag} && ./deploy.sh',
      'deploy',
    ),
  ]) {
    await snippets.addSnippet(
      workspaceId: _ws,
      title: title,
      code: code,
      tags: [tag],
    );
  }

  final identities = container.read(identitiesProvider.notifier);
  await identities.addIdentity(
    workspaceId: _ws,
    title: 'deploy (production)',
    username: 'deploy',
    authType: 'password',
    password: 'demo-only-password',
  );
  await identities.addIdentity(
    workspaceId: _ws,
    title: 'nas admin',
    username: 'admin',
    authType: 'password',
    password: 'demo-only-password',
  );

  // AI access: two registered clients, one of them active right now.
  final now = DateTime.now();
  final mcp = db.mcpDao;
  final clients = [
    McpClient(
      id: 'client-code',
      workspaceId: _ws,
      name: 'Claude Code',
      tokenHash: 'demo',
      createdAt: now.subtract(const Duration(days: 12)),
      lastSeenAt: now,
    ),
    McpClient(
      id: 'client-desktop',
      workspaceId: _ws,
      name: 'Claude Desktop',
      tokenHash: 'demo',
      createdAt: now.subtract(const Duration(days: 30)),
      lastSeenAt: now.subtract(const Duration(days: 2)),
    ),
  ];
  for (final client in clients) {
    await mcp.insertClient(client.toCompanion(true));
  }
  var n = 0;
  McpAuditLogData audit(String host, String command, int secondsAgo) =>
      McpAuditLogData(
        id: 'audit-${n++}',
        at: now.subtract(Duration(seconds: secondsAgo)),
        clientId: 'client-code',
        clientName: 'Claude Code',
        workspaceId: _ws,
        hostId: hosts[host]!.id,
        hostLabel: host,
        tool: 'run_command',
        argsJson: jsonEncode({'command': command}),
        decision: 'allowed',
        category: 'readonlySafe',
        exitCode: 0,
        durationMs: 180 + secondsAgo,
        outputBytes: 2048,
      );
  final recent = [
    audit('prod-web-01', 'systemctl status nginx', 8),
    audit('prod-web-01', 'tail -n 50 /var/log/nginx/error.log', 41),
    audit('staging-api', 'df -h /var', 95),
    audit('staging-api', 'docker ps --format "{{.Names}} {{.Status}}"', 160),
  ];
  for (final row in recent) {
    await mcp.insertAuditEntry(row.toCompanion(true));
  }
  _activity = McpActivityState(
    clients: [
      McpClientActivity(
        client: clients.first,
        sessions: const [],
        activeGrants: [
          for (final host in ['prod-web-01', 'staging-api'])
            McpHostGrant(
              id: 'grant-$host',
              clientId: 'client-code',
              hostId: hosts[host]!.id,
              mode: 'readonly',
              grantedAt: now.subtract(const Duration(minutes: 20)),
            ),
        ],
        rememberedApprovals: const [],
        recentAudit: recent,
        pendingApprovals: const [],
        hostLabels: {for (final e in hosts.entries) e.value.id: e.key},
      ),
    ],
  );
  await container.read(mcpSettingsProvider.notifier).setMasterEnabled(true);
  container.invalidate(mcpActivityProvider);

  return hosts;
}

/// Real time for the shell and the app's timers, then a frame.
Future<void> _wait(WidgetTester tester, int ms) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pump();
  await tester.pump();
}

Future<void> _shot(WidgetTester tester, String name) async {
  final boundary =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  File('$_shotsDir/$name.png').writeAsBytesSync(bytes!);
  debugPrint('[shot] $name');
}
