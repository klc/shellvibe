import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/snippets/domain/services/snippet_variable_parser.dart';

void main() {
  group('SnippetVariableParser Unit Tests', () {
    test('extractVariables returns unique INPUT variable names', () {
      const code =
          'echo \${INPUT:PORT_FORWARD} and \${INPUT:PORT} and \${INPUT:PORT}';
      final vars = SnippetVariableParser.extractVariables(code);
      expect(vars, unorderedEquals(['PORT_FORWARD', 'PORT']));
    });

    test('a plain shell variable is not a prompted variable', () {
      const code = 'echo \${HOME} \${PWD}';
      expect(SnippetVariableParser.extractVariables(code), isEmpty);
      expect(
        SnippetVariableParser.substituteVariables(code, {'HOME': 'x'}),
        equals(code),
      );
    });

    test('mixed INPUT and shell variables only prompt for INPUT', () {
      const code = 'cd \${INPUT:dir} && echo \${HOME}';
      expect(SnippetVariableParser.extractVariables(code), ['dir']);
      expect(
        SnippetVariableParser.substituteVariables(code, {'dir': '/srv'}),
        equals('cd /srv && echo \${HOME}'),
      );
    });

    test('substituteVariables handles several input variables', () {
      const code = 'ssh -p \${INPUT:PORT} user@\${INPUT:HOST}';
      final substituted = SnippetVariableParser.substituteVariables(code, {
        'PORT': '2222',
        'HOST': 'example.com',
      });
      expect(substituted, equals('ssh -p 2222 user@example.com'));
    });

    test('a key that prefixes another is not replaced inside it', () {
      const code = '\${INPUT:PORT_FORWARD} \${INPUT:PORT}';
      final substituted = SnippetVariableParser.substituteVariables(code, {
        'PORT': '8080',
        'PORT_FORWARD': '8080:80',
      });
      expect(substituted, equals('8080:80 8080'));
    });

    test('an empty entered value substitutes to empty; a missing one stays', () {
      const code = 'a\${INPUT:x}b\${INPUT:y}';
      expect(
        SnippetVariableParser.substituteVariables(code, {'x': ''}),
        equals('ab\${INPUT:y}'),
      );
    });
  });
}
