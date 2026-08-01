import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Cycle 17 Form Validation Unit Tests', () {
    test('Host port number validation rule (1 <= port <= 65535)', () {
      String? validatePort(String v) {
        if (v.trim().isEmpty) return 'Required';
        final port = int.tryParse(v.trim());
        if (port == null || port < 1 || port > 65535) {
          return 'Must be between 1 and 65535';
        }
        return null;
      }

      expect(validatePort('22'), isNull);
      expect(validatePort('8080'), isNull);
      expect(validatePort('65535'), isNull);
      expect(validatePort('1'), isNull);
      expect(validatePort('0'), equals('Must be between 1 and 65535'));
      expect(validatePort('65536'), equals('Must be between 1 and 65535'));
      expect(validatePort('-1'), equals('Must be between 1 and 65535'));
      expect(validatePort('abc'), equals('Must be between 1 and 65535'));
      expect(validatePort(''), equals('Required'));
    });

    test('Identity private key validation rule for SSH Private Key', () {
      String? validatePrivateKey(String v) {
        if (v.trim().isEmpty) return 'Private key is required';
        return null;
      }

      expect(validatePrivateKey('-----BEGIN OPENSSH PRIVATE KEY-----\nkey\n-----END OPENSSH PRIVATE KEY-----'), isNull);
      expect(validatePrivateKey('  '), equals('Private key is required'));
      expect(validatePrivateKey(''), equals('Private key is required'));
    });

    test('Runbook step exit code validation rule', () {
      String? validateExitCode(String val) {
        if (val.trim().isEmpty) return 'Required';
        if (int.tryParse(val.trim()) == null) {
          return 'Must be a valid integer';
        }
        return null;
      }

      expect(validateExitCode('0'), isNull);
      expect(validateExitCode('1'), isNull);
      expect(validateExitCode('-1'), isNull);
      expect(validateExitCode('127'), isNull);
      expect(validateExitCode(''), equals('Required'));
      expect(validateExitCode('abc'), equals('Must be a valid integer'));
      expect(validateExitCode('1.5'), equals('Must be a valid integer'));
    });

    test('Runbook 0-step prevention validation rule', () {
      bool canSaveRunbook(List<dynamic> steps) {
        return steps.isNotEmpty;
      }

      expect(canSaveRunbook([]), isFalse);
      expect(canSaveRunbook(['step1']), isTrue);
    });
  });
}
