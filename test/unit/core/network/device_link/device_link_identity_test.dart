import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/network/device_link/device_link_identity.dart';

void main() {
  test(
    'generates distinct self-signed identities with stable pins',
    () {
      final first = DeviceLinkIdentity.generate();
      final second = DeviceLinkIdentity.generate();

      expect(first.certificatePem, contains('BEGIN CERTIFICATE'));
      expect(first.privateKeyPem, contains('BEGIN PRIVATE KEY'));
      expect(first.subjectPublicKeyInfo, isNotEmpty);
      expect(first.spkiSha256Base64, isNotEmpty);
      expect(first.spkiSha256Base64, first.spkiSha256Base64);
      expect(
        DeviceLinkIdentity.spkiSha256Base64FromCertificateDer(
          _certificateDer(first.certificatePem),
        ),
        first.spkiSha256Base64,
      );
      expect(
        DeviceLinkIdentity.matchesSpkiPin(
          _certificateDer(first.certificatePem),
          first.spkiSha256Base64,
        ),
        isTrue,
      );
      expect(second.spkiSha256Base64, isNot(first.spkiSha256Base64));
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'creates a TLS server SecurityContext',
    () {
      final identity = DeviceLinkIdentity.generate();

      expect(() => identity.createServerSecurityContext(), returnsNormally);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test('rejects invalid identity input without exposing key material', () {
    expect(
      () => DeviceLinkIdentity.generate(commonName: ' '),
      throwsA(isA<DeviceLinkIdentityException>()),
    );
    expect(
      () => DeviceLinkIdentity.generate(validityDays: 0),
      throwsA(isA<DeviceLinkIdentityException>()),
    );
  });
}

List<int> _certificateDer(String pem) {
  final body = pem
      .replaceAll('-----BEGIN CERTIFICATE-----', '')
      .replaceAll('-----END CERTIFICATE-----', '')
      .replaceAll(RegExp(r'\s+'), '');
  return base64.decode(body);
}
