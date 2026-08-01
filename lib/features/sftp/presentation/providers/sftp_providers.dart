import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/sftp_service.dart';
import '../../data/sftp_transfer_queue_worker.dart';
import '../../domain/models/sftp_file_item.dart';
import '../../domain/models/transfer_item.dart';

part 'sftp_providers.g.dart';

/// Provider for [SftpService]
@riverpod
SftpService sftpService(Ref ref) {
  return SftpService();
}

/// Provider for [SftpTransferQueueWorker].
///
/// keepAlive: the transfer queue must survive screen navigation — an
/// autoDispose worker would be torn down (closing the queue controller) while
/// transfers are in flight, failing them mid-write and wiping the queue.
@Riverpod(keepAlive: true)
SftpTransferQueueWorker sftpTransferQueueWorker(
  SftpTransferQueueWorkerRef ref,
) {
  final worker = SftpTransferQueueWorker();
  ref.onDispose(() {
    worker.dispose();
  });
  return worker;
}

/// Provider watching the active transfer queue list
@riverpod
Stream<List<TransferItem>> transferQueueStream(Ref ref) {
  final worker = ref.watch(sftpTransferQueueWorkerProvider);
  return worker.watchQueue();
}

class SftpState {
  final SftpClient? remoteClient;
  final String remotePath;
  final String localPath;
  final List<SftpFileItem> remoteFiles;
  final List<SftpFileItem> localFiles;
  final bool isLoadingRemote;
  final bool isLoadingLocal;
  final String? remoteError;
  final String? localError;
  final Set<String> selectedRemotePaths;
  final Set<String> selectedLocalPaths;
  final String searchQuery;

  const SftpState({
    this.remoteClient,
    this.remotePath = '/',
    this.localPath = '/',
    this.remoteFiles = const [],
    this.localFiles = const [],
    this.isLoadingRemote = false,
    this.isLoadingLocal = false,
    this.remoteError,
    this.localError,
    this.selectedRemotePaths = const {},
    this.selectedLocalPaths = const {},
    this.searchQuery = '',
  });

  SftpState copyWith({
    SftpClient? remoteClient,
    bool clearRemoteClient = false,
    String? remotePath,
    String? localPath,
    List<SftpFileItem>? remoteFiles,
    List<SftpFileItem>? localFiles,
    bool? isLoadingRemote,
    bool? isLoadingLocal,
    String? remoteError,
    String? localError,
    Set<String>? selectedRemotePaths,
    Set<String>? selectedLocalPaths,
    String? searchQuery,
  }) {
    return SftpState(
      remoteClient: clearRemoteClient
          ? null
          : (remoteClient ?? this.remoteClient),
      remotePath: remotePath ?? this.remotePath,
      localPath: localPath ?? this.localPath,
      remoteFiles: remoteFiles ?? this.remoteFiles,
      localFiles: localFiles ?? this.localFiles,
      isLoadingRemote: isLoadingRemote ?? this.isLoadingRemote,
      isLoadingLocal: isLoadingLocal ?? this.isLoadingLocal,
      remoteError: remoteError,
      localError: localError,
      selectedRemotePaths: selectedRemotePaths ?? this.selectedRemotePaths,
      selectedLocalPaths: selectedLocalPaths ?? this.selectedLocalPaths,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

@Riverpod(keepAlive: true)
class SftpNotifier extends _$SftpNotifier {
  /// Set when the provider is disposed. Riverpod 2.x has no `ref.mounted` for
  /// notifier refs, and async continuations (deferred loads) must not write
  /// state after disposal.
  bool _disposed = false;

  @override
  SftpState build() {
    ref.onDispose(() {
      _disposed = true;
      try {
        state.remoteClient?.close();
      } catch (_) {}
    });
    final defaultLocal = _getDefaultLocalPath();
    final initialState = SftpState(localPath: defaultLocal);
    // Initial local directory load
    Future.microtask(() => loadLocalDirectory(defaultLocal));
    return initialState;
  }

  static String _getDefaultLocalPath() {
    try {
      return Directory.current.path;
    } catch (_) {
      return '/';
    }
  }

  void setRemoteClient(SftpClient? client) {
    final old = state.remoteClient;
    if (identical(old, client)) return;

    if (client == null) {
      state = state.copyWith(clearRemoteClient: true);
    } else {
      state = state.copyWith(remoteClient: client);
      loadRemoteDirectory(state.remotePath);
    }

    // A replaced or cleared client must not leak its socket; the notifier
    // dispose hook only closes the client currently referenced by state.
    if (old != null && !identical(old, client)) {
      try {
        old.close();
      } catch (_) {}
    }
  }

  Future<void> loadRemoteDirectory([String? path]) async {
    // The notifier may have been disposed while awaiting; writing state then
    // would throw.
    if (_disposed) return;
    final client = state.remoteClient;
    final targetPath = path ?? state.remotePath;

    if (client == null) {
      state = state.copyWith(
        remoteError: 'SFTP connection not established',
        isLoadingRemote: false,
      );
      return;
    }

    state = state.copyWith(isLoadingRemote: true, remoteError: null);

    try {
      final sftpService = ref.read(sftpServiceProvider);
      final files = await sftpService.listDirectory(client, targetPath);
      if (_disposed) return;
      state = state.copyWith(
        remotePath: targetPath,
        remoteFiles: files,
        isLoadingRemote: false,
      );
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(
        remoteError: 'Failed to list directory $targetPath: $e',
        isLoadingRemote: false,
      );
    }
  }

  Future<void> loadLocalDirectory([String? path]) async {
    if (_disposed) return;
    final targetPath = path ?? state.localPath;
    state = state.copyWith(isLoadingLocal: true, localError: null);

    try {
      final dir = Directory(targetPath);
      if (!dir.existsSync()) {
        state = state.copyWith(
          localError: 'Directory does not exist: $targetPath',
          isLoadingLocal: false,
        );
        return;
      }

      final entities = await dir.list().toList();
      final items = <SftpFileItem>[];

      // Async stat: statSync per entry blocks the UI isolate for seconds on
      // large directories.
      for (final entity in entities) {
        try {
          final stat = await entity.stat();
          items.add(SftpFileItem.fromFileSystemEntity(entity, stat: stat));
        } catch (_) {}
      }

      items.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      if (!_disposed) {
        state = state.copyWith(
          localPath: targetPath,
          localFiles: items,
          isLoadingLocal: false,
        );
      }
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(
        localError: 'Failed to list local directory: $e',
        isLoadingLocal: false,
      );
    }
  }

  void navigateRemoteUp() {
    if (state.remotePath == '/') return;
    final parent = p.dirname(state.remotePath);
    loadRemoteDirectory(parent);
  }

  void navigateLocalUp() {
    final parent = p.dirname(state.localPath);
    if (parent == state.localPath) return;
    loadLocalDirectory(parent);
  }

  Future<void> createRemoteFolder(String name) async {
    final client = state.remoteClient;
    if (client == null) return;
    final fullPath = p.join(state.remotePath, name);
    try {
      await ref.read(sftpServiceProvider).createDirectory(client, fullPath);
      await loadRemoteDirectory();
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(remoteError: 'Failed to create directory: $e');
    }
  }

  Future<void> createRemoteFile(String name) async {
    final client = state.remoteClient;
    if (client == null) return;
    final fullPath = p.join(state.remotePath, name);
    try {
      await ref.read(sftpServiceProvider).createFile(client, fullPath);
      await loadRemoteDirectory();
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(remoteError: 'Failed to create file: $e');
    }
  }

  Future<void> deleteRemoteItem(SftpFileItem item) async {
    final client = state.remoteClient;
    if (client == null) return;
    try {
      await ref
          .read(sftpServiceProvider)
          .deleteItem(client, item.path, isDirectory: item.isDirectory);
      await loadRemoteDirectory();
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(remoteError: 'Failed to delete item: $e');
    }
  }

  Future<void> deleteLocalItem(SftpFileItem item) async {
    try {
      if (item.isDirectory) {
        await Directory(item.path).delete(recursive: true);
      } else {
        await File(item.path).delete();
      }
      await loadLocalDirectory();
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(localError: 'Failed to delete local item: $e');
    }
  }

  Future<void> renameRemoteItem(SftpFileItem item, String newName) async {
    final client = state.remoteClient;
    if (client == null) return;
    final newPath = p.join(p.dirname(item.path), newName);
    try {
      await ref
          .read(sftpServiceProvider)
          .renameItem(client, item.path, newPath);
      await loadRemoteDirectory();
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(remoteError: 'Failed to rename: $e');
    }
  }

  Future<void> changeRemotePermissions(
    SftpFileItem item,
    int permissions,
  ) async {
    final client = state.remoteClient;
    if (client == null) return;
    try {
      await ref
          .read(sftpServiceProvider)
          .changePermissions(client, item.path, permissions);
      await loadRemoteDirectory();
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(remoteError: 'Failed to change permissions: $e');
    }
  }

  Future<void> changeRemoteOwner(
    SftpFileItem item, {
    int? uid,
    int? gid,
  }) async {
    final client = state.remoteClient;
    if (client == null) return;
    try {
      await ref
          .read(sftpServiceProvider)
          .changeOwner(client, item.path, uid: uid, gid: gid);
      await loadRemoteDirectory();
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(remoteError: 'Failed to change owner: $e');
    }
  }

  Future<String> readRemoteFileContent(String path) async {
    final client = state.remoteClient;
    if (client == null) throw Exception('SFTP client is not connected');
    final bytes = await ref.read(sftpServiceProvider).readFile(client, path);
    return utf8.decode(bytes);
  }

  Future<void> saveRemoteFileContent(String path, String content) async {
    final client = state.remoteClient;
    if (client == null) throw Exception('SFTP client is not connected');
    final bytes = Uint8List.fromList(utf8.encode(content));
    await ref.read(sftpServiceProvider).writeFile(client, path, bytes);
    if (_disposed) return;
    await loadRemoteDirectory();
  }

  void downloadItem(SftpFileItem item) {
    final client = state.remoteClient;
    if (client == null) return;
    final localDest = p.join(state.localPath, item.name);

    ref
        .read(sftpTransferQueueWorkerProvider)
        .enqueueDownload(
          client: client,
          remotePath: item.path,
          localPath: localDest,
          size: item.size,
        );
  }

  void uploadLocalItem(SftpFileItem item) {
    final client = state.remoteClient;
    if (client == null) return;
    final remoteDest = p.join(state.remotePath, item.name);

    ref
        .read(sftpTransferQueueWorkerProvider)
        .enqueueUpload(
          client: client,
          localPath: item.path,
          remotePath: remoteDest,
        );
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }
}
