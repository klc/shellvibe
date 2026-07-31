import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/features/snippets/domain/services/snippet_variable_parser.dart';

void main() {
  group('SnippetVariableParser Unit Tests', () {
    test('extractVariables extracts \${INPUT:VarName} and \${VarName}', () {
      const code = r'docker run -p ${INPUT:Port_Num}:80 -e HOST=${HostName} ${INPUT:ImageName}';
      final vars = SnippetVariableParser.extractVariables(code);

      expect(vars, containsAll(['Port_Num', 'HostName', 'ImageName']));
      expect(vars.length, equals(3));
    });

    test('extractVariables returns empty list when no variables present', () {
      const code = 'echo "Hello World" && ls -la';
      final vars = SnippetVariableParser.extractVariables(code);

      expect(vars, isEmpty);
    });

    test('substituteVariables replaces placeholders correctly', () {
      const code = r'ssh ${USER}@${INPUT:Host_IP} -p ${INPUT:Port}';
      final values = {
        'USER': 'admin',
        'Host_IP': '192.168.1.10',
        'Port': '2222',
      };

      final substituted = SnippetVariableParser.substituteVariables(code, values);
      expect(substituted, equals('ssh admin@192.168.1.10 -p 2222'));
    });
  });
}
