import '../models/mcp_enums.dart';
import '../models/mcp_models.dart';

/// Classifies a raw shell command into a [RiskCategory].
///
/// **This classifier is a UX aid, not a security boundary.** It exists so an
/// agent (or the approval dialog, or the audit log) gets a plain-language
/// read on what a command is about to do — nothing more. It parses text with
/// regular expressions, not a real shell grammar, so it is trivially evaded
/// by anyone who wants to evade it. Known evasions we accept and do not try
/// to fully close:
///
/// ```sh
/// echo cm0gLXJmIC8= | base64 -d | sh   # base64-encoded `rm -rf /`
/// a=r; b=m; $a$b -rf /                  # command built from variable pieces
/// python3 -c "import os; os.system(...)"  # shell text hidden inside a string
/// ```
///
/// The first and third lines are caught by the checks below (they land on
/// [RiskCategory.opaqueExec]); variable splitting is not caught at all — there
/// is no literal pattern left to match once the command is built one
/// character at a time at runtime. Catching two out of three is not a
/// reason to call this "coverage": a determined evasion only has to find the
/// gap once. Do not market this class as protection. The three real security
/// boundaries are, and remain:
///
/// 1. Human approval before a risky command runs.
/// 2. Server-side restriction — a least-privilege agent SSH user and a
///    narrow `sudoers` file on the host.
/// 3. The audit log plus a kill switch to cut access when something looks
///    wrong.
///
/// This class only ever makes those three boundaries easier to use well, by
/// putting a readable label and (for [RiskCategory.interactive]) a working
/// alternative in front of the human or the agent before they need it.
class CommandClassifier {
  const CommandClassifier();

  CommandClassification classify(String command, {String cwd = '/'}) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) {
      return const CommandClassification(
        RiskCategory.unclassified,
        reason: 'empty command',
      );
    }

    // opaqueExec is checked on the whole, unsplit command: the thing that
    // makes it opaque — a pipe landing on a shell interpreter, an `eval`,
    // a `python -c` string — is a relationship between tokens the
    // segment-by-segment pass below would otherwise tear apart. It outranks
    // every other category once found.
    final opaqueReason = _matchOpaqueExec(trimmed);
    if (opaqueReason != null) {
      return CommandClassification(
        RiskCategory.opaqueExec,
        reason: opaqueReason,
      );
    }

    final segments = _splitSegments(trimmed);
    _SegmentResult? best;
    var bestSeverity = -1;
    for (final rawSegment in segments) {
      final segment = rawSegment.trim();
      if (segment.isEmpty) continue;
      final result = _classifySegment(segment);
      final severity = _severity(result.category);
      // Strictly greater so that, on a tie, the earliest segment in the
      // command wins and its reason is the one surfaced.
      if (severity > bestSeverity) {
        bestSeverity = severity;
        best = result;
      }
    }

    best ??= const _SegmentResult(
      RiskCategory.unclassified,
      reason: 'no runnable segment found',
    );

    if (best.category == RiskCategory.readonlySafe) {
      return const CommandClassification(RiskCategory.readonlySafe);
    }
    return CommandClassification(
      best.category,
      reason: best.reason,
      batchAlternative: best.batchAlternative,
    );
  }

  // ---------------------------------------------------------------------
  // Severity ranking used to pick the worst segment of a compound command.
  // ---------------------------------------------------------------------

  /// Higher wins. `readonlySafe` is the floor; `opaqueExec` is the ceiling
  /// (and is actually never reached here, since it is decided before the
  /// command is split — kept for completeness and so the ranking reads as a
  /// total order on its own).
  ///
  /// `interactive` ranks above the state-mutating categories because it is
  /// refused unconditionally in every access mode (see the plan's decision
  /// matrix), which makes it the more restrictive outcome regardless of what
  /// else is on the command line. `secretRead` ranks above the mutating
  /// categories and below `interactive` because exposing credentials can
  /// still be partially mitigated by masking, where an interactive command
  /// simply cannot run at all here.
  int _severity(RiskCategory category) => switch (category) {
    RiskCategory.readonlySafe => 0,
    RiskCategory.unclassified => 1,
    RiskCategory.destructiveFs ||
    RiskCategory.privilege ||
    RiskCategory.serviceControl ||
    RiskCategory.package ||
    RiskCategory.identityPerm ||
    RiskCategory.networkFw ||
    RiskCategory.database ||
    RiskCategory.vcs ||
    RiskCategory.container => 2,
    RiskCategory.secretRead => 3,
    RiskCategory.interactive => 4,
    RiskCategory.opaqueExec => 5,
  };

  // ---------------------------------------------------------------------
  // Splitting
  // ---------------------------------------------------------------------

  /// Shell operators that chain independent commands: `;`, `&&`, `||`, `|`,
  /// and newline. `||` is listed before the bare `|` alternative so the
  /// regex engine prefers the longer match at each position.
  static final RegExp _operatorSplit = RegExp(r'\|\||&&|;|\||\r?\n');

  List<String> _splitSegments(String command) => command.split(_operatorSplit);

  // ---------------------------------------------------------------------
  // opaqueExec — checked against the whole command, before splitting.
  // ---------------------------------------------------------------------

  /// A pipeline that hands its output to a shell interpreter for execution,
  /// e.g. `curl … | sh`, `wget … | bash`, `base64 -d | sh`.
  static final RegExp _pipeIntoShell = RegExp(
    r'\|\s*(?:sudo\s+)?(?:sh|bash|zsh|dash|ksh)\b',
    caseSensitive: false,
  );

  /// `sh -c '…'` / `bash -c "…"` etc. used directly, at the start of the
  /// command or right after a shell operator.
  static final RegExp _shellDashC = RegExp(
    r'(?:^|[;&|]|\n)\s*(?:sh|bash|zsh|dash|ksh)\s+(?:-\S+\s+)*-c\b',
    caseSensitive: false,
  );

  /// `eval …` — runs a string the classifier cannot see into.
  static final RegExp _evalUsage = RegExp(r'\beval\b', caseSensitive: false);

  /// `source <(…)` / `. <(…)` — sources a process-substitution stream.
  static final RegExp _sourceProcessSubstitution = RegExp(
    r'\b(?:source|\.)\s+<\(',
    caseSensitive: false,
  );

  /// `python[3] -c "…os.system(...)…"` or `…subprocess…` — shell text
  /// embedded in an interpreter's `-c` string. The scan between `-c` and the
  /// call deliberately does not stop at `;` or `&`: those are legal, common
  /// characters *inside* the quoted Python string itself (e.g. `import os;
  /// os.system(...)`), so excluding them would make the check miss the
  /// plan's own example.
  static final RegExp _pythonInlineShellOut = RegExp(
    r'\bpython3?\b[^\n]*-c\b[^\n]*(?:os\.system|subprocess\.)',
    caseSensitive: false,
  );

  String? _matchOpaqueExec(String command) {
    if (_pipeIntoShell.hasMatch(command)) {
      return 'pipes its output into a shell interpreter, so the classifier '
          'cannot see what actually runs';
    }
    if (_shellDashC.hasMatch(command)) {
      return 'runs an opaque string via `sh -c` / `bash -c`, hiding the '
          'real command from the classifier';
    }
    if (_evalUsage.hasMatch(command)) {
      return '`eval` executes an opaque string the classifier cannot read';
    }
    if (_sourceProcessSubstitution.hasMatch(command)) {
      return 'sources a process-substitution stream, whose contents the '
          'classifier cannot see';
    }
    if (_pythonInlineShellOut.hasMatch(command)) {
      return 'runs shell commands from inside a Python `-c` string via '
          '`os.system`/`subprocess`, hiding them from the classifier';
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Per-segment classification.
  //
  // Order matters: each check below either returns a result or null (no
  // match, try the next check). Risky, flag-specific patterns are checked
  // before the readonlySafe whitelist, so e.g. `sed -i` is caught as
  // destructiveFs before bare `sed` ever reaches the readonlySafe fallback.
  // Anything that falls through every check is `unclassified`.
  // ---------------------------------------------------------------------

  _SegmentResult _classifySegment(String segment) {
    return _checkPrivilege(segment) ??
        _checkSecretRead(segment) ??
        _checkInteractive(segment) ??
        _checkDestructiveFs(segment) ??
        _checkServiceControl(segment) ??
        _checkPackage(segment) ??
        _checkIdentityPerm(segment) ??
        _checkNetworkFw(segment) ??
        _checkDatabase(segment) ??
        _checkVcs(segment) ??
        _checkContainer(segment) ??
        _checkReadonlySafe(segment) ??
        const _SegmentResult(
          RiskCategory.unclassified,
          reason:
              'command not recognized by any known pattern; treated as '
              'risky by default',
        );
  }

  // -- privilege ----------------------------------------------------------

  static final RegExp _privilegeLead = RegExp(
    r'^\s*(?:sudo|su|doas)\b',
    caseSensitive: false,
  );
  static final RegExp _chmodSetuid = RegExp(
    r'\bchmod\b.*(?:u\+s\b|\+s\b)',
    caseSensitive: false,
  );

  _SegmentResult? _checkPrivilege(String s) {
    if (_privilegeLead.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.privilege,
        reason:
            'runs as another user with elevated privileges (`sudo`/`su`/`doas`)',
      );
    }
    if (_chmodSetuid.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.privilege,
        reason: 'sets the setuid bit, letting the file run as its owner',
      );
    }
    return null;
  }

  // -- secretRead -----------------------------------------------------------

  static final RegExp _secretReadCommand = RegExp(
    r'^\s*(?:cat|less|more|head|tail|vim|vi|nvim|nano|grep|egrep|fgrep|'
    r'strings|xxd|od|hexdump|cp|scp)\b',
    caseSensitive: false,
  );
  static final RegExp _credentialPath = RegExp(
    r'\.ssh/id_(?:rsa|dsa|ecdsa|ed25519)(?:\.pub)?\b'
    r'|\.env(?:\.[\w.-]+)?\b'
    r'|/etc/shadow\b'
    r'|/etc/gshadow\b'
    r'|\.pem\b'
    r'|\.key\b'
    r'|credentials\b'
    r'|\.aws/credentials\b'
    r'|\.netrc\b'
    r'|\.pgpass\b'
    r'|\.git-credentials\b',
    caseSensitive: false,
  );
  static final RegExp _bareEnvDump = RegExp(
    r'^\s*(?:env|printenv)(?:\s+-0)?\s*$',
    caseSensitive: false,
  );

  _SegmentResult? _checkSecretRead(String s) {
    if (_secretReadCommand.hasMatch(s) && _credentialPath.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.secretRead,
        reason: 'reads a path that typically holds credential material',
      );
    }
    if (_bareEnvDump.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.secretRead,
        reason:
            'dumps the full process environment, which often carries secrets',
      );
    }
    return null;
  }

  // -- interactive ----------------------------------------------------------

  static final RegExp _interactiveEditor = RegExp(
    r'^\s*(?:vim|vi|nvim|nano|emacs)\b',
    caseSensitive: false,
  );
  static final RegExp _lessMore = RegExp(
    r'^\s*(?:less|more)\b',
    caseSensitive: false,
  );
  static final RegExp _htopLead = RegExp(r'^\s*htop\b', caseSensitive: false);
  static final RegExp _topLead = RegExp(r'^\s*top\b', caseSensitive: false);
  static final RegExp _batchFlag = RegExp(r'-b\b', caseSensitive: false);
  static final RegExp _tailLead = RegExp(r'^\s*tail\b', caseSensitive: false);
  static final RegExp _followFlag = RegExp(
    r'-f\b|--follow\b',
    caseSensitive: false,
  );
  static final RegExp _mysqlLead = RegExp(r'^\s*mysql\b', caseSensitive: false);
  static final RegExp _mysqlExecuteFlag = RegExp(
    r'-e\b|--execute\b',
    caseSensitive: false,
  );
  static final RegExp _psqlLead = RegExp(r'^\s*psql\b', caseSensitive: false);
  static final RegExp _psqlCommandFlag = RegExp(
    r'-c\b|--command\b',
    caseSensitive: false,
  );
  static final RegExp _tmuxLead = RegExp(r'^\s*tmux\b', caseSensitive: false);
  static final RegExp _sshBare = RegExp(
    r'^\s*ssh\b(?:\s+-{1,2}\S+)*\s+\S+\s*$',
    caseSensitive: false,
  );

  _SegmentResult? _checkInteractive(String s) {
    if (_interactiveEditor.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.interactive,
        reason: 'opens an interactive terminal editor and blocks the session',
        batchAlternative:
            'use the sftp_read / sftp_write tools instead of an '
            'interactive editor',
      );
    }
    if (_lessMore.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.interactive,
        reason: 'is an interactive pager and blocks the session',
        batchAlternative: 'cat',
      );
    }
    if (_htopLead.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.interactive,
        reason: 'has no batch mode and blocks the session',
        batchAlternative: 'top -b -n1',
      );
    }
    if (_topLead.hasMatch(s) && !_batchFlag.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.interactive,
        reason: 'runs interactively and blocks the session without `-b`',
        batchAlternative: 'top -b -n1',
      );
    }
    if (_tailLead.hasMatch(s) && _followFlag.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.interactive,
        reason: 'follows forever with `-f` and blocks the session',
        batchAlternative: 'tail -n 200',
      );
    }
    if (_mysqlLead.hasMatch(s) && !_mysqlExecuteFlag.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.interactive,
        reason: 'drops into an interactive prompt with no `-e`',
        batchAlternative: 'mysql -e "…"',
      );
    }
    if (_psqlLead.hasMatch(s) && !_psqlCommandFlag.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.interactive,
        reason: 'drops into an interactive prompt with no `-c`',
        batchAlternative: 'psql -c "…"',
      );
    }
    if (_tmuxLead.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.interactive,
        reason:
            'multiplexes an interactive terminal and blocks the session. '
            'tmux exists to hold an interactive terminal open, so it has no '
            'batch form: run the underlying command directly instead of '
            'inside a multiplexer',
      );
    }
    if (_sshBare.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.interactive,
        reason:
            'with no remote command opens a second interactive session '
            'inside this one, which has no batch form: run the command '
            'directly on the target host through its own session instead of '
            'nesting ssh',
      );
    }
    return null;
  }

  // -- destructiveFs --------------------------------------------------------

  static final RegExp _rmLead = RegExp(r'^\s*rm\b', caseSensitive: false);
  static final RegExp _shredLead = RegExp(r'^\s*shred\b', caseSensitive: false);
  static final RegExp _mkfsLead = RegExp(
    r'^\s*mkfs(?:\.\w+)?\b',
    caseSensitive: false,
  );
  static final RegExp _ddToDevice = RegExp(
    r'\bdd\b.*\bof=/dev/',
    caseSensitive: false,
  );
  static final RegExp _redirectToDevice = RegExp(
    r'>\s*/dev/(?:sd|nvme|hd)\w*',
    caseSensitive: false,
  );
  static final RegExp _truncateToZero = RegExp(
    r'\btruncate\b.*(?:-s\s*0\b|--size[= ]0\b)',
    caseSensitive: false,
  );
  static final RegExp _findDelete = RegExp(
    r'\bfind\b.*-delete\b',
    caseSensitive: false,
  );
  static final RegExp _findExecRm = RegExp(
    r'\bfind\b.*-exec\b.*\brm\b',
    caseSensitive: false,
  );
  static final RegExp _sedInPlace = RegExp(
    r'\bsed\b.*(?:-i\b|--in-place\b)',
    caseSensitive: false,
  );
  static final RegExp _journalctlVacuum = RegExp(
    r'\bjournalctl\b.*--vacuum',
    caseSensitive: false,
  );

  _SegmentResult? _checkDestructiveFs(String s) {
    if (_rmLead.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.destructiveFs,
        reason: 'deletes files (`rm`)',
      );
    }
    if (_shredLead.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.destructiveFs,
        reason: 'overwrites and deletes a file beyond recovery (`shred`)',
      );
    }
    if (_mkfsLead.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.destructiveFs,
        reason: 'formats a filesystem, destroying everything on it (`mkfs`)',
      );
    }
    if (_ddToDevice.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.destructiveFs,
        reason: 'writes raw data straight to a block device (`dd of=/dev/…`)',
      );
    }
    if (_redirectToDevice.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.destructiveFs,
        reason: 'redirects output straight onto a block device',
      );
    }
    if (_truncateToZero.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.destructiveFs,
        reason: 'truncates a file to zero bytes, discarding its contents',
      );
    }
    if (_findDelete.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.destructiveFs,
        reason: '`find … -delete` removes every file it matches',
      );
    }
    if (_findExecRm.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.destructiveFs,
        reason: '`find … -exec rm` removes every file it matches',
      );
    }
    if (_sedInPlace.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.destructiveFs,
        reason: '`sed -i` overwrites the file in place',
      );
    }
    if (_journalctlVacuum.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.destructiveFs,
        reason: '`journalctl --vacuum…` permanently deletes stored logs',
      );
    }
    return null;
  }

  // -- serviceControl ---------------------------------------------------

  static final RegExp _systemctlMutate = RegExp(
    r'\bsystemctl\b.*\b(?:stop|restart|disable|mask)\b',
    caseSensitive: false,
  );
  static final RegExp _serviceMutate = RegExp(
    r'^\s*service\b.*\b(?:stop|restart)\b',
    caseSensitive: false,
  );
  static final RegExp _powerLead = RegExp(
    r'^\s*(?:reboot|shutdown|halt)\b',
    caseSensitive: false,
  );
  static final RegExp _initZero = RegExp(
    r'^\s*init\s+0\b',
    caseSensitive: false,
  );

  _SegmentResult? _checkServiceControl(String s) {
    if (_systemctlMutate.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.serviceControl,
        reason: 'stops, restarts, disables or masks a system service',
      );
    }
    if (_serviceMutate.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.serviceControl,
        reason: 'stops or restarts a system service',
      );
    }
    if (_powerLead.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.serviceControl,
        reason: 'reboots, shuts down or halts the machine',
      );
    }
    if (_initZero.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.serviceControl,
        reason: '`init 0` halts the machine',
      );
    }
    return null;
  }

  // -- package --------------------------------------------------------------

  static final RegExp _pkgManagerMutate = RegExp(
    r'\b(?:apt|apt-get|yum|dnf|apk|pacman)\b.*\b(?:install|remove|purge)\b',
    caseSensitive: false,
  );
  static final RegExp _pipInstall = RegExp(
    r'\bpip3?\b.*\binstall\b',
    caseSensitive: false,
  );
  static final RegExp _npmGlobalInstall = RegExp(
    r'\bnpm\b.*\b(?:i|install)\b.*(?:-g\b|--global\b)',
    caseSensitive: false,
  );

  _SegmentResult? _checkPackage(String s) {
    if (_pkgManagerMutate.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.package,
        reason: 'installs or removes a system package',
      );
    }
    if (_pipInstall.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.package,
        reason: 'installs a Python package (`pip install`)',
      );
    }
    if (_npmGlobalInstall.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.package,
        reason: 'installs an npm package globally',
      );
    }
    return null;
  }

  // -- identityPerm -----------------------------------------------------

  static final RegExp _identityLead = RegExp(
    r'^\s*(?:useradd|userdel|usermod|passwd|visudo)\b',
    caseSensitive: false,
  );
  static final RegExp _chownLead = RegExp(r'^\s*chown\b', caseSensitive: false);
  static final RegExp _chmod777 = RegExp(
    r'\bchmod\b.*\b777\b',
    caseSensitive: false,
  );

  _SegmentResult? _checkIdentityPerm(String s) {
    if (_identityLead.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.identityPerm,
        reason: 'changes a user account or sudo configuration',
      );
    }
    if (_chownLead.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.identityPerm,
        reason: 'changes file ownership',
      );
    }
    if (_chmod777.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.identityPerm,
        reason: '`chmod 777` opens a file or directory to everyone',
      );
    }
    return null;
  }

  // -- networkFw --------------------------------------------------------

  static final RegExp _iptablesFlush = RegExp(r'\biptables\b.*-F\b');
  static final RegExp _nftFlush = RegExp(
    r'\bnft\b.*\bflush\b',
    caseSensitive: false,
  );
  static final RegExp _ufwDisable = RegExp(
    r'\bufw\b.*\bdisable\b',
    caseSensitive: false,
  );
  static final RegExp _firewalldRemove = RegExp(
    r'\bfirewall-cmd\b.*--remove',
    caseSensitive: false,
  );

  _SegmentResult? _checkNetworkFw(String s) {
    if (_iptablesFlush.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.networkFw,
        reason: '`iptables -F` flushes every firewall rule',
      );
    }
    if (_nftFlush.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.networkFw,
        reason: '`nft flush` clears the nftables ruleset',
      );
    }
    if (_ufwDisable.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.networkFw,
        reason: '`ufw disable` turns the firewall off',
      );
    }
    if (_firewalldRemove.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.networkFw,
        reason: 'removes a firewalld rule',
      );
    }
    return null;
  }

  // -- database -----------------------------------------------------------

  static final RegExp _sqlDrop = RegExp(
    r'\bDROP\s+(?:TABLE|DATABASE|SCHEMA|INDEX|VIEW)\b',
    caseSensitive: false,
  );
  static final RegExp _sqlTruncate = RegExp(
    r'\bTRUNCATE\b',
    caseSensitive: false,
  );
  static final RegExp _sqlDeleteFrom = RegExp(
    r'\bDELETE\s+FROM\b',
    caseSensitive: false,
  );
  static final RegExp _sqlWhere = RegExp(r'\bWHERE\b', caseSensitive: false);
  static final RegExp _mysqlExecute = RegExp(
    r'^\s*mysql\b.*(?:-e\b|--execute\b)',
    caseSensitive: false,
  );
  static final RegExp _psqlCommand = RegExp(
    r'^\s*psql\b.*(?:-c\b|--command\b)',
    caseSensitive: false,
  );

  _SegmentResult? _checkDatabase(String s) {
    if (_sqlDrop.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.database,
        reason: 'SQL `DROP` permanently removes a table, database or index',
      );
    }
    if (_sqlTruncate.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.database,
        reason: 'SQL `TRUNCATE` empties a table with no way back',
      );
    }
    if (_sqlDeleteFrom.hasMatch(s) && !_sqlWhere.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.database,
        reason: 'SQL `DELETE` with no `WHERE` clause removes every row',
      );
    }
    if (_mysqlExecute.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.database,
        reason: 'runs a non-interactive SQL statement via `mysql -e`',
      );
    }
    if (_psqlCommand.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.database,
        reason: 'runs a non-interactive SQL statement via `psql -c`',
      );
    }
    return null;
  }

  // -- vcs ------------------------------------------------------------------

  static final RegExp _gitForcePush = RegExp(
    r'\bgit\b.*\bpush\b.*(?:--force\b|-f\b)',
    caseSensitive: false,
  );
  static final RegExp _gitResetHard = RegExp(
    r'\bgit\b.*\breset\b.*--hard\b',
    caseSensitive: false,
  );
  static final RegExp _gitCleanForce = RegExp(
    r'\bgit\b.*\bclean\b.*-f',
    caseSensitive: false,
  );

  _SegmentResult? _checkVcs(String s) {
    if (_gitForcePush.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.vcs,
        reason: '`git push --force` overwrites remote history',
      );
    }
    if (_gitResetHard.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.vcs,
        reason: '`git reset --hard` discards uncommitted work',
      );
    }
    if (_gitCleanForce.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.vcs,
        reason: '`git clean -f` deletes untracked files',
      );
    }
    return null;
  }

  // -- container --------------------------------------------------------

  static final RegExp _dockerRemove = RegExp(
    r'\bdocker\b.*\b(?:rm|rmi)\b',
    caseSensitive: false,
  );
  static final RegExp _dockerSystemPrune = RegExp(
    r'\bdocker\b.*\bsystem\b.*\bprune\b',
    caseSensitive: false,
  );
  static final RegExp _dockerComposeDownVolumes = RegExp(
    r'\bdocker\b.*\bcompose\b.*\bdown\b.*(?:-v\b|--volumes\b)',
    caseSensitive: false,
  );
  static final RegExp _dockerResourcePrune = RegExp(
    r'\bdocker\b.*\b(?:network|volume|image)\b.*\bprune\b',
    caseSensitive: false,
  );
  static final RegExp _kubectlDelete = RegExp(
    r'\bkubectl\b.*\bdelete\b',
    caseSensitive: false,
  );

  _SegmentResult? _checkContainer(String s) {
    if (_dockerRemove.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.container,
        reason: 'removes a container or image (`docker rm`/`rmi`)',
      );
    }
    if (_dockerSystemPrune.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.container,
        reason:
            '`docker system prune` removes unused containers, images and networks',
      );
    }
    if (_dockerComposeDownVolumes.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.container,
        reason: '`docker compose down -v` also deletes named volumes',
      );
    }
    if (_dockerResourcePrune.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.container,
        reason: 'prunes docker networks, volumes or images',
      );
    }
    if (_kubectlDelete.hasMatch(s)) {
      return const _SegmentResult(
        RiskCategory.container,
        reason: '`kubectl delete` removes a cluster object',
      );
    }
    return null;
  }

  // -- readonlySafe -----------------------------------------------------

  static final RegExp _readonlyLead = RegExp(
    r'^\s*(?:ls|cat|head|grep|egrep|fgrep|du|df|ps|free|uptime|uname|id|stat|'
    r'wc|pwd|whoami|hostname|date|echo|printf|which|type)\b',
    caseSensitive: false,
  );
  static final RegExp _systemctlStatus = RegExp(
    r'\bsystemctl\b.*\bstatus\b',
    caseSensitive: false,
  );
  static final RegExp _journalctlLead = RegExp(
    r'^\s*journalctl\b',
    caseSensitive: false,
  );
  static final RegExp _dockerReadonly = RegExp(
    r'\bdocker\b.*\b(?:ps|logs|inspect)\b',
    caseSensitive: false,
  );
  static final RegExp _kubectlReadonly = RegExp(
    r'\bkubectl\b.*\b(?:get|describe|logs)\b',
    caseSensitive: false,
  );
  static final RegExp _gitReadonly = RegExp(
    r'\bgit\b.*\b(?:status|log|diff)\b',
    caseSensitive: false,
  );
  static final RegExp _findLead = RegExp(r'^\s*find\b', caseSensitive: false);
  static final RegExp _sedLead = RegExp(r'^\s*sed\b', caseSensitive: false);

  _SegmentResult? _checkReadonlySafe(String s) {
    // `_topLead`/`_tailLead` batch/non-follow forms fall through to here only
    // because `_checkInteractive` already rejected the interactive forms —
    // by the time we reach this check, a bare `top` or `tail -f` is gone.
    if (_readonlyLead.hasMatch(s) ||
        _systemctlStatus.hasMatch(s) ||
        _journalctlLead.hasMatch(s) ||
        _dockerReadonly.hasMatch(s) ||
        _kubectlReadonly.hasMatch(s) ||
        _gitReadonly.hasMatch(s) ||
        _findLead.hasMatch(s) ||
        _sedLead.hasMatch(s) ||
        (_topLead.hasMatch(s) && _batchFlag.hasMatch(s)) ||
        _tailLead.hasMatch(s)) {
      return const _SegmentResult(RiskCategory.readonlySafe);
    }
    return null;
  }
}

/// One command segment's outcome, before it is compared against the other
/// segments of a compound command.
class _SegmentResult {
  final RiskCategory category;
  final String? reason;
  final String? batchAlternative;

  const _SegmentResult(this.category, {this.reason, this.batchAlternative});
}
