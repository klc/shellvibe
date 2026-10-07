import 'package:flutter_test/flutter_test.dart';

import 'package:shellvibe/features/mcp/domain/services/output_redactor.dart';

/// A PEM key cut in half by the output cap must still be masked.
void main() {
  const redactor = OutputRedactor();
  const body1 = 'b3BlbnNzaC1rZXktdjEAAAAAdummybodyline1';
  const body2 = 'AAAAC3NzaC1lZDI1NTE5AAAAIdummybodyline2';
  const cut = '[... 4096 bytes kirpildi ...]';

  test('a header half (footer cut off) is masked', () {
    final r = redactor.redact(
      'before\n-----BEGIN OPENSSH PRIVATE KEY-----\n$body1\n$body2\n$cut\nafter',
    );
    expect(r.text, isNot(contains(body1)));
    expect(r.text, isNot(contains(body2)));
    expect(r.text, contains('before'));
    expect(r.text, contains(cut));
    expect(r.text, contains('after'));
    expect(r.count, 1);
  });

  test('a footer half (header cut off) is masked', () {
    final r = redactor.redact(
      'before\n$cut\n$body1\n$body2\n-----END OPENSSH PRIVATE KEY-----\nafter',
    );
    expect(r.text, isNot(contains(body1)));
    expect(r.text, isNot(contains(body2)));
    expect(r.text, contains(cut));
    expect(r.text, contains('after'));
    expect(r.count, 1);
  });

  test('a complete key is still masked once, as one block', () {
    final r = redactor.redact(
      '-----BEGIN RSA PRIVATE KEY-----\n$body1\n$body2\n'
      '-----END RSA PRIVATE KEY-----',
    );
    expect(r.text, '[REDACTED:private_key]');
    expect(r.count, 1);
  });

  test('ordinary output is left alone', () {
    const text = 'total 12\ndrwxr-xr-x 2 root root 4096 Oct  8 .ssh\nok';
    final r = redactor.redact(text);
    expect(r.text, text);
    expect(r.count, 0);
  });
}
