/// How much of a command's output was dropped to stay under the size cap.
class OutputTruncation {
  final int originalBytes;
  final int keptBytes;

  const OutputTruncation({
    required this.originalBytes,
    required this.keptBytes,
  });

  Map<String, Object?> toJson() => {
    'originalBytes': originalBytes,
    'keptBytes': keptBytes,
  };
}

/// The result of running one command over a persistent shell session.
class ShellCommandResult {
  final String stdout;
  final String stderr;
  final int exitCode;

  /// Working directory after the command ran, read from the sentinel line.
  ///
  /// Returned on every call so the agent always knows where it is; this alone
  /// removes a large class of hallucinated paths.
  final String cwd;

  final int durationMs;

  /// Set when output exceeded the cap and the middle was dropped.
  final OutputTruncation? truncated;

  /// Number of secrets masked in [stdout] and [stderr] combined.
  ///
  /// Reported even when zero-valued fields are omitted elsewhere: an agent
  /// that does not know something was hidden will reason from incomplete data.
  final int redactedCount;

  /// The command did not finish on its own and was interrupted with Ctrl-C.
  final bool interrupted;

  /// The shell channel could not be recovered and was reopened, so any shell
  /// state the agent had built up (variables, `cd`, background jobs) is gone.
  final bool sessionReset;

  /// The command was still running when its timeout ran out.
  final bool timedOut;

  /// The output was not valid UTF-8, so [stdout]/[stderr] hold U+FFFD where
  /// those bytes were.
  final bool binary;

  const ShellCommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.cwd,
    required this.durationMs,
    this.truncated,
    this.redactedCount = 0,
    this.interrupted = false,
    this.sessionReset = false,
    this.timedOut = false,
    this.binary = false,
  });

  Map<String, Object?> toJson() => {
    'stdout': stdout,
    'stderr': stderr,
    'exitCode': exitCode,
    'cwd': cwd,
    'durationMs': durationMs,
    if (truncated != null) 'truncated': truncated!.toJson(),
    if (redactedCount > 0) 'redacted': {'count': redactedCount},
    if (interrupted) 'interrupted': true,
    if (sessionReset) 'sessionReset': true,
    if (timedOut) 'timedOut': true,
    if (binary) 'binary': true,
  };
}
