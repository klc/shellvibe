import '../../../hosts/domain/models/host_model.dart';
import '../models/runbook_model.dart';
import '../models/runbook_step_model.dart';
import '../models/snippet_model.dart';
import '../models/variable_declaration.dart';
import 'snippet_variable_parser.dart';

/// Everything a run has to ask for: the `${INPUT:...}` names, and how to ask.
class RunVariables {
  /// In first-use order, without repeats.
  final List<String> names;

  /// One per name: the runbook's own declaration, else the snippet's, else
  /// plain required text.
  final List<VariableDeclaration> declarations;

  const RunVariables(this.names, this.declarations);

  bool get isEmpty => names.isEmpty;
}

/// The variables [runbook] needs at run time.
///
/// A snippet step contributes the placeholders in the snippet's *current*
/// code, since that is what will run, and the snippet's declarations for them
/// unless the runbook declares the same name itself.
RunVariables collectRunVariables(
  RunbookModel runbook, {
  Map<String, SnippetModel> snippets = const {},
}) {
  final ordered = [...runbook.steps]
    ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
  final names = <String>{};
  final fromSnippets = <String, VariableDeclaration>{};
  for (final step in ordered) {
    switch (step.kind) {
      case StepKind.command:
        names.addAll(SnippetVariableParser.extractVariables(step.command));
      case StepKind.snippet:
        final snippet = snippets[step.snippetId];
        if (snippet == null) break;
        names.addAll(SnippetVariableParser.extractVariables(snippet.code));
        for (final v in snippet.variables) {
          fromSnippets[v.name] = v;
        }
      case StepKind.approval:
        break;
    }
  }
  final own = {for (final v in runbook.variables) v.name: v};
  return RunVariables(names.toList(), [
    for (final name in names)
      own[name] ?? fromSnippets[name] ?? VariableDeclaration(name: name),
  ]);
}

/// The values to hide: those entered for variables declared secret.
Set<String> secretValuesOf(
  Iterable<VariableDeclaration> declarations,
  Map<String, String> values,
) {
  return {
    for (final d in declarations)
      if (d.type == VariableType.secret && (values[d.name] ?? '').isNotEmpty)
        values[d.name]!,
  };
}

/// What `${SV:...}` stands for on [host]: the machine's own details, so one
/// snippet can say `ssh ${SV:USER}@${SV:HOST}` and mean a different thing on
/// each host it runs on. Never prompted for.
Map<String, String> builtinValuesFor(HostModel host) {
  var hostname = host.hostname.trim();
  String? embeddedUser;
  final at = hostname.indexOf('@');
  if (at >= 0) {
    embeddedUser = hostname.substring(0, at).trim();
    hostname = hostname.substring(at + 1).trim();
  }
  final user = (host.username?.trim().isNotEmpty ?? false)
      ? host.username!.trim()
      : (embeddedUser ?? '');
  return {
    'HOST': hostname,
    'HOST_LABEL': host.label,
    'USER': user,
    'PORT': '${host.port}',
  };
}
