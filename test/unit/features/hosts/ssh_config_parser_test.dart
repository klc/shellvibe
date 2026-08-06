import 'package:flutter_test/flutter_test.dart';

import 'package:terly2/features/hosts/domain/models/ssh_config_models.dart';
import 'package:terly2/features/hosts/domain/services/ssh_config_parser.dart';

void main() {
  const parser = SshConfigParser();

  group('SshConfigParser', () {
    test('parses keyword/value pairs with case-insensitive keywords', () {
      final doc = parser.parse('HostName example.com\nPort 2222');

      expect(doc.directives, hasLength(2));
      expect(doc.directives[0].keyword, 'hostname');
      expect(doc.directives[0].args, ['example.com']);
      expect(doc.directives[1].keyword, 'port');
      expect(doc.directives[1].args, ['2222']);
      expect(doc.warnings, isEmpty);
    });

    test('strips full-line and trailing comments outside quotes', () {
      final doc = parser.parse(
        '# leading comment\n'
        'Host foo # trailing comment\n'
        'User root\n'
        'HostName "bar#baz.com" # quoted hash survives\n'
        'LocalCommand echo "a # b"',
      );

      final keywords = doc.directives.map((d) => d.keyword).toList();
      expect(keywords, ['host', 'user', 'hostname', 'localcommand']);
      expect(doc.directives[1].args, ['root']);
      expect(doc.directives[2].args, ['bar#baz.com']);
      expect(doc.directives[3].args, ['echo', 'a # b']);
      expect(doc.warnings, isEmpty);
    });

    test('escaped hash is not a comment', () {
      final doc = parser.parse(r'HostName foo\#bar');
      expect(doc.directives.single.args, ['foo#bar']);
    });

    test('joins backslash-continuation lines', () {
      final doc = parser.parse('ProxyCommand ssh -W %h:%p \\\n  bastion\n');
      expect(doc.directives.single.keyword, 'proxycommand');
      expect(doc.directives.single.args, ['ssh', '-W', '%h:%p', 'bastion']);
    });

    test('supports = separator in its three forms', () {
      final doc = parser.parse(
        'HostName=one.example.com\n'
        'HostName = two.example.com\n'
        'Host = alias\n'
        'SendEnv LC_ALL=C\n'
        'Port=2222',
      );

      expect(doc.directives[0].keyword, 'hostname');
      expect(doc.directives[0].args, ['one.example.com']);
      expect(doc.directives[1].keyword, 'hostname');
      expect(doc.directives[1].args, ['two.example.com']);
      expect(doc.directives[2].keyword, 'host');
      expect(doc.directives[2].args, ['alias']);
      expect(doc.directives[3].keyword, 'sendenv');
      expect(doc.directives[3].args, ['LC_ALL=C'], reason: '= inside a value must survive');
      expect(doc.directives[4].args, ['2222']);
    });

    test('splits multiple arguments on whitespace', () {
      final doc = parser.parse('LocalForward 8080 localhost:80');
      expect(doc.directives.single.args, ['8080', 'localhost:80']);
    });

    test('reports lines without arguments as warnings', () {
      final doc = parser.parse('HostName\n');
      expect(doc.directives, isEmpty);
      expect(doc.warnings, hasLength(1));
      expect(doc.warnings.single.message, contains('no arguments'));
    });

    test('reports unterminated quotes as info warnings', () {
      final doc = parser.parse('User "root');
      expect(doc.directives.single.args, ['root']);
      expect(doc.warnings, hasLength(1));
      expect(doc.warnings.single.severity,
          SshConfigWarningSeverity.info);
    });

    test('records source and line numbers', () {
      final doc = parser.parse('Port 22\nUser root', source: 'config');
      expect(doc.directives[0].source, 'config');
      expect(doc.directives[0].line, 1);
      expect(doc.directives[1].line, 2);
    });

    test('handles CRLF line endings', () {
      final doc = parser.parse('Host foo\r\nPort 22\r\n');
      expect(doc.directives, hasLength(2));
      expect(doc.directives[1].args, ['22']);
    });
  });
}
