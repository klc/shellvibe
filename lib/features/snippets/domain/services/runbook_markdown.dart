import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/runbook_model.dart';
import '../models/runbook_step_model.dart';
import '../models/snippet_model.dart';
import '../models/variable_declaration.dart';

/// Why a Markdown file could not become a runbook. The message is for the
/// person importing: it names the step or key at fault.
class RunbookMarkdownException implements Exception {
  final String message;
  const RunbookMarkdownException(this.message);

  @override
  String toString() => message;
}

/// Runbooks as Markdown, close to what Runme reads: YAML frontmatter, then one
/// fenced shell block per command step, the block's info string carrying the
/// step's options as JSON.
///
/// ````markdown
/// ---
/// title: "Deploy"
/// tags: ["ops"]
/// defaults: {"expectedExitCode":0,"onFailure":"stop","retries":0,"timeout":30}
/// ---
///
/// ```sh {"name":"step-1","retries":2}
/// systemctl restart app
/// ```
///
/// > [!approval] Check the dashboards, then continue
/// ````
///
/// Frontmatter values are written as JSON, which is valid YAML, so the file
/// reads as ordinary frontmatter anywhere and parses back exactly.
///
/// A snippet step is exported as the snippet's current code, since a file
/// cannot refer to a snippet that only exists in one person's library; it
/// comes back as an ordinary command step.
class RunbookMarkdown {
  static const _shellLanguages = {'sh', 'bash', 'shell', 'zsh', 'console'};

  /// The built-in step defaults; an option equal to them is left out of an
  /// export, and a step with no option takes the file's `defaults` over these.
  static const _builtIn = {
    'expectedExitCode': 0,
    'onFailure': 'stop',
    'retries': 0,
    'timeout': 30,
  };

  /// [runbook] as Markdown. [snippets] resolves snippet steps to their code.
  static String export(
    RunbookModel runbook, {
    Map<String, SnippetModel> snippets = const {},
  }) {
    final out = StringBuffer('---\n');
    out.writeln('title: ${jsonEncode(runbook.title)}');
    if (runbook.description != null && runbook.description!.isNotEmpty) {
      out.writeln('description: ${jsonEncode(runbook.description)}');
    }
    if (runbook.tags.isNotEmpty) {
      out.writeln('tags: ${jsonEncode(runbook.tags)}');
    }
    if (runbook.variables.isNotEmpty) {
      out.writeln(
        'variables: ${jsonEncode([for (final v in runbook.variables) v.toJson()])}',
      );
    }
    out.writeln('defaults: ${jsonEncode(_builtIn)}');
    out.writeln('---');

    final steps = [...runbook.steps]
      ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
    for (final (index, step) in steps.indexed) {
      out.writeln();
      if (step.kind == StepKind.approval) {
        final lines = step.command.split('\n');
        out.writeln('> [!approval] ${lines.first}');
        for (final line in lines.skip(1)) {
          out.writeln('> $line');
        }
        continue;
      }
      var code = step.command;
      if (step.kind == StepKind.snippet) {
        final snippet = snippets[step.snippetId];
        out.writeln(
          '<!-- Snippet step, exported inline as the snippet\'s current code. '
          '-->',
        );
        code = snippet?.code ?? step.command;
      }
      final options = <String, Object>{
        'name': 'step-${index + 1}',
        if (step.expectedExitCode != _builtIn['expectedExitCode'])
          'expectedExitCode': step.expectedExitCode,
        if (step.onFailure != StepFailurePolicy.stop)
          'onFailure': step.onFailure.wireName,
        if (step.retries != _builtIn['retries']) 'retries': step.retries,
        if (step.timeoutSeconds != _builtIn['timeout'])
          'timeout': step.timeoutSeconds,
        if (step.expectedOutputPattern != null &&
            step.expectedOutputPattern!.isNotEmpty)
          'expectedOutput': step.expectedOutputPattern!,
      };
      // A fence longer than any run of backticks inside the command.
      final longest = RegExp('`+')
          .allMatches(code)
          .fold<int>(0, (m, e) => e.end - e.start > m ? e.end - e.start : m);
      final fence = '`' * (longest >= 3 ? longest + 1 : 3);
      out.writeln('${fence}sh ${jsonEncode(options)}');
      out.writeln(code);
      out.writeln(fence);
    }
    return out.toString();
  }

  /// Reads [markdown] as a new runbook in [workspaceId], with fresh ids.
  ///
  /// Lenient about the file: a plain `sh` / `bash` block with no options is a
  /// command step with the defaults, blocks in other languages and prose are
  /// ignored. Strict about what it does read: an option that is wrong, or
  /// JSON that does not parse, is an error naming the step, never a silent
  /// fallback.
  static RunbookModel import(
    String markdown, {
    required String workspaceId,
    DateTime? now,
  }) {
    final lines = const LineSplitter().convert(markdown);
    var cursor = 0;

    final front = <String, Object?>{};
    if (lines.isNotEmpty && lines.first.trim() == '---') {
      final end = lines.indexWhere((l) => l.trim() == '---', 1);
      if (end < 0) {
        throw const RunbookMarkdownException(
          'The frontmatter is not closed: expected a second "---" line.',
        );
      }
      _readFrontmatter(lines.sublist(1, end), front);
      cursor = end + 1;
    }

    final defaults = _defaultsOf(front['defaults']);
    final runbookId = const Uuid().v4();
    final steps = <RunbookStepModel>[];
    String? heading;

    RunbookStepModel add({
      required String command,
      StepKind kind = StepKind.command,
      Map<String, Object?> options = const {},
    }) {
      final order = steps.length + 1;
      final label = 'Step $order';
      final merged = {...defaults, ...options};
      final exit = merged['expectedExitCode'];
      final retries = merged['retries'];
      final timeout = merged['timeout'];
      final onFailure = merged['onFailure'];
      final pattern = merged['expectedOutput'];
      if (exit is! int) {
        throw RunbookMarkdownException(
          '$label: expectedExitCode must be a whole number.',
        );
      }
      if (retries is! int ||
          retries < 0 ||
          retries > RunbookStepModel.maxRetries) {
        throw RunbookMarkdownException(
          '$label: retries must be a whole number from 0 to '
          '${RunbookStepModel.maxRetries}.',
        );
      }
      if (timeout is! int || timeout < 1) {
        throw RunbookMarkdownException(
          '$label: timeout must be a positive number of seconds.',
        );
      }
      if (onFailure != 'stop' && onFailure != 'continue') {
        throw RunbookMarkdownException(
          '$label: onFailure must be "stop" or "continue".',
        );
      }
      if (pattern != null) {
        if (pattern is! String) {
          throw RunbookMarkdownException(
            '$label: expectedOutput must be text.',
          );
        }
        try {
          RegExp(pattern);
        } catch (_) {
          throw RunbookMarkdownException(
            '$label: expectedOutput is not a valid regular expression.',
          );
        }
      }
      return RunbookStepModel(
        id: const Uuid().v4(),
        runbookId: runbookId,
        stepOrder: order,
        command: command,
        kind: kind,
        expectedExitCode: exit,
        expectedOutputPattern: pattern as String?,
        timeoutSeconds: timeout,
        onFailure: StepFailurePolicy.parse(onFailure as String),
        retries: retries,
      );
    }

    final fence = RegExp(r'^(\s*)(`{3,}|~{3,})\s*([^\s`]*)\s*(.*)$');
    while (cursor < lines.length) {
      final line = lines[cursor];
      final open = fence.firstMatch(line);
      if (open != null) {
        final marker = open.group(2)!;
        final language = open.group(3)!.toLowerCase();
        final info = open.group(4)!.trim();
        final body = <String>[];
        cursor++;
        var closed = false;
        while (cursor < lines.length) {
          final candidate = lines[cursor].trim();
          if (candidate.startsWith(marker[0] * marker.length) &&
              candidate.replaceAll(marker[0], '').isEmpty) {
            closed = true;
            cursor++;
            break;
          }
          body.add(lines[cursor]);
          cursor++;
        }
        if (!closed) {
          throw RunbookMarkdownException(
            'A code block is never closed (expected a line of $marker).',
          );
        }
        if (!_shellLanguages.contains(language)) continue;
        final command = body.join('\n').trim();
        if (command.isEmpty) continue;
        steps.add(
          add(
            command: command,
            options: _optionsOf(info, 'Step ${steps.length + 1}'),
          ),
        );
        continue;
      }

      final approval = RegExp(
        r'^\s*>\s*\[!approval\]\s?(.*)$',
      ).firstMatch(line);
      if (approval != null) {
        final message = [approval.group(1)!.trim()];
        cursor++;
        while (cursor < lines.length) {
          final next = RegExp(r'^\s*>\s?(.*)$').firstMatch(lines[cursor]);
          if (next == null) break;
          message.add(next.group(1)!);
          cursor++;
        }
        final text = message.join('\n').trim();
        if (text.isEmpty) {
          throw RunbookMarkdownException(
            'Step ${steps.length + 1}: an approval needs a message after [!approval].',
          );
        }
        steps.add(add(command: text, kind: StepKind.approval));
        continue;
      }

      heading ??= RegExp(r'^#\s+(.+?)\s*#*\s*$').firstMatch(line)?.group(1);
      cursor++;
    }

    if (steps.isEmpty) {
      throw const RunbookMarkdownException(
        'No steps found. A step is a fenced sh or bash code block, or a '
        '"> [!approval] message" quote.',
      );
    }

    final title = (front['title'] as String?)?.trim().isNotEmpty ?? false
        ? (front['title'] as String).trim()
        : (heading ?? 'Imported runbook');
    final description = front['description'] as String?;
    return RunbookModel(
      id: runbookId,
      workspaceId: workspaceId,
      title: title,
      description: description == null || description.isEmpty
          ? null
          : description,
      steps: steps,
      createdAt: now ?? DateTime.now(),
      tags: _stringList(front['tags'], 'tags'),
      variables: _variablesOf(front['variables']),
    );
  }

  static Map<String, Object?> _optionsOf(String info, String label) {
    if (!info.startsWith('{')) return const {};
    try {
      final decoded = jsonDecode(info);
      if (decoded is! Map) throw const FormatException();
      return {for (final e in decoded.entries) '${e.key}': e.value};
    } catch (_) {
      throw RunbookMarkdownException(
        '$label: the options after the language are not valid JSON.',
      );
    }
  }

  static Map<String, Object?> _defaultsOf(Object? raw) {
    if (raw == null) return {..._builtIn};
    if (raw is! Map) {
      throw const RunbookMarkdownException('"defaults" must be a mapping.');
    }
    return {..._builtIn, for (final e in raw.entries) '${e.key}': e.value};
  }

  static List<String> _stringList(Object? raw, String key) {
    if (raw == null) return const [];
    if (raw is! List) {
      throw RunbookMarkdownException('"$key" must be a list.');
    }
    return [for (final item in raw) '$item'.trim()]
      ..removeWhere((s) => s.isEmpty);
  }

  static List<VariableDeclaration> _variablesOf(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List) {
      throw const RunbookMarkdownException('"variables" must be a list.');
    }
    final result = <VariableDeclaration>[];
    for (final item in raw) {
      final declaration = VariableDeclaration.tryFromJson(item);
      if (declaration == null) {
        throw const RunbookMarkdownException(
          'Each entry of "variables" needs at least a name.',
        );
      }
      result.add(declaration);
    }
    return result;
  }

  /// `key: value` lines: the value is JSON when it parses as such (which is
  /// how an export writes it) and plain text otherwise, so a hand-written
  /// `title: Deploy` works. A key with nothing after it followed by `- item`
  /// lines is a list.
  static void _readFrontmatter(List<String> lines, Map<String, Object?> into) {
    String? listKey;
    for (final raw in lines) {
      if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) continue;
      final item = RegExp(r'^\s+-\s+(.*)$').firstMatch(raw);
      if (item != null && listKey != null) {
        (into[listKey] as List).add(_scalar(item.group(1)!));
        continue;
      }
      final pair = RegExp(
        r'^([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.*)$',
      ).firstMatch(raw);
      if (pair == null) {
        throw RunbookMarkdownException(
          'The frontmatter has a line that is not "key: value": "$raw".',
        );
      }
      final key = pair.group(1)!;
      final value = pair.group(2)!.trim();
      if (value.isEmpty) {
        listKey = key;
        into[key] = <Object?>[];
      } else {
        listKey = null;
        into[key] = _scalar(value);
      }
    }
  }

  static Object? _scalar(String value) {
    try {
      return jsonDecode(value);
    } catch (_) {
      final unquoted =
          value.length >= 2 &&
              ((value.startsWith("'") && value.endsWith("'")) ||
                  (value.startsWith('"') && value.endsWith('"')))
          ? value.substring(1, value.length - 1)
          : value;
      return unquoted;
    }
  }
}
