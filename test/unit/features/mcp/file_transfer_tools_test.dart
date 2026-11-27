import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shellvibe/core/network/ssh_session_manager.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/mcp/data/mcp_host_connector.dart';
import 'package:shellvibe/features/mcp/data/mcp_session_pool.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_approval_repository.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_audit_repository.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_grant_repository.dart';
import 'package:shellvibe/features/mcp/data/tools/file_transfer_tools.dart';
import 'package:shellvibe/features/mcp/data/tools/mcp_tool_handler.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_enums.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_models.dart';
import 'package:shellvibe/features/mcp/domain/services/approval_coordinator.dart';
import 'package:shellvibe/features/mcp/domain/services/policy_engine.dart';
import 'package:shellvibe/shared/database/app_database.dart';

import '../../core/mcp/fake_shell_channel.dart';

class _ChannelSession implements SSHSession {
  _ChannelSession(this.fake);

  final FakeShellChannel fake;

  @override
  Stream<Uint8List> get stdout => fake.stdout.map((b) => Uint8List.fromList(b));

  @override
  Stream<Uint8List> get stderr => fake.stderr.map((b) => Uint8List.fromList(b));

  @override
  Future<void> get done => fake.done;

  @override
  int? get exitCode => fake.exitStatus;

  @override
  void write(Uint8List data) => fake.write(data);

  @override
  void close() => fake.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// How the fake server behaves for the next transfer.
class _Server {
  /// Home directory, what `realpath .` answers.
  late String home;

  /// Fail after the first chunk.
  bool failMidway = false;

  /// After the first chunk, wait for this (or for the client to close).
  Completer<void>? gate;

  /// Signalled once the first chunk has moved.
  Completer<void> firstChunk = Completer<void>();

  final clients = <_FakeSftp>[];
}

class _Manager implements SSHSessionManager {
  _Manager(this.server);

  final _Server server;

  @override
  Future<SSHSession> openExec(String command) async =>
      _ChannelSession(FakeShellChannel());

  @override
  Future<SftpClient> openSftp() async {
    final client = _FakeSftp(server);
    server.clients.add(client);
    return client;
  }

  @override
  Stream<SSHClient?> get clientChanges => const Stream.empty();

  /// The connection going away takes every SFTP channel on it along.
  @override
  Future<void> close() async {
    for (final client in server.clients) {
      await client.close();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Connector implements McpHostConnector {
  _Connector(this.server);

  final _Server server;

  @override
  Future<McpConnection> connect(HostModel host) async =>
      McpConnection(target: _Manager(server), jumpManagers: const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An SFTP server whose filesystem is this machine's: remote paths are local
/// paths under the test's temp directory, so symlinks resolve for real.
class _FakeSftp implements SftpClient {
  _FakeSftp(this.server);

  final _Server server;
  final _closed = Completer<void>();

  bool get isClosed => _closed.isCompleted;

  void _check() {
    if (isClosed) throw const SocketException('SFTP channel closed');
  }

  /// Waits on the server's gate, failing if the channel closes first.
  Future<void> _afterFirstChunk() async {
    if (!server.firstChunk.isCompleted) server.firstChunk.complete();
    if (server.failMidway) throw const SocketException('connection reset');
    final gate = server.gate;
    if (gate != null) await Future.any([gate.future, _closed.future]);
    _check();
  }

  @override
  Future<SftpFileAttrs> stat(String path, {bool followLink = true}) async {
    _check();
    final type = FileSystemEntity.typeSync(path, followLinks: followLink);
    final bits = switch (type) {
      FileSystemEntityType.file => 1 << 15,
      FileSystemEntityType.directory => 1 << 14,
      FileSystemEntityType.link => (1 << 15) + (1 << 13),
      _ => throw const FileSystemException('No such file'),
    };
    return SftpFileAttrs(
      size: type == FileSystemEntityType.file ? File(path).lengthSync() : 0,
      mode: SftpFileMode.value(bits | 0x1A4),
    );
  }

  @override
  Future<String> absolute(String path) async {
    _check();
    return path == '.' ? server.home : File(path).resolveSymbolicLinksSync();
  }

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    _check();
    if (mode.flag & SftpFileOpenMode.write.flag != 0) {
      File(path).writeAsBytesSync(const []);
      return _WriteFile(this, path);
    }
    return _ReadFile(this, File(path).readAsBytesSync());
  }

  @override
  Future<void> setStat(String path, SftpFileAttrs attrs) async => _check();

  @override
  Future<void> remove(String filename) async {
    _check();
    File(filename).deleteSync();
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    _check();
    File(oldPath).renameSync(newPath);
  }

  @override
  Future<void> close() async {
    if (!isClosed) _closed.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReadFile implements SftpFile {
  _ReadFile(this.client, this.content);

  final _FakeSftp client;
  final Uint8List content;

  @override
  Stream<Uint8List> read({
    int? length,
    int offset = 0,
    void Function(int bytesRead)? onProgress,
    int chunkSize = 4,
    int maxPendingRequests = 1,
  }) async* {
    const size = 4;
    for (var i = 0; i < content.length; i += size) {
      yield content.sublist(i, (i + size).clamp(0, content.length));
      if (i == 0) await client._afterFirstChunk();
    }
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DoneWriter with DoneFuture implements SftpFileWriter {
  _DoneWriter(this.done);

  @override
  final Future<void> done;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WriteFile implements SftpFile {
  _WriteFile(this.client, this.path);

  final _FakeSftp client;
  final String path;

  @override
  SftpFileWriter write(
    Stream<Uint8List> stream, {
    int offset = 0,
    void Function(int total)? onProgress,
    int chunkSize = defaultChunkSize,
    int maxPendingRequests = defaultMaxPendingRequests,
  }) => _DoneWriter(_write(stream));

  Future<void> _write(Stream<Uint8List> stream) async {
    final file = File(path).openSync(mode: FileMode.append);
    try {
      var first = true;
      await for (final chunk in stream) {
        file.writeFromSync(chunk);
        if (first) {
          first = false;
          await client._afterFirstChunk();
        }
      }
    } finally {
      file.closeSync();
    }
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tmp;
  late String remoteDir;
  late String localDir;
  late _Server server;
  late AppDatabase db;
  late McpAuditRepository audit;
  late McpGrantRepository grants;
  late ApprovalCoordinator approvals;
  late McpSessionPool pool;
  late McpSession session;

  const ctx = McpToolContext(
    clientId: 'client-1',
    clientName: 'Agent',
    workspaceId: 'default',
    connectionScopeId: 'scope-1',
  );
  final content = Uint8List.fromList(List.generate(1000, (i) => (i * 7) % 256));
  final contentSha = const DartSha256()
      .hashSync(content)
      .bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  Future<void> insertHost({bool visible = true, String max = 'autonomous'}) =>
      db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'host-a',
          workspaceId: 'default',
          label: 'box',
          hostname: 'box.example.com',
          createdAt: DateTime(2026),
          mcpVisible: Value(visible),
          mcpDefaultMode: Value(max),
        ),
      );

  Future<void> grant(McpAccessMode mode) =>
      grants.grant(clientId: ctx.clientId, hostId: 'host-a', mode: mode);

  FileTransferTool tool({required bool upload}) => upload
      ? FileTransferTool.upload(
          sessionPool: pool,
          hostsDao: db.hostsDao,
          grantRepository: grants,
          auditRepository: audit,
          policyEngine: PolicyEngine(
            approvals: McpApprovalRepository(db.mcpDao),
            dao: db.mcpDao,
          ),
          approvalCoordinator: approvals,
        )
      : FileTransferTool.download(
          sessionPool: pool,
          hostsDao: db.hostsDao,
          grantRepository: grants,
          auditRepository: audit,
          policyEngine: PolicyEngine(
            approvals: McpApprovalRepository(db.mcpDao),
            dao: db.mcpDao,
          ),
          approvalCoordinator: approvals,
        );

  Future<Object?> run(
    bool upload,
    String local,
    String remote, {
    bool? overwrite,
    int? timeoutSeconds,
    String? description,
  }) => tool(upload: upload).execute(ctx, {
    'sessionId': session.sessionId,
    'localPath': local,
    'remotePath': remote,
    'overwrite': ?overwrite,
    'timeoutSeconds': ?timeoutSeconds,
    'description': ?description,
  });

  /// Answers the next approval request with [approve], handing it back.
  Future<CommandApprovalRequest> answerNext({required bool approve}) async {
    while (approvals.currentCommands.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final pending = approvals.currentCommands.single;
    approvals.resolveCommand(pending.id, ApprovalDecision(approved: approve));
    return pending.request;
  }

  Future<List<(String, String, String?)>> rows() async => [
    for (final r in await audit.query()) (r.tool, r.decision, r.category),
  ];

  Matcher throwsCode(McpErrorCode code) =>
      throwsA(isA<McpToolException>().having((e) => e.code, 'code', code));

  List<String> leftovers(String dir) => [
    for (final f in Directory(dir).listSync())
      if (f.path.contains('.shellvibe-part-')) f.path,
  ];

  setUp(() async {
    tmp = Directory(
      Directory.systemTemp
          .createTempSync('mcp_transfer_')
          .resolveSymbolicLinksSync(),
    );
    remoteDir = p.join(tmp.path, 'remote');
    localDir = p.join(tmp.path, 'local');
    Directory(remoteDir).createSync();
    Directory(localDir).createSync();
    server = _Server()..home = remoteDir;

    db = AppDatabase(NativeDatabase.memory());
    await db.mcpDao.insertClient(
      McpClientsCompanion.insert(
        id: ctx.clientId,
        workspaceId: 'default',
        name: ctx.clientName,
        tokenHash: 'hash',
        createdAt: DateTime(2026),
      ),
    );
    audit = McpAuditRepository(db.mcpDao);
    grants = McpGrantRepository(db.mcpDao);
    approvals = ApprovalCoordinator();
    pool = McpSessionPool(connector: _Connector(server));
    session = await pool.open(
      clientId: ctx.clientId,
      connectionScopeId: ctx.connectionScopeId,
      clientName: ctx.clientName,
      mode: 'guarded',
      host: HostModel(
        id: 'host-a',
        workspaceId: 'default',
        label: 'box',
        hostname: 'box.example.com',
        createdAt: DateTime(2026),
      ),
    );
  });

  tearDown(() async {
    pool.dispose();
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  group('refused before anything moves', () {
    test(
      'no live grant is HOST_ACCESS_REQUIRED, audited auto_denied',
      () async {
        await insertHost();
        final local = p.join(localDir, 'a.bin');
        File(local).writeAsBytesSync(content);

        await expectLater(
          run(true, local, p.join(remoteDir, 'a.bin')),
          throwsCode(McpErrorCode.hostAccessRequired),
        );
        expect(await rows(), [('upload_file', 'auto_denied', null)]);
        expect(File(p.join(remoteDir, 'a.bin')).existsSync(), isFalse);
      },
    );

    test('a hidden host is refused', () async {
      await insertHost(visible: false);
      await grant(McpAccessMode.autonomous);

      await expectLater(
        run(false, p.join(localDir, 'a.bin'), p.join(remoteDir, 'a.bin')),
        throwsCode(McpErrorCode.hostNotVisible),
      );
      expect(await rows(), [('download_file', 'auto_denied', null)]);
    });

    test('a readonly upload is denied and writes nothing', () async {
      await insertHost();
      await grant(McpAccessMode.readonly);
      final local = p.join(localDir, 'a.bin');
      File(local).writeAsBytesSync(content);

      await expectLater(
        run(true, local, p.join(remoteDir, 'a.bin')),
        throwsCode(McpErrorCode.policyDenied),
      );
      expect(Directory(remoteDir).listSync(), isEmpty);
      expect(await rows(), [('upload_file', 'denied', 'file_transfer')]);
    });

    test('the host max holds a wider grant down', () async {
      await insertHost(max: 'readonly');
      await grant(McpAccessMode.autonomous);
      final local = p.join(localDir, 'a.bin');
      File(local).writeAsBytesSync(content);

      await expectLater(
        run(true, local, p.join(remoteDir, 'a.bin')),
        throwsCode(McpErrorCode.policyDenied),
      );
    });

    test('a control character in a path is an argument error', () async {
      for (final bad in ['/tmp/a\nb', '/tmp/a\rb', '/tmp/a\u0000b']) {
        await expectLater(
          run(true, bad, '/tmp/x'),
          throwsA(
            isA<McpToolException>()
                .having((e) => e.code, 'code', McpErrorCode.internal)
                .having((e) => e.message, 'message', contains('control')),
          ),
        );
        await expectLater(
          run(false, '/tmp/x', bad),
          throwsCode(McpErrorCode.internal),
        );
      }
    });

    test('a relative localPath is refused', () async {
      await expectLater(
        run(true, 'a.bin', '/tmp/x'),
        throwsCode(McpErrorCode.internal),
      );
    });

    test(
      'an existing destination needs overwrite and stays untouched',
      () async {
        await insertHost();
        await grant(McpAccessMode.autonomous);
        final local = p.join(localDir, 'a.bin');
        final remote = p.join(remoteDir, 'a.bin');
        File(local).writeAsStringSync('local');
        File(remote).writeAsStringSync('remote');

        await expectLater(
          run(true, local, remote),
          throwsCode(McpErrorCode.destinationExists),
        );
        await expectLater(
          run(false, local, remote),
          throwsCode(McpErrorCode.destinationExists),
        );
        expect(File(local).readAsStringSync(), 'local');
        expect(File(remote).readAsStringSync(), 'remote');
      },
    );
  });

  group('credential paths', () {
    test('caught through a remote symlink\'s resolved path', () async {
      await insertHost();
      await grant(McpAccessMode.autonomous);
      Directory(p.join(tmp.path, 'etc')).createSync();
      File(p.join(tmp.path, 'etc', 'shadow')).writeAsStringSync('root:x');
      Link(
        p.join(remoteDir, 'notes.txt'),
      ).createSync(p.join(tmp.path, 'etc', 'shadow'));

      // Neither the name as given nor `~/notes.txt` names a secret; only
      // where the link points does.
      final asked = run(false, p.join(localDir, 'notes.txt'), '~/notes.txt');
      final request = await answerNext(approve: false);
      await expectLater(asked, throwsCode(McpErrorCode.policyDenied));

      expect(request.category, RiskCategory.secretRead);
      expect(request.canRemember, isFalse);
      expect(request.transfer!.remotePath, p.join(tmp.path, 'etc', 'shadow'));
      expect(File(p.join(localDir, 'notes.txt')).existsSync(), isFalse);
    });

    test('caught through the local path on upload', () async {
      await insertHost();
      await grant(McpAccessMode.autonomous);
      Directory(p.join(tmp.path, '.ssh')).createSync();
      File(p.join(tmp.path, '.ssh', 'id_ed25519')).writeAsStringSync('key');
      final local = p.join(localDir, 'upload.txt');
      Link(local).createSync(p.join(tmp.path, '.ssh', 'id_ed25519'));

      final asked = run(true, local, p.join(remoteDir, 'upload.txt'));
      final request = await answerNext(approve: false);
      await expectLater(asked, throwsCode(McpErrorCode.policyDenied));

      // Autonomous would have allowed a plain upload without asking.
      expect(request.category, RiskCategory.secretRead);
      expect(File(p.join(remoteDir, 'upload.txt')).existsSync(), isFalse);
    });
  });

  test('a declined approval moves nothing and is audited denied', () async {
    await insertHost();
    await grant(McpAccessMode.guarded);
    final local = p.join(localDir, 'a.bin');
    File(local).writeAsBytesSync(content);

    final call = run(true, local, p.join(remoteDir, 'a.bin'));
    final request = await answerNext(approve: false);
    await expectLater(call, throwsCode(McpErrorCode.policyDenied));

    expect(request.canRemember, isFalse);
    expect(request.transfer!.upload, isTrue);
    expect(request.transfer!.bytes, content.length);
    expect(request.transfer!.replacesExisting, isFalse);
    expect(Directory(remoteDir).listSync(), isEmpty);
    expect(await rows(), [('upload_file', 'denied', 'file_transfer')]);
  });

  test('the agent description reaches the approval and the audit', () async {
    await insertHost();
    await grant(McpAccessMode.guarded);
    final local = p.join(localDir, 'a.bin');
    File(local).writeAsBytesSync(content);

    final call = run(
      true,
      local,
      p.join(remoteDir, 'a.bin'),
      description: 'Ship the build\nfor review',
    );
    final request = await answerNext(approve: false);
    await expectLater(call, throwsCode(McpErrorCode.policyDenied));

    expect(request.description, 'Ship the build for review');
    expect(
      (await audit.query()).single.argsJson,
      contains('Ship the build for review'),
    );
  });

  test('upload arrives intact with the right hash, no temp left', () async {
    await insertHost();
    await grant(McpAccessMode.autonomous);
    final local = p.join(localDir, 'a.bin');
    File(local).writeAsBytesSync(content);

    final result =
        await run(true, local, p.join(remoteDir, 'a.bin'))
            as Map<String, Object?>;

    expect(File(p.join(remoteDir, 'a.bin')).readAsBytesSync(), content);
    expect(result['bytes'], content.length);
    expect(result['sha256'], contentSha);
    expect(result['remotePath'], p.join(remoteDir, 'a.bin'));
    expect(leftovers(remoteDir), isEmpty);
    final row = (await audit.query()).single;
    expect(row.decision, 'allowed');
    expect(row.outputBytes, content.length);
    expect(row.outputSha256, contentSha);
  });

  test('upload over an existing file asks, then replaces it', () async {
    await insertHost();
    await grant(McpAccessMode.autonomous);
    final local = p.join(localDir, 'a.bin');
    final remote = p.join(remoteDir, 'a.bin');
    File(local).writeAsBytesSync(content);
    File(remote).writeAsStringSync('old');

    final call = run(true, local, remote, overwrite: true);
    final request = await answerNext(approve: true);
    await call;

    expect(request.category, RiskCategory.destructiveFs);
    expect(request.transfer!.replacesExisting, isTrue);
    expect(File(remote).readAsBytesSync(), content);
    expect(await rows(), [('upload_file', 'confirmed', 'destructive_fs')]);
  });

  test('download arrives intact, approved in guarded mode', () async {
    await insertHost();
    await grant(McpAccessMode.guarded);
    File(p.join(remoteDir, 'a.bin')).writeAsBytesSync(content);
    final local = p.join(localDir, 'a.bin');

    final call = run(false, local, '~/a.bin');
    await answerNext(approve: true);
    final result = await call as Map<String, Object?>;

    expect(File(local).readAsBytesSync(), content);
    expect(result['sha256'], contentSha);
    expect(result['bytes'], content.length);
    expect(leftovers(localDir), isEmpty);
    expect(await rows(), [('download_file', 'confirmed', 'file_transfer')]);
  });

  group('failures leave no partial file', () {
    test('download failing midway keeps the old local file', () async {
      await insertHost();
      await grant(McpAccessMode.autonomous);
      File(p.join(remoteDir, 'a.bin')).writeAsBytesSync(content);
      final local = p.join(localDir, 'a.bin');
      File(local).writeAsStringSync('old');
      server.failMidway = true;

      await expectLater(
        run(false, local, p.join(remoteDir, 'a.bin'), overwrite: true),
        throwsCode(McpErrorCode.internal),
      );
      expect(File(local).readAsStringSync(), 'old');
      expect(leftovers(localDir), isEmpty);
      expect(await rows(), [('download_file', 'error', 'file_transfer')]);
    });

    test('upload failing midway keeps the old remote file', () async {
      await insertHost();
      await grant(McpAccessMode.autonomous);
      final local = p.join(localDir, 'a.bin');
      final remote = p.join(remoteDir, 'a.bin');
      File(local).writeAsBytesSync(content);
      File(remote).writeAsStringSync('old');
      server.failMidway = true;

      final call = run(true, local, remote, overwrite: true);
      await answerNext(approve: true);
      await expectLater(call, throwsCode(McpErrorCode.internal));

      expect(File(remote).readAsStringSync(), 'old');
      expect(leftovers(remoteDir), isEmpty);
      expect(await rows(), [('upload_file', 'error', 'destructive_fs')]);
    });

    test('download timing out is aborted and cleaned up', () async {
      await insertHost();
      await grant(McpAccessMode.autonomous);
      File(p.join(remoteDir, 'a.bin')).writeAsBytesSync(content);
      final local = p.join(localDir, 'a.bin');
      File(local).writeAsStringSync('old');
      server.gate = Completer<void>(); // never opens

      await expectLater(
        run(
          false,
          local,
          p.join(remoteDir, 'a.bin'),
          overwrite: true,
          timeoutSeconds: 1,
        ),
        throwsA(
          isA<McpToolException>().having(
            (e) => e.message,
            'message',
            contains('did not finish within 1s'),
          ),
        ),
      );
      expect(File(local).readAsStringSync(), 'old');
      expect(leftovers(localDir), isEmpty);
      expect(await rows(), [('download_file', 'error', 'file_transfer')]);
    });

    test('upload timing out removes the remote temp file', () async {
      await insertHost();
      await grant(McpAccessMode.autonomous);
      final local = p.join(localDir, 'a.bin');
      File(local).writeAsBytesSync(content);
      server.gate = Completer<void>(); // never opens

      await expectLater(
        run(true, local, p.join(remoteDir, 'a.bin'), timeoutSeconds: 1),
        throwsA(
          isA<McpToolException>().having(
            (e) => e.message,
            'message',
            contains('did not finish within 1s'),
          ),
        ),
      );
      expect(Directory(remoteDir).listSync(), isEmpty);
      expect(await rows(), [('upload_file', 'error', 'file_transfer')]);
    });

    test(
      'the session closed underneath still removes the local temp',
      () async {
        await insertHost();
        await grant(McpAccessMode.autonomous);
        File(p.join(remoteDir, 'a.bin')).writeAsBytesSync(content);
        final local = p.join(localDir, 'a.bin');
        server.gate = Completer<void>();

        final call = run(false, local, p.join(remoteDir, 'a.bin'));
        await server.firstChunk.future;
        await pool.closeAll();

        await expectLater(call, throwsCode(McpErrorCode.internal));
        expect(Directory(localDir).listSync(), isEmpty);
      },
    );
  });

  test('the session is busy while a transfer runs', () async {
    await insertHost();
    await grant(McpAccessMode.autonomous);
    File(p.join(remoteDir, 'a.bin')).writeAsBytesSync(content);
    final gate = server.gate = Completer<void>();
    expect(session.busy, isFalse);

    final call = run(
      false,
      p.join(localDir, 'a.bin'),
      p.join(remoteDir, 'a.bin'),
    );
    await server.firstChunk.future;
    expect(session.busy, isTrue);

    gate.complete();
    await call;
    expect(session.busy, isFalse);
    expect(File(p.join(localDir, 'a.bin')).readAsBytesSync(), content);
  });
}
