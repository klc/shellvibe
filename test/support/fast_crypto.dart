import 'package:cryptography/cryptography.dart';
import 'package:shellvibe/core/crypto/encryption_engine.dart';

/// An [EncryptionEngine] whose Argon2id runs at the cheapest settings the
/// library accepts.
///
/// For tests about what gets sealed, opened, restored or synced — not about
/// the KDF, which `encryption_engine_test` covers at the real settings. Those
/// cost most of a second per derivation, and a backup or sync test derives
/// dozens of keys.
///
/// Everything that seals and everything that opens in one test has to share
/// it: an envelope does not record the settings it was sealed under.
EncryptionEngine fastEncryptionEngine() => EncryptionEngine(
  kdf: Argon2id(parallelism: 1, memory: 1024, iterations: 1, hashLength: 32),
);
