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

void main() {
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
  });
}
