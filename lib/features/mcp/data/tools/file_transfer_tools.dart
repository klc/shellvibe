import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../../core/mcp/mcp_protocol.dart';
import '../../../../shared/database/daos/hosts_dao.dart';
import '../../../sftp/data/sftp_service.dart';
import '../../domain/models/mcp_enums.dart';
import '../../domain/models/mcp_models.dart';
import '../../domain/services/approval_coordinator.dart';
import '../../domain/services/command_classifier.dart';
import '../../domain/services/mcp_session_mirror.dart';
import '../../domain/services/policy_engine.dart';
import '../mcp_session_pool.dart';
import '../repositories/mcp_audit_repository.dart';
import '../repositories/mcp_grant_repository.dart';
import 'mcp_tool_handler.dart';

/// `upload_file` and `download_file`: one regular file between this computer
/// and a session's host, so an agent has no reason to reach for `scp` around
/// ShellVibe's policy, approval and audit log.
///
/// The checks run in `run_command`'s order (session, live grant, visible
/// host, host max access), repeated here rather than shared. Then both ends
/// are resolved and stat'ed over a per-call SFTP channel, and
/// [PolicyEngine.evaluateTransfer] gets the facts. This process does the
/// local I/O itself: it runs as the same user on the same machine as the
/// agent, so a local path names the same file for both.
///
/// A destination is never left partial and never truncated on failure: a
/// download goes to a temp sibling renamed into place, an upload through
/// [openRemoteReplacement] and its commit/discard.
///
/// ponytail: one regular file per call, whole, with no resume and no progress
/// reporting; the agent tars a directory first. Add resume or progress
/// notifications if agents start moving files that outgrow the 600 s cap.
class FileTransferTool with McpArgReaders implements McpToolHandler {
  /// True for `upload_file`, false for `download_file`.
  final bool upload;
  final McpSessionPool sessionPool;
  final HostsDao hostsDao;
  final McpGrantRepository grantRepository;
  final McpAuditRepository auditRepository;
  final PolicyEngine policyEngine;
  final ApprovalCoordinator approvalCoordinator;

  const FileTransferTool.upload({
    required this.sessionPool,
    required this.hostsDao,
    required this.grantRepository,
    required this.auditRepository,
    required this.policyEngine,
    required this.approvalCoordinator,
  }) : upload = true;

  const FileTransferTool.download({
    required this.sessionPool,
    required this.hostsDao,
    required this.grantRepository,
    required this.auditRepository,
    required this.policyEngine,
    required this.approvalCoordinator,
  }) : upload = false;

  static const int _defaultTimeoutSeconds = 300;
  static const int _maxTimeoutSeconds = 600;

  /// How long any one remote cleanup step may take. A stalled link would
  /// otherwise hold the call, and the session's busy flag, forever.
  static const Duration _cleanupLimit = Duration(seconds: 10);

  static final RegExp _controlChar = RegExp(r'[\x00-\x1F\x7F-\x9F]');

  @override
  String get name => upload ? 'upload_file' : 'download_file';

  @override
  McpToolDefinition get definition => McpToolDefinition(
    name: name,
    description: upload
        ? 'Uploads one regular file from this computer to a remote server '
              'over SSH (SFTP), through an already-open session (see '
              'open_session). Use this instead of scp, sftp or rsync. To move '
              'a directory, tar it first. The transfer is checked against '
              'the host\'s access policy and may be denied (POLICY_DENIED) or '
              'pause while the user is asked to approve it. An existing remote '
              'file is never replaced unless overwrite is true '
              '(DESTINATION_EXISTS). Returns the resolved remote path, the '
              'byte count and the SHA-256 of what was sent.'
        : 'Downloads one regular file from a remote server to this computer '
              'over SSH (SFTP), through an already-open session (see '
              'open_session). Use this instead of scp, sftp or rsync. To fetch '
              'a directory, tar it on the server first. The transfer is '
              'checked against the host\'s access policy and may be denied '
              '(POLICY_DENIED) or pause while the user is asked to approve it. '
              'The file\'s bytes are not scanned for secrets. An existing local '
              'file is never replaced unless overwrite is true '
              '(DESTINATION_EXISTS); the local directory must already exist. '
              'Returns the resolved remote path, the byte count and the '
              'SHA-256 of what was received.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'sessionId': {
          'type': 'string',
          'description': 'The sessionId returned by open_session.',
        },
        'localPath': {
          'type': 'string',
          'description': upload
              ? 'Absolute path of the file on this computer to upload.'
              : 'Absolute path on this computer to write the file to.',
        },
        'remotePath': {
          'type': 'string',
          'description':
              'Path on the server: absolute, relative to the session\'s '
              'current directory, or starting with ~/ for the login user\'s '
              'home.',
        },
        'overwrite': {
          'type': 'boolean',
          'description': upload
              ? 'Replace the remote file if it exists. Defaults to false.'
              : 'Replace the local file if it exists. Defaults to false.',
        },
        'timeoutSeconds': {
          'type': 'integer',
          'minimum': 1,
          'maximum': _maxTimeoutSeconds,
          'description':
              'How long the transfer may take before it is aborted and any '
              'partial file removed. Defaults to $_defaultTimeoutSeconds; '
              'clamped to a maximum of $_maxTimeoutSeconds.',
        },
      },
      'required': ['sessionId', 'localPath', 'remotePath'],
      'additionalProperties': false,
    },
  );

  @override
  Future<Object?> execute(McpToolContext ctx, Map<String, Object?> args) async {
    final sessionId = requireString(args, 'sessionId');
    final localPath = _requirePath(args, 'localPath');
    final remoteArg = _requirePath(args, 'remotePath');
    if (!p.isAbsolute(localPath)) {
      throw McpToolException(
        McpErrorCode.internal,
        'Argument "localPath" must be an absolute path on this computer, got '
        '"$localPath".',
      );
    }
    final rawOverwrite = args['overwrite'];
    if (rawOverwrite != null && rawOverwrite is! bool) {
      throw McpToolException(
        McpErrorCode.internal,
        'Argument "overwrite" must be a boolean.',
      );
    }
    final overwrite = rawOverwrite == true;
    final timeoutSeconds =
        (optionalInt(args, 'timeoutSeconds') ?? _defaultTimeoutSeconds).clamp(
          1,
          _maxTimeoutSeconds,
        );
    final limit = Duration(seconds: timeoutSeconds);

    final session = sessionPool.requireOwned(
      ctx.clientId,
      ctx.connectionScopeId,
      sessionId,
    );

    // Set as the call learns what it is; read by the single audit at the end.
    var refusal = AuditDecision.error;
    RiskCategory? category;
    SftpClient? sftp;

    Future<void> audit(
      AuditDecision decision, {
      int? durationMs,
      int? bytes,
      String? sha256,
    }) => auditRepository.record(
      clientId: ctx.clientId,
      clientName: ctx.clientName,
      workspaceId: ctx.workspaceId,
      hostId: session.hostId,
      hostLabel: session.hostLabel,
      tool: name,
      args: {
        'sessionId': session.sessionId,
        'localPath': localPath,
        'remotePath': remoteArg,
        'overwrite': overwrite,
        'timeoutSeconds': timeoutSeconds,
      },
      decision: decision,
      category: category,
      durationMs: durationMs,
      outputBytes: bytes,
      outputSha256: sha256,
    );

    session.activeTransfers++;
    session.lastActivityAt = DateTime.now();
    try {
      // The attempt is shown as asked, before any check: what an agent tried
      // matters as much as what it got through.
      _mirror(session)?.writeCommand(
        session.tabId!,
        command: upload
            ? '$name $localPath → $remoteArg'
            : '$name $remoteArg → $localPath',
        cwd: session.shell.cwd,
      );

      // Re-checked per call, exactly as `run_command` does and for the same
      // reasons: a grant can lapse and a host's limits can change while a
      // session stays open.
      final granted = await grantRepository.effectiveMode(
        ctx.clientId,
        session.hostId,
        connectionScopeId: ctx.connectionScopeId,
      );
      if (granted == null) {
        refusal = AuditDecision.autoDenied;
        throw McpToolException(
          McpErrorCode.hostAccessRequired,
          'Access to host "${session.hostId}" is no longer granted. Call '
          'request_host_access again before transferring files.',
        );
      }
      final hostRow = await hostsDao.getHostById(session.hostId);
      if (hostRow != null && !hostRow.mcpVisible) {
        refusal = AuditDecision.autoDenied;
        throw McpToolException(
          McpErrorCode.hostNotVisible,
          'Host "${session.hostId}" has been hidden from agents.',
        );
      }
      final mode = granted.atMost(
        hostRow == null
            ? McpAccessMode.readonly
            : McpAccessMode.fromName(hostRow.mcpDefaultMode),
      );

      final client = sftp = await session.connection.target.openSftp().timeout(
        limit,
      );
      // Read-only lookups; left running past the limit they only cost a
      // channel the finally below closes.
      final plan = await _plan(
        client,
        session,
        localPath: localPath,
        remoteArg: remoteArg,
        overwrite: overwrite,
      ).timeout(limit);

      final decision = policyEngine.evaluateTransfer(
        upload: upload,
        replacesRemoteFile: upload && plan.replacesExisting,
        touchesCredentialPath: plan.touchesCredentialPath,
        mode: mode,
      );
      category = decision.category;

      var success = AuditDecision.allowed;
      switch (decision.action) {
        case PolicyAction.deny:
        case PolicyAction.rejectInteractive:
          refusal = AuditDecision.denied;
          throw McpToolException(
            McpErrorCode.policyDenied,
            decision.message ?? 'This file transfer was denied by policy.',
            details: {'category': decision.category.wireName},
          );
        case PolicyAction.confirm:
          // Never remembered, whatever the category: a transfer approval is
          // for these exact bytes, and nothing here keys a stored approval.
          final approval = await approvalCoordinator.requestCommandApproval(
            CommandApprovalRequest(
              clientId: ctx.clientId,
              clientName: ctx.clientName,
              hostId: session.hostId,
              hostLabel: session.hostLabel,
              command: upload
                  ? '$name ${plan.localPath} → ${plan.remotePath}'
                  : '$name ${plan.remotePath} → ${plan.localPath}',
              cwd: session.shell.cwd,
              category: decision.category,
              canRemember: false,
              transfer: FileTransferApproval(
                upload: upload,
                localPath: plan.localPath,
                remotePath: plan.remotePath,
                bytes: plan.bytes,
                replacesExisting: plan.replacesExisting,
              ),
            ),
          );
          if (!approval.approved) {
            refusal = AuditDecision.denied;
            throw McpToolException(
              McpErrorCode.policyDenied,
              'The user declined to approve this file transfer.',
              details: {'category': decision.category.wireName},
            );
          }
          success = AuditDecision.confirmed;
        case PolicyAction.allow:
          break;
      }

      final stopwatch = Stopwatch()..start();
      final (bytes, sha256) = upload
          ? await _upload(client, session, plan, limit)
          : await _download(client, plan, limit);
      final durationMs = stopwatch.elapsedMilliseconds;

      await audit(
        success,
        durationMs: durationMs,
        bytes: bytes,
        sha256: sha256,
      );
      _mirror(session)?.writeNotice(
        session.tabId!,
        '${upload ? 'uploaded' : 'downloaded'} $bytes bytes to '
        '${upload ? plan.remotePath : plan.localPath} in ${durationMs}ms '
        '(sha256 $sha256)',
      );
      return {
        'localPath': localPath,
        'remotePath': plan.remotePath,
        'bytes': bytes,
        'sha256': sha256,
        'durationMs': durationMs,
      };
    } catch (e) {
      final error = e is McpToolException
          ? e
          : McpToolException(
              McpErrorCode.internal,
              upload
                  ? 'The upload failed: $e.'
                  : 'The download failed: $e. The local destination was '
                        'not replaced.',
            );
      await audit(refusal);
      final tabId = session.tabId;
      if (tabId != null) sessionPool.mirror.writeNotice(tabId, error.message);
      throw error;
    } finally {
      final client = sftp;
      if (client != null) await _quietly(client.close);
      session.activeTransfers--;
      session.lastActivityAt = DateTime.now();
    }
  }

  /// Resolves both ends and refuses what cannot be transferred, before
  /// anyone is asked: the approval window shows the paths this returns, and
  /// those are the paths the transfer then uses.
  Future<_TransferPlan> _plan(
    SftpClient sftp,
    McpSession session, {
    required String localPath,
    required String remoteArg,
    required bool overwrite,
  }) async {
    final String remoteAbsolute;
    if (remoteArg == '~' || remoteArg.startsWith('~/')) {
      // The SFTP server starts in the login user's home.
      final home = await sftp.absolute('.');
      remoteAbsolute = remoteArg == '~'
          ? home
          : p.posix.join(home, remoteArg.substring(2));
    } else if (p.posix.isAbsolute(remoteArg)) {
      remoteAbsolute = remoteArg;
    } else {
      remoteAbsolute = p.posix.join(session.shell.cwd, remoteArg);
    }

    SftpFileAttrs? entry;
    try {
      entry = await sftp.stat(remoteAbsolute, followLink: false);
    } catch (_) {
      // Does not exist (or cannot be stat'ed): handled below.
    }

    final String remotePath;
    int? remoteSize;
    if (entry == null) {
      if (!upload) {
        throw McpToolException(
          McpErrorCode.internal,
          'Remote file "$remoteAbsolute" does not exist.',
        );
      }
      // realpath refuses a path that does not exist yet, so the directory
      // is resolved and the name appended: a symlinked directory still
      // shows, and is checked, as where the file really lands.
      final String parent;
      try {
        parent = await sftp.absolute(p.posix.dirname(remoteAbsolute));
      } catch (_) {
        throw McpToolException(
          McpErrorCode.internal,
          'Remote directory "${p.posix.dirname(remoteAbsolute)}" does not '
          'exist.',
        );
      }
      remotePath = p.posix.join(parent, p.posix.basename(remoteAbsolute));
    } else {
      // Resolved through every symlink: a link to /etc/shadow has to be
      // judged, and shown, as /etc/shadow. A link that resolves to nothing
      // is refused rather than written through blind.
      SftpFileAttrs target;
      try {
        remotePath = await sftp.absolute(remoteAbsolute);
        target = await sftp.stat(remotePath);
      } catch (_) {
        throw McpToolException(
          McpErrorCode.internal,
          'Remote path "$remoteAbsolute" is a symlink that does not resolve.',
        );
      }
      if (!target.isFile) {
        throw McpToolException(
          McpErrorCode.internal,
          'Remote path "$remotePath" is not a regular file. To move a '
          'directory, tar it first.',
        );
      }
      if (upload && !overwrite) {
        throw McpToolException(
          McpErrorCode.destinationExists,
          'Remote file "$remotePath" already exists. Pass overwrite: true '
          'only if replacing it is intended.',
        );
      }
      remoteSize = target.size;
    }

    final String localResolved;
    int? bytes = remoteSize;
    var replacesExisting = upload && entry != null;
    if (upload) {
      try {
        localResolved = await File(localPath).resolveSymbolicLinks();
      } catch (_) {
        throw McpToolException(
          McpErrorCode.internal,
          'Local file "$localPath" does not exist.',
        );
      }
      if (await FileSystemEntity.type(localResolved) !=
          FileSystemEntityType.file) {
        throw McpToolException(
          McpErrorCode.internal,
          'Local path "$localPath" is not a regular file. To move a '
          'directory, tar it first.',
        );
      }
      bytes = await File(localResolved).length();
    } else {
      final type = await FileSystemEntity.type(localPath, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        final parent = Directory(p.dirname(localPath));
        if (!await parent.exists()) {
          throw McpToolException(
            McpErrorCode.internal,
            'Local directory "${parent.path}" does not exist.',
          );
        }
        localResolved = p.join(
          await parent.resolveSymbolicLinks(),
          p.basename(localPath),
        );
      } else {
        try {
          localResolved = await File(localPath).resolveSymbolicLinks();
        } catch (_) {
          throw McpToolException(
            McpErrorCode.internal,
            'Local path "$localPath" is a symlink that does not resolve.',
          );
        }
        if (await FileSystemEntity.type(localResolved) !=
            FileSystemEntityType.file) {
          throw McpToolException(
            McpErrorCode.internal,
            'Local path "$localPath" exists and is not a regular file.',
          );
        }
        if (!overwrite) {
          throw McpToolException(
            McpErrorCode.destinationExists,
            'Local file "$localPath" already exists. Pass overwrite: true '
            'only if replacing it is intended.',
          );
        }
        replacesExisting = true;
      }
    }

    return _TransferPlan(
      localPath: localResolved,
      remotePath: remotePath,
      bytes: bytes,
      replacesExisting: replacesExisting,
      touchesCredentialPath: [
        remoteArg,
        remoteAbsolute,
        remotePath,
        localPath,
        localResolved,
      ].any(CommandClassifier.isCredentialPath),
    );
  }

  /// Streams the remote file into a temp sibling of the local destination,
  /// hashing as it goes, and renames it into place only once it is whole.
  ///
  /// The timeout closes the SFTP client, which fails every pending read; that
  /// is the only way to stop a read the server never answers.
  Future<(int, String)> _download(
    SftpClient sftp,
    _TransferPlan plan,
    Duration limit,
  ) async {
    final temp = File('${plan.localPath}.shellvibe-part-${const Uuid().v4()}');
    final hash = const DartSha256().newHashSink();
    var bytes = 0;
    var timedOut = false;
    final timer = Timer(limit, () {
      timedOut = true;
      unawaited(sftp.close());
    });
    SftpFile? remote;
    try {
      remote = await sftp.open(plan.remotePath);
      final sink = temp.openWrite();
      try {
        await sink.addStream(
          remote.read().map((chunk) {
            bytes += chunk.length;
            hash.add(chunk);
            return chunk;
          }),
        );
        await sink.flush();
      } finally {
        // A failed addStream closes the sink itself; closing it again would
        // throw and hide the real error.
        try {
          await sink.close();
        } catch (_) {}
      }
      timer.cancel();
      if (timedOut) throw TimeoutException(null);
      await temp.rename(plan.localPath);
    } catch (_) {
      if (timedOut) throw _timeoutError(limit);
      rethrow;
    } finally {
      timer.cancel();
      // Local first: with the connection gone the remote close below can
      // only fail, and the temp file must go regardless.
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
      final file = remote;
      if (file != null) await _quietly(file.close);
    }
    hash.close();
    return (bytes, _hex((await hash.hash()).bytes));
  }

  /// Streams the local file into [openRemoteReplacement]'s temp file and
  /// commits it only once it is whole.
  ///
  /// The timeout closes the SFTP client like a download's does, so the temp
  /// file is then removed over a fresh one. If the connection itself is gone
  /// (the session was closed underneath) the remote temp cannot be removed.
  Future<(int, String)> _upload(
    SftpClient sftp,
    McpSession session,
    _TransferPlan plan,
    Duration limit,
  ) async {
    final hash = const DartSha256().newHashSink();
    var bytes = 0;
    var timedOut = false;
    var committed = false;
    final timer = Timer(limit, () {
      timedOut = true;
      unawaited(sftp.close());
    });
    RemoteReplacement? replacement;
    try {
      replacement = await openRemoteReplacement(
        sftp,
        plan.remotePath,
        tempSuffix: const Uuid().v4(),
      );
      try {
        await replacement.file.write(
          File(plan.localPath).openRead().map((chunk) {
            bytes += chunk.length;
            hash.add(chunk);
            return chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
          }),
        );
      } finally {
        await _quietly(replacement.file.close);
      }
      // Stopped before the commit, never during it: a rename cut off
      // half-way would leave the agent told "timed out" about a file that
      // was in fact replaced.
      timer.cancel();
      if (timedOut) throw TimeoutException(null);
      await replacement.commit(sftp);
      committed = true;
    } catch (_) {
      if (timedOut) throw _timeoutError(limit);
      rethrow;
    } finally {
      timer.cancel();
      final pending = replacement;
      if (pending != null && !committed) {
        await _quietly(() async {
          final cleanup = timedOut
              ? await session.connection.target.openSftp()
              : sftp;
          try {
            await pending.discard(cleanup);
            // ponytail: when the helper had to write in place, a failed write
            // to an existing file has already truncated it; only a new file
            // can be removed. Fixing that needs openRemoteReplacement to
            // refuse the in-place fallback for MCP uploads.
            if (pending.writesInPlace && !plan.replacesExisting) {
              await cleanup.remove(pending.targetPath);
            }
          } finally {
            if (timedOut) await cleanup.close();
          }
        });
      }
    }
    hash.close();
    return (bytes, _hex((await hash.hash()).bytes));
  }

  McpToolException _timeoutError(Duration limit) => McpToolException(
    McpErrorCode.internal,
    'The ${upload ? 'upload' : 'download'} did not finish within '
    '${limit.inSeconds}s and was aborted; the partial file is removed and '
    'the destination left as it was. Retry with a larger timeoutSeconds '
    '(max $_maxTimeoutSeconds), or compress the file first.',
  );

  /// A required path argument with no control character in it: the approval
  /// window and the AI tab must never show less of a path than will be used.
  String _requirePath(Map<String, Object?> args, String key) {
    final value = requireString(args, key);
    if (_controlChar.hasMatch(value)) {
      throw McpToolException(
        McpErrorCode.internal,
        'Argument "$key" contains a line break or another control character. '
        'Paths with control characters are refused.',
      );
    }
    return value;
  }

  McpSessionMirror? _mirror(McpSession session) =>
      session.tabId == null ? null : sessionPool.mirror;

  static Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action().timeout(_cleanupLimit);
    } catch (_) {}
  }

  static String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

/// Both ends of one transfer, resolved and checked, as the user approves it.
class _TransferPlan {
  final String localPath;
  final String remotePath;
  final int? bytes;
  final bool replacesExisting;
  final bool touchesCredentialPath;

  const _TransferPlan({
    required this.localPath,
    required this.remotePath,
    required this.bytes,
    required this.replacesExisting,
    required this.touchesCredentialPath,
  });
}
