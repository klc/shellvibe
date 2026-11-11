import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:shellvibe/features/sftp/data/sftp_service.dart';

class FakeSftpFile implements SftpFile {
  final Uint8List content;
  @override
  bool isClosed = false;

  FakeSftpFile(this.content);

  @override
  Stream<Uint8List> read({
    int chunkSize = 32768,
    int? length,
    int maxPendingRequests = 10,
    int offset = 0,
    void Function(int)? onProgress,
  }) async* {
    final start = offset;
    final end = (length != null && start + length < content.length)
        ? start + length
        : content.length;
    if (start < content.length) {
      yield content.sublist(start, end);
    }
  }

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSftpClient implements SftpClient {
  final Map<String, Uint8List> files = {};
  final Map<String, int> fileSizes = {};

  @override
  Future<SftpFileAttrs> stat(String path, {bool followLink = true}) async {
    if (fileSizes.containsKey(path)) {
      return SftpFileAttrs(size: fileSizes[path]);
    }
    if (files.containsKey(path)) {
      return SftpFileAttrs(size: files[path]!.length);
    }
    throw Exception('File not found');
  }

  @override
  Future<SftpFile> open(String path, {SftpFileOpenMode? mode}) async {
    if (files.containsKey(path)) {
      return FakeSftpFile(files[path]!);
    }
    throw Exception('File not found');
  }

  String? lastSetStatPath;
  SftpFileAttrs? lastSetStatAttrs;

  @override
  Future<void> setStat(String path, SftpFileAttrs attrs) async {
    lastSetStatPath = path;
    lastSetStatAttrs = attrs;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLinkClient implements SftpClient {
  @override
  Stream<List<SftpName>> readdir(String path) async* {
    yield [
      SftpName(
        filename: 'alias',
        longname: '',
        attr: SftpFileAttrs(mode: const SftpFileMode.value(0xA1FF)),
      ),
    ];
  }

  @override
  Future<SftpFileAttrs> stat(String path, {bool followLink = true}) async =>
      SftpFileAttrs(mode: const SftpFileMode.value(0x41FF));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A finished writer: the bytes were counted into the log already.
class _DoneWriter with DoneFuture implements SftpFileWriter {
  _DoneWriter(this.done);

  @override
  final Future<void> done;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingFile implements SftpFile {
  _RecordingFile(this.path, this.log);

  final String path;
  final List<String> log;

  @override
  bool isClosed = false;

  @override
  SftpFileWriter write(
    Stream<Uint8List> stream, {
    int offset = 0,
    void Function(int total)? onProgress,
    int chunkSize = defaultChunkSize,
    int maxPendingRequests = defaultMaxPendingRequests,
  }) => _DoneWriter(
    stream
        .fold<int>(0, (sum, chunk) => sum + chunk.length)
        .then((bytes) => log.add('write $path $bytes')),
  );

  @override
  Future<void> close() async {
    isClosed = true;
    log.add('close $path');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A remote file system that logs every call a write makes, in order.
class _WriteRecordingClient implements SftpClient {
  final log = <String>[];

  /// What stat sees, following links.
  final files = <String, SftpFileAttrs>{};

  /// What lstat sees where it differs from [files]: the links themselves.
  final links = <String, SftpFileAttrs>{};

  /// Where each link resolves to.
  final realPaths = <String, String>{};

  final extensions = <String, String>{};
  bool refuseChown = false;

  /// Plain SFTP rename semantics: an existing target is an error.
  bool refuseRenameOverExisting = false;

  /// The log with the random temp-file suffix replaced by `.part`.
  List<String> get calls => [
    for (final entry in log)
      entry.replaceAll(RegExp(r'\.shellvibe-part-[0-9a-f-]+'), '.part'),
  ];

  @override
  Future<SftpFileAttrs> stat(String path, {bool followLink = true}) async {
    final attrs = followLink ? files[path] : (links[path] ?? files[path]);
    if (attrs == null) throw Exception('No such file');
    return attrs;
  }

  @override
  Future<String> absolute(String path) async => realPaths[path] ?? path;

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    log.add('open $path');
    return _RecordingFile(path, log);
  }

  @override
  Future<void> setStat(String path, SftpFileAttrs attrs) async {
    if (attrs.userID != null) {
      if (refuseChown) throw Exception('Permission denied');
      log.add('chown $path ${attrs.userID}:${attrs.groupID}');
    }
    if (attrs.mode != null) {
      log.add('chmod $path ${attrs.mode!.value.toRadixString(8)}');
    }
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    if (refuseRenameOverExisting && files.containsKey(newPath)) {
      throw Exception('Failure');
    }
    log.add('rename $oldPath $newPath');
  }

  @override
  Future<void> remove(String filename) async {
    files.remove(filename);
    log.add('remove $filename');
  }

  @override
  Future<SftpHandsake> get handshake async => SftpHandsake(3, extensions);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A directory tree for recursive delete.
class _TreeClient implements SftpClient {
  final log = <String>[];

  static SftpName _entry(String name, int mode) => SftpName(
    filename: name,
    longname: '',
    attr: SftpFileAttrs(mode: SftpFileMode.value(mode)),
  );

  final tree = <String, List<SftpName>>{
    '/site': [
      _entry('.', 0x41ED),
      _entry('..', 0x41ED),
      _entry('index.html', 0x81A4),
      _entry('assets', 0x41ED),
      _entry('shared', 0xA1FF),
    ],
    '/site/assets': [_entry('app.js', 0x81A4)],
  };

  @override
  Future<List<SftpName>> listdir(String path) async => tree[path] ?? [];

  @override
  Future<void> remove(String filename) async => log.add('remove $filename');

  @override
  Future<void> rmdir(String dirname) async => log.add('rmdir $dirname');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SftpService.writeFile keeps what the old file had', () {
    final content = Uint8List.fromList([1, 2, 3]);

    test('mode and owner go on the temp file before it replaces the original', () async {
      final client = _WriteRecordingClient();
      client.files['/srv/.env'] = SftpFileAttrs(
        mode: const SftpFileMode.value(0x8180), // regular file, 0600
        userID: 33,
        groupID: 33,
      );

      await SftpService().writeFile(client, '/srv/.env', content);

      expect(client.calls, [
        'open /srv/.env.part',
        // Owner first: chown clears the setuid/setgid bits the mode restores.
        'chown /srv/.env.part 33:33',
        'chmod /srv/.env.part 600',
        'write /srv/.env.part 3',
        'close /srv/.env.part',
        'rename /srv/.env.part /srv/.env',
      ]);
    });

    test('a symlink stays a link: its target is the file replaced', () async {
      final client = _WriteRecordingClient();
      client.links['/etc/nginx/sites-enabled/x'] = SftpFileAttrs(
        mode: const SftpFileMode.value(0xA1FF),
      );
      client.realPaths['/etc/nginx/sites-enabled/x'] =
          '/etc/nginx/sites-available/x';
      client.files['/etc/nginx/sites-available/x'] = SftpFileAttrs(
        mode: const SftpFileMode.value(0x81A4),
        userID: 0,
        groupID: 0,
      );

      await SftpService().writeFile(
        client,
        '/etc/nginx/sites-enabled/x',
        content,
      );

      expect(client.calls, [
        'open /etc/nginx/sites-available/x.part',
        'chown /etc/nginx/sites-available/x.part 0:0',
        'chmod /etc/nginx/sites-available/x.part 644',
        'write /etc/nginx/sites-available/x.part 3',
        'close /etc/nginx/sites-available/x.part',
        'rename /etc/nginx/sites-available/x.part /etc/nginx/sites-available/x',
      ]);
    });

    test('an owner it cannot restore means writing in place instead', () async {
      final client = _WriteRecordingClient()..refuseChown = true;
      client.files['/srv/app.conf'] = SftpFileAttrs(
        mode: const SftpFileMode.value(0x81B4),
        userID: 33,
        groupID: 33,
      );

      await SftpService().writeFile(client, '/srv/app.conf', content);

      expect(client.calls, [
        'open /srv/app.conf.part',
        'close /srv/app.conf.part',
        'remove /srv/app.conf.part',
        'open /srv/app.conf',
        'write /srv/app.conf 3',
        'close /srv/app.conf',
      ]);
    });

    test('without posix-rename the original is removed, then replaced', () async {
      final client = _WriteRecordingClient()..refuseRenameOverExisting = true;
      client.files['/a.txt'] = SftpFileAttrs(
        mode: const SftpFileMode.value(0x81A4),
      );

      await SftpService().writeFile(client, '/a.txt', content);

      expect(client.calls.skip(4), ['remove /a.txt', 'rename /a.txt.part /a.txt']);
    });

    test('with posix-rename a failed rename is an error, original kept', () async {
      final client = _WriteRecordingClient()
        ..refuseRenameOverExisting = true
        ..extensions['posix-rename@openssh.com'] = '1';
      client.files['/a.txt'] = SftpFileAttrs(
        mode: const SftpFileMode.value(0x81A4),
      );

      await expectLater(
        SftpService().writeFile(client, '/a.txt', content),
        throwsException,
      );
      expect(client.calls, isNot(contains('remove /a.txt')));
      expect(client.calls.last, 'remove /a.txt.part');
    });
  });

  test('deleting a folder deletes what is in it; links are unlinked', () async {
    final client = _TreeClient();

    await SftpService().deleteItem(client, '/site', isDirectory: true);

    expect(client.log, [
      'remove /site/index.html',
      'remove /site/assets/app.js',
      'rmdir /site/assets',
      'remove /site/shared',
      'rmdir /site',
    ]);
  });

  group('SftpService Large File & Stream Tests', () {
    late SftpService service;
    late FakeSftpClient client;

    setUp(() {
      service = SftpService();
      client = FakeSftpClient();
    });

    test('readFile succeeds under maxSizeBytes limit', () async {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      client.files['/small.txt'] = data;

      final result = await service.readFile(client, '/small.txt', maxSizeBytes: 100);
      expect(result, equals(data));
    });

    test('readFile throws Exception when file size exceeds maxSizeBytes', () async {
      final data = Uint8List.fromList(List.filled(200, 65));
      client.files['/large.txt'] = data;

      expect(
        () => service.readFile(client, '/large.txt', maxSizeBytes: 100),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('exceeds maximum in-memory limit'),
          ),
        ),
      );
    });

    test('changePermissions passes permissions value to setStat', () async {
      await service.changePermissions(client, '/test.txt', 0644);
      expect(client.lastSetStatPath, equals('/test.txt'));
      expect(client.lastSetStatAttrs?.mode?.value, equals(0644));
    });

    test('listDirectory shows a symlink to a directory as a directory', () async {
      final items = await service.listDirectory(FakeLinkClient(), '/');
      expect(items.single.isSymlink, isTrue);
      expect(items.single.isDirectory, isTrue);
    });
  });
}
