import 'package:flutter_test/flutter_test.dart';

import 'package:shellvibe/features/mcp/domain/services/output_redactor.dart';

void main() {
  const redactor = OutputRedactor();

  group('built-in patterns mask and count exactly once per occurrence', () {
    test('AWS access key', () {
      final result = redactor.redact(
        'export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE',
      );
      expect(result.count, 1);
      expect(result.text, isNot(contains('AKIAIOSFODNN7EXAMPLE')));
      expect(result.text, contains('[REDACTED:aws_key]'));
    });

    test('GitHub personal access token', () {
      const token =
          'ghp_abcdefghijklmnopqrstuvwxyz1234567890ABCD'; // 40 chars after ghp_
      final result = redactor.redact('token: $token');
      expect(result.count, 1);
      expect(result.text, isNot(contains(token)));
      expect(result.text, contains('[REDACTED:github_token]'));
    });

    test('OpenAI-style sk- API key', () {
      const key = 'sk-abcdefghij1234567890ABCDEFGHIJ';
      final result = redactor.redact('OPENAI_API_KEY=$key');
      expect(result.count, 1);
      expect(result.text, isNot(contains(key)));
      expect(result.text, contains('[REDACTED:api_key]'));
    });

    test('JWT', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
          '.eyJzdWIiOiIxMjM0NTY3ODkwIn0'
          '.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U';
      final result = redactor.redact('Authorization: Bearer $jwt');
      expect(result.count, 1);
      expect(result.text, isNot(contains(jwt)));
      expect(result.text, contains('[REDACTED:jwt]'));
    });

    test('password=hunter2 assignment', () {
      final result = redactor.redact('password=hunter2');
      expect(result.count, 1);
      expect(result.text, isNot(contains('hunter2')));
      expect(result.text, contains('[REDACTED:assignment]'));
    });

    test('postgres URL with inline credentials', () {
      final result = redactor.redact('postgres://u:p@host/db');
      expect(result.count, 1);
      expect(result.text, isNot(contains('u:p@')));
      expect(result.text, contains('[REDACTED:db_url]'));
    });
  });

  test('a multi-line PEM private key block is masked in full, no line of '
      'the key body survives', () {
    const keyBody =
        'b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gt\n'
        'ZWQyNTUxOQAAACBleGFtcGxlS2V5Qm9keUxpbmVPbmUxMjM0NTY3ODkwYWJjZGVmZ2hp\n'
        'ZXhhbXBsZUtleUJvZHlMaW5lVHdvYWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0\n'
        'ZXhhbXBsZUtleUJvZHlMaW5lVGhyZWU5ODc2NTQzMjEwemF5eHd2dXRzcnFwb25tbGtq';
    final pem =
        '-----BEGIN OPENSSH PRIVATE KEY-----\n$keyBody\n'
        '-----END OPENSSH PRIVATE KEY-----';
    final surroundingOutput = 'reading id_rsa...\n$pem\ndone reading key.';

    final result = redactor.redact(surroundingOutput);

    expect(result.count, 1);
    expect(result.text, contains('[REDACTED:private_key]'));
    // Not one line of the key body may survive, individually or as a
    // whole. A partially masked key is a leaked key.
    for (final line in keyBody.split('\n')) {
      expect(result.text, isNot(contains(line)));
    }
    expect(result.text, isNot(contains(keyBody)));
    // The surrounding, non-secret text must be preserved.
    expect(result.text, contains('reading id_rsa...'));
    expect(result.text, contains('done reading key.'));
  });

  test('count is exact across several different secrets in one text', () {
    const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.abcdefghij1234';
    final text =
        'aws=AKIAIOSFODNN7EXAMPLE\n'
        'gh=ghp_abcdefghijklmnopqrstuvwxyz1234567890ABCD\n'
        'openai=sk-abcdefghij1234567890ABCDEFGHIJ\n'
        'jwt=$jwt\n'
        'password=hunter2\n'
        'db=postgres://u:p@host/db';

    final result = redactor.redact(text);

    expect(result.count, 6);
  });

  test('count is 0 for text containing no secrets', () {
    final result = redactor.redact(
      'just a normal log line with nothing sensitive in it',
    );
    expect(result.count, 0);
    expect(result.text, 'just a normal log line with nothing sensitive in it');
  });

  test('an assignment keeps the key name visible, masks only the value', () {
    final result = redactor.redact('password: hunter2');
    expect(result.text, startsWith('password: '));
    expect(result.text, contains('[REDACTED:assignment]'));
    expect(result.text, isNot(contains('hunter2')));
  });

  test('a postgres URL keeps scheme and host, masks only the credentials', () {
    final result = redactor.redact('postgres://user:pw@host/db');
    expect(result.text, 'postgres://[REDACTED:db_url]@host/db');
  });

  test('caller-supplied extraPatterns are applied and counted', () {
    final customRedactor = OutputRedactor(
      extraPatterns: [RegExp(r'CUSTOM-SECRET-\d+')],
    );

    final result = customRedactor.redact(
      'value is CUSTOM-SECRET-12345 in this line',
    );

    expect(result.count, 1);
    expect(result.text, isNot(contains('CUSTOM-SECRET-12345')));
    expect(result.text, contains('[REDACTED:custom]'));
  });

  test('extraPatterns do not affect a redactor without them', () {
    final result = redactor.redact('value is CUSTOM-SECRET-12345 in this line');
    expect(result.count, 0);
    expect(result.text, contains('CUSTOM-SECRET-12345'));
  });
}
