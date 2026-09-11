import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';

/// In-memory TLS identity used by a Device Link server.
///
/// The identity is intentionally not persisted here. Callers own persistence
/// and must store the private key through the app's secure-storage boundary.
final class DeviceLinkIdentity {
  final String certificatePem;
  final String privateKeyPem;
  final Uint8List _subjectPublicKeyInfo;

  DeviceLinkIdentity._({
    required this.certificatePem,
    required this.privateKeyPem,
    required Uint8List subjectPublicKeyInfo,
  }) : _subjectPublicKeyInfo = Uint8List.fromList(subjectPublicKeyInfo);

  /// Generates a self-signed RSA identity suitable for a local TLS listener.
  factory DeviceLinkIdentity.generate({
    String commonName = 'shellvibe-device-link',
    int validityDays = 365,
  }) {
    if (commonName.trim().isEmpty) {
      throw const DeviceLinkIdentityException(
        'Certificate common name is empty',
      );
    }
    if (validityDays <= 0) {
      throw const DeviceLinkIdentityException(
        'Certificate validity is invalid',
      );
    }

    try {
      final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
      final privateKey = keyPair.privateKey as RSAPrivateKey;
      final publicKey = keyPair.publicKey as RSAPublicKey;
      final csr = X509Utils.generateRsaCsrPem(
        {'CN': commonName},
        privateKey,
        publicKey,
      );
      final certificate = X509Utils.generateSelfSignedCertificate(
        privateKey,
        csr,
        validityDays,
        serialNumber: DateTime.now().microsecondsSinceEpoch.toString(),
      );
      final privateKeyPem = CryptoUtils.encodeRSAPrivateKeyToPem(privateKey);
      // Read the SPKI back from the certificate. This makes the pin exactly
      // match the bytes a peer will parse from the TLS certificate, including
      // any canonicalization performed by the X.509 encoder.
      final certificateData = X509Utils.x509CertificateFromPem(certificate);
      final certificateSpki =
          certificateData.tbsCertificate?.subjectPublicKeyInfo.bytes;
      if (certificateSpki == null || certificateSpki.isEmpty) {
        throw const DeviceLinkIdentityException(
          'Generated certificate has no subject public key info',
        );
      }
      final spki = base64.decode(certificateSpki);

      return DeviceLinkIdentity._(
        certificatePem: certificate,
        privateKeyPem: privateKeyPem,
        subjectPublicKeyInfo: spki,
      );
    } catch (error) {
      throw DeviceLinkIdentityException(
        'Failed to generate the Device Link TLS identity',
        error,
      );
    }
  }

  /// Restores an identity persisted by the desktop secure-storage boundary.
  factory DeviceLinkIdentity.fromPem({
    required String certificatePem,
    required String privateKeyPem,
  }) {
    try {
      final certificateData = X509Utils.x509CertificateFromPem(certificatePem);
      final certificateSpki =
          certificateData.tbsCertificate?.subjectPublicKeyInfo.bytes;
      if (certificateSpki == null || certificateSpki.isEmpty) {
        throw const DeviceLinkIdentityException(
          'Persisted certificate has no subject public key info',
        );
      }
      final identity = DeviceLinkIdentity._(
        certificatePem: certificatePem,
        privateKeyPem: privateKeyPem,
        subjectPublicKeyInfo: base64.decode(certificateSpki),
      );
      // Validate the pair before returning it. Without this check a corrupted
      // or mismatched secure-storage record would survive until the first
      // listener start and be reported as an opaque server-start failure.
      identity.createServerSecurityContext();
      return identity;
    } catch (error) {
      if (error is DeviceLinkIdentityException) rethrow;
      throw DeviceLinkIdentityException(
        'Failed to restore the Device Link TLS identity',
        error,
      );
    }
  }

  /// DER-encoded SubjectPublicKeyInfo used for QR pinning.
  Uint8List get subjectPublicKeyInfo =>
      Uint8List.fromList(_subjectPublicKeyInfo);

  /// Base64(SHA-256(SubjectPublicKeyInfo DER)).
  String get spkiSha256Base64 => base64.encode(
    CryptoUtils.getHashPlain(_subjectPublicKeyInfo, algorithmName: 'SHA-256'),
  );

  /// Computes the same pin from the DER bytes received during a TLS handshake.
  static String spkiSha256Base64FromCertificateDer(List<int> certificateDer) {
    if (certificateDer.isEmpty) {
      throw const DeviceLinkIdentityException('Peer certificate is empty');
    }
    final certificate = X509Utils.x509CertificateFromPem(
      _derToPem(certificateDer),
    );
    final subjectPublicKeyInfo =
        certificate.tbsCertificate?.subjectPublicKeyInfo.bytes;
    if (subjectPublicKeyInfo == null || subjectPublicKeyInfo.isEmpty) {
      throw const DeviceLinkIdentityException(
        'Peer certificate has no subject public key info',
      );
    }
    return base64.encode(
      CryptoUtils.getHashPlain(
        base64.decode(subjectPublicKeyInfo),
        algorithmName: 'SHA-256',
      ),
    );
  }

  /// Compares a peer certificate pin without returning certificate details.
  static bool matchesSpkiPin(List<int> certificateDer, String expectedPin) {
    try {
      final actual = spkiSha256Base64FromCertificateDer(certificateDer);
      return _constantTimeEquals(actual, expectedPin);
    } on Object {
      return false;
    }
  }

  /// Creates a server context containing only this identity's certificate.
  SecurityContext createServerSecurityContext() {
    final context = SecurityContext(withTrustedRoots: false);
    context.useCertificateChainBytes(utf8.encode(certificatePem));
    context.usePrivateKeyBytes(utf8.encode(privateKeyPem));
    return context;
  }

  static String _derToPem(List<int> der) {
    final encoded = base64.encode(der);
    final lines = <String>[];
    for (var offset = 0; offset < encoded.length; offset += 64) {
      final end = offset + 64 > encoded.length ? encoded.length : offset + 64;
      lines.add(encoded.substring(offset, end));
    }
    return '-----BEGIN CERTIFICATE-----\n'
        '${lines.join('\n')}\n'
        '-----END CERTIFICATE-----';
  }

  static bool _constantTimeEquals(String left, String right) {
    var difference = left.length ^ right.length;
    final length = left.length < right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      difference |= left.codeUnitAt(i) ^ right.codeUnitAt(i);
    }
    return difference == 0;
  }
}

/// Non-sensitive error raised while building a TLS identity.
class DeviceLinkIdentityException implements Exception {
  final String message;
  final Object? cause;

  const DeviceLinkIdentityException(this.message, [this.cause]);

  @override
  String toString() => 'DeviceLinkIdentityException: $message';
}
