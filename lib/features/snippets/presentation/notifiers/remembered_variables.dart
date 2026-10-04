import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'remembered_variables.g.dart';

/// The last non-secret values typed into a variable prompt, by what was run
/// (`runbook:<id>`, `snippet:<id>`) and then by variable name, so the next run
/// of the same thing starts from them.
///
/// Memory only, for this session: nothing here is ever written to disk, and a
/// secret is never put in at all (the dialog does not pass secrets in, and
/// [remember] would not know to tell them apart, so the caller filters).
@Riverpod(keepAlive: true)
class RememberedVariables extends _$RememberedVariables {
  @override
  Map<String, Map<String, String>> build() => const {};

  /// Replaces what is remembered for [key] with [values].
  void remember(String key, Map<String, String> values) {
    state = {...state, key: Map.unmodifiable(values)};
  }
}
