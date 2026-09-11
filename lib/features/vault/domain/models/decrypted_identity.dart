/// Represents an Identity with decrypted credential fields.
///
/// This model only exists in memory during an active vault session —
/// it is never persisted to disk in plaintext. Used when establishing
/// SSH connections that need the raw password or private key.
class DecryptedIdentity {
  final String id;
  final String title;
  final String username;
  final String authType;
  final String? password;
  final String? privateKey;
  final String? passphrase;

  const DecryptedIdentity({
    required this.id,
    required this.title,
    required this.username,
    required this.authType,
    this.password,
    this.privateKey,
    this.passphrase,
  });
}
