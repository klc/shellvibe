import 'package:flutter_test/flutter_test.dart';

import 'package:shellvibe/features/hosts/domain/models/host_model.dart';

HostModel _host({
  String label = 'Production web',
  String hostname = '10.0.0.5',
  String? username = 'deploy',
  String protocol = 'ssh',
}) {
  return HostModel(
    id: 'h1',
    workspaceId: 'default',
    label: label,
    hostname: hostname,
    username: username,
    protocol: protocol,
    createdAt: DateTime.utc(2026),
  );
}

void main() {
  group('hostMatchesQuery', () {
    test('an empty or blank query matches every host', () {
      expect(hostMatchesQuery(_host(), ''), isTrue);
      expect(hostMatchesQuery(_host(), '   '), isTrue);
    });

    test('matches label, hostname, username and protocol', () {
      final host = _host(
        label: 'Production web',
        hostname: 'web.internal',
        username: 'deploy',
        protocol: 'mosh',
      );
      expect(hostMatchesQuery(host, 'production'), isTrue);
      expect(hostMatchesQuery(host, 'internal'), isTrue);
      expect(hostMatchesQuery(host, 'deploy'), isTrue);
      expect(hostMatchesQuery(host, 'mosh'), isTrue);
      expect(hostMatchesQuery(host, 'database'), isFalse);
    });

    test('ignores case and surrounding whitespace in the query', () {
      expect(hostMatchesQuery(_host(label: 'Staging'), '  sTaG '), isTrue);
    });

    test('a host without a username is matched on its other fields', () {
      final host = _host(username: null, label: 'Bastion');
      expect(hostMatchesQuery(host, 'bastion'), isTrue);
      expect(hostMatchesQuery(host, 'deploy'), isFalse);
    });
  });
}
