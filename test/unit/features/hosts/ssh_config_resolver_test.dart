import 'package:flutter_test/flutter_test.dart';

import 'package:shellvibe/features/hosts/domain/models/ssh_config_models.dart';
import 'package:shellvibe/features/hosts/domain/services/ssh_config_resolver.dart';

/// In-memory resolver harness: a fake file system for loader/lister plus a
/// ready resolver bound to `~/home` with a few environment variables.
class Harness {
  final Map<String, String> files = {};
  final List<String> touchedPaths = [];

  late final SshConfigResolver resolver = SshConfigResolver(
    loader: (path) async {
      touchedPaths.add(path);
      return files[path];
    },
    lister: (dir) async {
      final prefix = dir == '.' ? '' : '$dir/';
      return files.keys
          .where((p) => p.startsWith(prefix) && !p.substring(prefix.length).contains('/'))
          .map((p) => p.substring(prefix.length))
          .toList()
        ..sort();
    },
    homePath: '/home/user',
    environment: const {'TERLY_DEPLOY': 'prod'},
  );

  Future<SshConfigResolution> resolve(String content, {String path = 'config'}) {
    return resolver.resolveContent(path, content);
  }
}

void main() {
  group('SshConfigResolver', () {
    test('resolves a plain concrete host', () async {
      final h = Harness();
      final res = await h.resolve(
        'Host web\n'
        '  HostName web.example.com\n'
        '  User deploy\n'
        '  Port 2222\n',
      );

      expect(res.hosts, hasLength(1));
      final host = res.hosts.single;
      expect(host.alias, 'web');
      expect(host.hostname, 'web.example.com');
      expect(host.username, 'deploy');
      expect(host.port, 2222);
      expect(res.warnings, isEmpty);
    });

    test('HostName defaults to the alias', () async {
      final res = await Harness().resolve('Host web\nUser root\n');
      expect(res.hosts.single.hostname, 'web');
    });

    test('first obtained value wins across stanzas', () async {
      final res = await Harness().resolve(
        'Host web\n  User first\n  Port 22\n'
        'Host web\n  User second\n  Port 99\n'
        'Host *\n  User global\n',
      );
      final host = res.hosts.single;
      expect(host.username, 'first');
      expect(host.port, 22);
    });

    test('global defaults apply through Host *', () async {
      final res = await Harness().resolve(
        'Host web\n  HostName web.example.com\n'
        'Host db\n  HostName db.example.com\n'
        '  Port 5432\n'
        'Host *\n  User root\n  Port 2200\n',
      );
      expect(res.hosts, hasLength(2));
      final web = res.hosts.firstWhere((h) => h.alias == 'web');
      final db = res.hosts.firstWhere((h) => h.alias == 'db');
      expect(web.username, 'root');
      expect(web.port, 2200);
      expect(db.username, 'root');
      expect(db.port, 5432, reason: 'host-specific value beats the default');
    });

    test('wildcard stanzas are not imported as hosts', () async {
      final res = await Harness().resolve(
        'Host *.example.com\n  User root\n'
        'Host *\n  Port 22\n',
      );
      expect(res.hosts, isEmpty);
    });

    test('Host pattern matching: wildcards, negation, alternation, case', () async {
      final res = await Harness().resolve(
        'Host web1|web3\n  User alt\n'
        'Host web*\n  User wild\n'
        'Host WEB1\n  User upper\n'
        'Host !web2\n  User negated\n',
      );

      String userOf(String alias) =>
          res.hosts.firstWhere((h) => h.alias == alias).username!;

      expect(userOf('web1'), 'alt', reason: '| alternation matches');
      expect(userOf('web2'), 'wild', reason: 'negated pattern vetoes the '
          'negated stanza, wildcard remains');
      expect(userOf('web3'), 'alt');
      expect(userOf('WEB1'), 'upper', reason: 'patterns are case-sensitive '
          'in both directions');
    });

    test('negation vetoes a stanza regardless of other patterns', () async {
      final res = await Harness().resolve(
        'Host web* !webx\n  User team\n'
        'Host webx\n  User special\n'
        'Host web1\n  User one\n',
      );
      expect(res.hosts.firstWhere((h) => h.alias == 'webx').username,
          'special');
      expect(res.hosts.firstWhere((h) => h.alias == 'web1').username, 'team',
          reason: 'web1 is not vetoed, so the first stanza applies');
    });

    test('only-negated Host pattern applies to everything else', () async {
      final res = await Harness().resolve(
        'Host !web\n  User others\n'
        'Host web\n  User me\n'
        'Host db\n  User dbu\n',
      );
      expect(res.hosts.firstWhere((h) => h.alias == 'web').username, 'me');
      expect(res.hosts.firstWhere((h) => h.alias == 'db').username, 'others');
    });

    test('Match all applies unconditionally', () async {
      final res = await Harness().resolve(
        'Match all\n  User matcher\n'
        'Host web\n',
      );
      expect(res.hosts.single.username, 'matcher');
    });

    test('Match host matches the resolved hostname, not the alias', () async {
      final res = await Harness().resolve(
        'Host web\n  HostName web.example.com\n'
        'Match host web.example.com\n  User matched\n'
        'Match host web\n  User notThisOne\n',
      );
      expect(res.hosts.single.username, 'matched');
    });

    test('Match user and negation', () async {
      final res = await Harness().resolve(
        'Host web\n  User root\n'
        'Match user root\n  Port 2222\n'
        'Match !user root\n  Port 1111\n',
      );
      expect(res.hosts.single.port, 2222);
    });

    test('runtime-only Match criteria skip the stanza with a warning', () async {
      final res = await Harness().resolve(
        'Host web\n'
        'Match exec "test -f /tmp/x"\n  User execUser\n'
        'Match canonical\n  User canonUser\n',
      );
      final host = res.hosts.single;
      expect(host.username, isNull);
      expect(res.warnings, isNotEmpty);
      expect(res.warnings.any((w) => w.message.contains('exec')), isTrue);
    });

    test('token expansion in Hostname, User and IdentityFile', () async {
      final res = await Harness().resolve(
        'Host web\n'
        '  HostName %h.internal\n'
        '  User app-%p\n'
        '  IdentityFile ~/.ssh/id_ed25519\n'
        '  IdentityFile %d/.ssh/deploy_%r\n',
      );
      final host = res.hosts.single;
      expect(host.hostname, 'web.internal');
      expect(host.username, 'app-22');
      expect(host.identityFiles,
          ['/home/user/.ssh/id_ed25519', '/home/user/.ssh/deploy_app-22']);
    });

    test('unresolvable tokens stay literal with a warning', () async {
      final res = await Harness().resolve(
        'Host web\n  IdentityFile %u/.ssh/key\n',
      );
      expect(res.hosts.single.identityFiles, ['%u/.ssh/key']);
      expect(res.warnings.any((w) => w.message.contains('%u')), isTrue);
    });

    test('IdentityFile accumulates and none clears it', () async {
      final res = await Harness().resolve(
        'Host web\n'
        '  IdentityFile ~/.ssh/one\n'
        '  IdentityFile ~/.ssh/two\n'
        'Host none\n'
        '  IdentityFile ~/.ssh/one\n'
        '  IdentityFile none\n',
      );
      expect(res.hosts.firstWhere((h) => h.alias == 'web').identityFiles,
          ['/home/user/.ssh/one', '/home/user/.ssh/two']);
      expect(res.hosts.firstWhere((h) => h.alias == 'none').identityFiles,
          isEmpty);
    });

    test('ProxyJump parses user, host and port; multi-hop keeps first', () async {
      final res = await Harness().resolve(
        'Host web\n  ProxyJump user@bastion:2222,jump2\n',
      );
      final jump = res.hosts.single.jumpHost!;
      expect(jump.username, 'user');
      expect(jump.host, 'bastion');
      expect(jump.port, 2222);
      expect(res.hosts.single.jumpViaProxyCommand, isFalse);
    });

    test('ProxyJump none disables jump and wins first-obtained', () async {
      final res = await Harness().resolve(
        'Host web\n  ProxyJump none\n  ProxyJump bastion\n',
      );
      expect(res.hosts.single.jumpHost, isNull);
    });

    test('ProxyCommand ssh -W is approximated as a jump host', () async {
      final res = await Harness().resolve(
        'Host web\n  ProxyCommand ssh -W %h:%p user@bastion\n',
      );
      final host = res.hosts.single;
      expect(host.jumpHost!.host, 'bastion');
      expect(host.jumpHost!.username, 'user');
      expect(host.jumpViaProxyCommand, isTrue);
    });

    test('non -W ProxyCommand is reported unsupported', () async {
      final res = await Harness().resolve(
        'Host web\n  ProxyCommand nc -X connect -x proxy %h %p\n',
      );
      expect(res.hosts.single.jumpHost, isNull);
      expect(res.warnings.any((w) => w.message.contains('ProxyCommand')),
          isTrue);
    });

    test('forwards parse with bind addresses and IPv6 brackets', () async {
      final res = await Harness().resolve(
        'Host web\n'
        '  LocalForward 8080 localhost:80\n'
        '  LocalForward 127.0.0.1:9090 db:5432\n'
        '  LocalForward [::1]:8443 [::1]:443\n'
        '  RemoteForward 3306 db:3306\n'
        '  DynamicForward 1080\n',
      );
      final forwards = res.hosts.single.forwards;
      expect(forwards, hasLength(5));
      expect(forwards[0].type, 'local');
      expect(forwards[0].localPort, 8080);
      expect(forwards[0].remoteHost, 'localhost');
      expect(forwards[0].remotePort, 80);
      expect(forwards[0].bindAddress, isNull);
      expect(forwards[1].bindAddress, '127.0.0.1');
      expect(forwards[2].bindAddress, '::1');
      expect(forwards[2].remoteHost, '::1');
      expect(forwards[3].type, 'remote');
      expect(forwards[4].type, 'dynamic');
      expect(forwards[4].remoteHost, isNull);
    });

    test('unmappable forwards are skipped with warnings', () async {
      final res = await Harness().resolve(
        'Host web\n'
        '  LocalForward /tmp/sock localhost:80\n'
        '  RemoteForward 1080\n'
        '  LocalForward 0 localhost:80\n'
        '  LocalForward 8080\n',
      );
      expect(res.hosts.single.forwards, isEmpty);
      expect(res.warnings.length, greaterThanOrEqualTo(4));
    });

    test('unmapped options warn for the curated list only', () async {
      final res = await Harness().resolve(
        'Host web\n'
        '  ControlMaster auto\n'
        '  ForwardAgent yes\n'
        '  ServerAliveInterval 60\n',
      );
      final messages = res.warnings.map((w) => w.message).toList();
      expect(messages.any((m) => m.contains('ControlMaster')), isTrue);
      expect(messages.any((m) => m.contains('ForwardAgent')), isTrue);
      expect(messages.any((m) => m.contains('ServerAliveInterval')), isFalse);
    });

    test('Include flattens files; relative paths resolve under ~/.ssh',
        () async {
      final h = Harness();
      h.files['config'] = 'Include extra.conf\nHost web\n  HostName %h.x\n';
      h.files['/home/user/.ssh/extra.conf'] = 'Host extra\n  User incl\n';
      final res = await h.resolver.resolveFile('config');

      expect(h.touchedPaths, contains('/home/user/.ssh/extra.conf'));
      expect(res.hosts, hasLength(2));
      expect(res.hosts.firstWhere((h) => h.alias == 'extra').username, 'incl');
      expect(res.hosts.firstWhere((h) => h.alias == 'web').hostname, 'web.x');
    });

    test('Include with glob expands in lexical order', () async {
      final h = Harness();
      h.files['config'] = 'Include ~/.ssh/conf.d/*.conf\n';
      h.files['/home/user/.ssh/conf.d/b.conf'] = 'Host bee\n  User b\n';
      h.files['/home/user/.ssh/conf.d/a.conf'] = 'Host aye\n  User a\n';
      final res = await h.resolver.resolveFile('config');
      expect(res.hosts.map((x) => x.alias).toList(), ['aye', 'bee']);
    });

    test('Include env var expansion', () async {
      final h = Harness();
      h.files['config'] = r'Include ${TERLY_DEPLOY}.conf' '\n';
      h.files['/home/user/.ssh/prod.conf'] = 'Host prod\n  User p\n';
      final res = await h.resolver.resolveFile('config');
      expect(res.hosts.single.alias, 'prod');
    });

    test('Include cycle is detected', () async {
      final h = Harness();
      h.files['/home/user/.ssh/config'] = 'Include a.conf\n';
      h.files['/home/user/.ssh/a.conf'] =
          'Include config\nHost a\n  User x\n';
      final res = await h.resolver.resolveFile('/home/user/.ssh/config');
      expect(res.warnings.any((w) => w.message.contains('cycle')), isTrue);
      expect(res.hosts.single.alias, 'a');
    });

    test('missing Include is an info warning, not an error', () async {
      final h = Harness();
      h.files['config'] = 'Include nope.conf\nHost web\n';
      final res = await h.resolver.resolveFile('config');
      expect(res.hosts.single.alias, 'web');
      expect(res.warnings.any((w) => w.message.contains('not found')), isTrue);
    });

    test('Include inside a Host block is skipped with a warning', () async {
      final h = Harness();
      h.files['config'] =
          'Host web\n  Include other.conf\n  User main\n';
      h.files['/home/user/.ssh/other.conf'] = 'Host other\n  User o\n';
      final res = await h.resolver.resolveFile('config');
      expect(res.hosts, hasLength(1));
      expect(res.hosts.single.alias, 'web');
      expect(res.warnings.any((w) => w.message.contains('Host/Match block')),
          isTrue);
    });

    test(
        'the same directive matching several aliases dedupes to one warning',
        () async {
      // One ControlMaster directive, matched by both aliases via
      // alternation — the per-alias resolution reports it twice, but it is
      // the same source+line, so it is one problem.
      final res = await Harness().resolve('Host web|db\n  ControlMaster auto\n');
      final messages = res.warnings
          .map((w) => w.message)
          .where((m) => m.contains('ControlMaster'))
          .toList();
      expect(messages.length, 1);
    });

    test('the same message at different lines is not collapsed away',
        () async {
      // Two distinct ControlMaster directives that happen to produce
      // identical message text must surface as two separate problems.
      final res = await Harness().resolve(
        'Host web\n  ControlMaster auto\n'
        'Host db\n  ControlMaster auto\n',
      );
      final messages = res.warnings
          .map((w) => w.message)
          .where((m) => m.contains('ControlMaster'))
          .toList();
      expect(messages.length, 2);
    });

    test('unreadable root file yields an error warning', () async {
      final res = await Harness().resolver.resolveFile('missing');
      expect(res.hosts, isEmpty);
      expect(res.warnings.single.severity, SshConfigWarningSeverity.error);
    });

    test('invalid Port is ignored with a warning', () async {
      final res = await Harness().resolve('Host web\n  Port abc\n');
      expect(res.hosts.single.port, 22);
      expect(res.warnings.any((w) => w.message.contains('Invalid Port')),
          isTrue);
    });
  });
}
