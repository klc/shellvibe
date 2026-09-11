import 'package:flutter_test/flutter_test.dart';

import 'package:shellvibe/features/mcp/domain/services/forbidden_paths.dart';

void main() {
  const guard = ForbiddenPaths();

  group('built-in globs match obvious positives', () {
    const positives = <String>[
      '/home/u/.ssh/id_rsa',
      '/srv/app/.env',
      '/srv/app/.env.production',
      '/etc/shadow',
      '/etc/gshadow',
      '/certs/site.pem',
      '/certs/site.key',
      '/home/u/.aws/credentials',
      '/home/u/.netrc',
      '/home/u/.pgpass',
      '/home/u/.git-credentials',
    ];

    for (final path in positives) {
      test('$path is forbidden', () {
        expect(guard.isForbidden(path), isTrue);
      });
    }
  });

  group('obvious negatives are not forbidden', () {
    const negatives = <String>[
      '/var/log/nginx/access.log',
      '/home/u/notes.txt',
      '/etc/hosts',
    ];

    for (final path in negatives) {
      test('$path is not forbidden', () {
        expect(guard.isForbidden(path), isFalse);
      });
    }
  });

  group('normalization catches path traversal', () {
    test('/etc/../etc/shadow is caught', () {
      expect(guard.isForbidden('/etc/../etc/shadow'), isTrue);
    });

    test('/etc//shadow is caught', () {
      expect(guard.isForbidden('/etc//shadow'), isTrue);
    });
  });

  group('extraGlobs are honored', () {
    test('a path matching an extra glob is forbidden', () {
      final custom = ForbiddenPaths(extraGlobs: const ['**/*.secret']);
      expect(custom.isForbidden('/tmp/config.secret'), isTrue);
    });

    test(
      'a path not matching any glob (built-in or extra) is not forbidden',
      () {
        final custom = ForbiddenPaths(extraGlobs: const ['**/*.secret']);
        expect(custom.isForbidden('/tmp/config.txt'), isFalse);
      },
    );

    test('extra globs do not affect a guard that lacks them', () {
      expect(guard.isForbidden('/tmp/config.secret'), isFalse);
    });
  });
}
