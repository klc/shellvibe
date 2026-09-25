/// Validation shared between [VaultEnvRepository] and the add/edit form, so
/// the two cannot drift apart and let the repository reject something the
/// form just accepted (or the other way round).
library;

/// Names ShellVibe sets on every local shell itself. A stored environment
/// variable can never take one of these names: the automatic value always
/// wins (see `TerminalTabsNotifier._localShellEnvironment`), so accepting the
/// name here would let someone save an override that can never take effect.
const Set<String> kReservedVaultEnvVarNames = {
  'TERM',
  'COLORTERM',
  'TERM_THEME',
};

/// Shape a stored variable's name must have to be a valid shell identifier: a
/// letter or underscore, then any number of letters, digits or underscores.
final RegExp vaultEnvVarNameRegex = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
