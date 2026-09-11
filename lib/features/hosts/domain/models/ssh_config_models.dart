/// Models for parsing and importing OpenSSH `~/.ssh/config` files.
library;

/// Severity of a problem found while parsing, resolving or importing an
/// SSH config file.
enum SshConfigWarningSeverity { info, warning, error }

/// A non-fatal problem found during parse/resolve/import.
///
/// Kept as data rather than exceptions so the import preview can render the
/// full list before the user commits to an import.
class SshConfigWarning {
  final String? source;
  final int? line;
  final String message;
  final SshConfigWarningSeverity severity;

  const SshConfigWarning({
    this.source,
    this.line,
    required this.message,
    this.severity = SshConfigWarningSeverity.warning,
  });

  /// Human-readable location, e.g. `config:12` or `line 12`.
  String get location {
    if (source == null && line == null) return '';
    if (source == null) return 'line $line';
    if (line == null) return source!;
    return '$source:$line';
  }
}

/// One parsed `keyword value…` pair from an ssh config file.
class SshConfigDirective {
  final String keyword;

  /// Original arguments, quoted strings and escapes already resolved.
  final List<String> args;
  final String? source;
  final int line;

  const SshConfigDirective({
    required this.keyword,
    required this.args,
    this.source,
    required this.line,
  });

  @override
  String toString() => '$keyword ${args.join(' ')} ($source:$line)';
}

/// Fully parsed, Include-expanded configuration document.
class SshConfigDocument {
  final List<SshConfigDirective> directives;
  final List<SshConfigWarning> warnings;

  const SshConfigDocument({required this.directives, this.warnings = const []});
}

/// A TCP port forwarding parsed from `LocalForward`/`RemoteForward`/
/// `DynamicForward`.
class SshForwardDraft {
  /// 'local', 'remote' or 'dynamic' — mirrors `PortForwardRules.type`.
  final String type;
  final int localPort;
  final String? remoteHost;
  final int? remotePort;

  /// Original bind address, or null when the config did not specify one.
  /// ShellVibe's tunnel model has no bind-address field, so this is only kept for
  /// the import warnings.
  final String? bindAddress;
  final int line;

  const SshForwardDraft({
    required this.type,
    required this.localPort,
    this.remoteHost,
    this.remotePort,
    this.bindAddress,
    required this.line,
  });
}

/// First hop of a `ProxyJump` chain (`[user@]host[:port]`).
class SshJumpHostDraft {
  final String? username;
  final String host;
  final int? port;

  const SshJumpHostDraft({this.username, required this.host, this.port});
}

/// Effective configuration resolved for one concrete `Host <alias>` entry.
class ResolvedSshConfig {
  final String alias;
  final String hostname;
  final String? username;
  final int port;

  /// Token/`~`/env-expanded `IdentityFile` paths, in config order.
  final List<String> identityFiles;
  final SshJumpHostDraft? jumpHost;

  /// True when [jumpHost] was approximated from a `ProxyCommand ssh -W …`
  /// form instead of a real `ProxyJump` directive.
  final bool jumpViaProxyCommand;
  final List<SshForwardDraft> forwards;
  final List<SshConfigWarning> warnings;

  const ResolvedSshConfig({
    required this.alias,
    required this.hostname,
    this.username,
    this.port = 22,
    this.identityFiles = const [],
    this.jumpHost,
    this.jumpViaProxyCommand = false,
    this.forwards = const [],
    this.warnings = const [],
  });
}

/// Outcome of resolving a whole config file: one entry per concrete alias.
class SshConfigResolution {
  final List<ResolvedSshConfig> hosts;
  final List<SshConfigWarning> warnings;

  const SshConfigResolution({required this.hosts, this.warnings = const []});
}
