import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/snippets/domain/services/snippet_variable_parser.dart';

void main() {
  group('SnippetVariableParser Unit Tests', () {
    test('extractVariables returns unique variable names', () {
      const code = 'echo \${INPUT:PORT_FORWARD} and \${PORT} and \${INPUT:PORT}';
      final vars = SnippetVariableParser.extractVariables(code);
      expect(vars, containsAll(['PORT_FORWARD', 'PORT']));
    });

    test('substituteVariables replaces longer keys first to prevent substring replacement bugs', () {
      const code = 'connect to \${PORT_FORWARD} and \${PORT}';
      final values = {
        'PORT': '8080',
        'PORT_FORWARD': '8080:80',
      };

      final substituted = SnippetVariableParser.substituteVariables(code, values);
      expect(substituted, equals('connect to 8080:80 and 8080'));
    });

    test('substituteVariables handles input prefixed variables', () {
      const code = 'ssh -p \${INPUT:PORT} user@\${INPUT:HOST}';
      final values = {
        'PORT': '2222',
        'HOST': 'example.com',
      };

      final substituted = SnippetVariableParser.substituteVariables(code, values);
      expect(substituted, equals('ssh -p 2222 user@example.com'));
    });
  });
}
