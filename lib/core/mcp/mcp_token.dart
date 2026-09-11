import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

// `DartSha256` (the pure-Dart, synchronous implementation) lives in the
// `dart.dart` entrypoint, not the default `cryptography.dart` one. The
// default `Sha256()` factory can resolve to a platform-specific backend
// (e.g. FFI) whose `hash()` is async-only; [McpToken.hash] and
// [McpToken.verify] are specified as synchronous, and this file is also
// compiled into the standalone `shellvibe-mcp` bridge binary where pulling
// in a platform channel is undesirable anyway, so `DartSha256` is used
// explicitly.
import 'package:cryptography/dart.dart';

/// Generates and verifies MCP client bearer tokens.
///
/// This deliberately hashes with **SHA-256**, not the Argon2id used for
/// Device Link pairing secrets (see
/// `features/device_link/data/repositories/device_link_pairing_repository.dart`).
/// The two secrets are not the same kind of thing:
///
/// - A Device Link pairing secret is short-lived and, more importantly, is
///   *comparable* to a low-entropy user-chosen value in the threat model
///   Argon2id defends against — the whole point of a slow KDF is to make
///   guessing expensive when the input space might be small. It is also
///   verified **once per pairing**, so the cost of a slow hash is paid a
///   handful of times per device.
/// - An MCP token is 32 bytes of CSPRNG output (see [generate]). There is no
///   dictionary or low-entropy guessing surface to defend against — the
///   search space is 2^256. What dominates the threat model instead is that
///   [verify] runs on **every JSON-RPC request** the bridge forwards, for as
///   long as the session is open. Argon2id here would not buy any additional
///   security (there is nothing weak in the input to slow an attacker down
///   against) while spending real wall-clock time on the server's own CPU on
///   every single call — and it would do so *before* any rate limiter gets a
///   chance to reject the request, meaning a hostile or buggy client could
///   turn the KDF itself into a denial-of-service lever against the app.
///
/// SHA-256 is the correct tool for "is this high-entropy random token the
/// one we issued", and a fast hash is exactly what you want when it runs on
/// the hot path.
class McpToken {
  const McpToken._();

  static final Random _random = Random.secure();

  /// Generates a new raw MCP token: 32 bytes of [Random.secure] output,
  /// base64url-encoded with the padding `=` characters stripped.
  ///
  /// Mirrors `DeviceLinkPairingTokenStore.issue` (see
  /// `core/network/device_link/device_link_server.dart`), which uses the
  /// same 32-byte / `Random.secure` / base64url-minus-padding shape for its
  /// one-time pairing tokens.
  static String generate() {
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => _random.nextInt(256)),
    );
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Returns the lowercase hex SHA-256 digest of [token].
  ///
  /// This is the only form of the token that is ever persisted to the
  /// database (`McpClients.tokenHash`) — the raw token is shown to the user
  /// once at creation time and otherwise only lives in
  /// `~/.shellvibe/mcp-endpoint.json` (see `mcp_endpoint_file.dart`).
  static String hash(String token) {
    final digest = const DartSha256().hashSync(utf8.encode(token));
    return digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Verifies that [token] hashes to [expectedHash].
  ///
  /// The comparison is written to run in constant time with respect to how
  /// much of the two hashes match: it does NOT short-circuit (via `==`,
  /// early `return false`, or `break`) on the first differing byte. Instead
  /// every byte position is compared and the differences are accumulated
  /// with a bitwise OR, so the number of loop iterations — and therefore the
  /// running time — depends only on the length of the strings being
  /// compared, never on their content. This defends against a timing attack
  /// where an attacker who can measure response latency to microsecond
  /// precision could otherwise recover the expected hash one byte at a time
  /// by observing how much longer a "closer" guess takes to reject.
  static bool verify(String token, String expectedHash) {
    final actualHash = hash(token);
    final actualBytes = utf8.encode(actualHash);
    final expectedBytes = utf8.encode(expectedHash);

    // A length mismatch is itself safe to reveal early: SHA-256 hex digests
    // are always exactly 64 characters, so a wrong length only ever happens
    // for a malformed/corrupt stored hash, never as a function of how many
    // token bytes an attacker guessed correctly.
    if (actualBytes.length != expectedBytes.length) return false;

    var difference = 0;
    for (var i = 0; i < actualBytes.length; i++) {
      difference |= actualBytes[i] ^ expectedBytes[i];
    }
    return difference == 0;
  }
}
