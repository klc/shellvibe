import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/mcp/mcp_token.dart';

void main() {
  group('McpToken.generate', () {
    test('produces a distinct value on every call', () {
      final tokens = List.generate(200, (_) => McpToken.generate()).toSet();
      // 32 bytes of Random.secure output colliding inside 200 draws would mean
      // the generator is not actually random, which is the failure worth
      // catching here — not the (astronomically unlikely) genuine collision.
      expect(tokens.length, 200);
    });

    test('is URL-safe base64 with no padding', () {
      for (var i = 0; i < 20; i++) {
        final token = McpToken.generate();
        expect(token, isNot(contains('=')));
        expect(token, isNot(contains('+')));
        expect(token, isNot(contains('/')));
        expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(token), isTrue);
      }
    });

    test('carries the full 32 bytes of entropy', () {
      // base64 of 32 bytes is 43 characters once the single '=' pad is
      // stripped. A shorter token would mean entropy was lost somewhere.
      expect(McpToken.generate().length, 43);
    });
  });

  group('McpToken.hash', () {
    test('is stable for the same input', () {
      const token = 'a-fixed-token-value';
      expect(McpToken.hash(token), McpToken.hash(token));
    });

    test('is lowercase hex of exactly 64 characters', () {
      final hash = McpToken.hash(McpToken.generate());
      expect(hash.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash), isTrue);
    });

    test('matches the known SHA-256 digest of a known input', () {
      // Pins the algorithm itself: if `hash` were ever swapped for another
      // digest, every stored token would silently stop authenticating.
      expect(
        McpToken.hash('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('differs for inputs that differ by one character', () {
      expect(McpToken.hash('token-a'), isNot(McpToken.hash('token-b')));
    });
  });

  group('McpToken.verify', () {
    test('accepts the token its hash was made from', () {
      final token = McpToken.generate();
      expect(McpToken.verify(token, McpToken.hash(token)), isTrue);
    });

    test('rejects a different token', () {
      final stored = McpToken.hash(McpToken.generate());
      expect(McpToken.verify(McpToken.generate(), stored), isFalse);
    });

    test('rejects a truncated token', () {
      final token = McpToken.generate();
      final stored = McpToken.hash(token);
      expect(
        McpToken.verify(token.substring(0, token.length - 1), stored),
        isFalse,
      );
    });

    test('rejects a token with one extra character appended', () {
      final token = McpToken.generate();
      expect(McpToken.verify('${token}x', McpToken.hash(token)), isFalse);
    });

    test('rejects a stored hash of the wrong length', () {
      final token = McpToken.generate();
      final stored = McpToken.hash(token);
      // A corrupt or truncated column value must fail closed rather than
      // matching on a prefix.
      expect(McpToken.verify(token, stored.substring(0, 32)), isFalse);
      expect(McpToken.verify(token, ''), isFalse);
    });

    test('rejects a hash that differs only in its final byte', () {
      final token = McpToken.generate();
      final stored = McpToken.hash(token);
      final lastChar = stored[stored.length - 1];
      final flipped =
          stored.substring(0, stored.length - 1) +
          (lastChar == 'a' ? 'b' : 'a');
      expect(McpToken.verify(token, flipped), isFalse);
    });

    test('is case-sensitive about the stored hash', () {
      final token = McpToken.generate();
      expect(
        McpToken.verify(token, McpToken.hash(token).toUpperCase()),
        isFalse,
      );
    });
  });
}
