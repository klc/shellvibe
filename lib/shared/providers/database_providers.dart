import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/crypto/encryption_engine.dart';
import '../database/app_database.dart';
import '../database/daos/hosts_dao.dart';
import '../database/daos/identities_dao.dart';
import '../database/daos/known_hosts_dao.dart';
import '../database/daos/runbooks_dao.dart';
import '../database/daos/snippets_dao.dart';
import '../database/daos/tunnels_dao.dart';
import '../storage/secure_storage_service.dart';

part 'database_providers.g.dart';

/// Provides a single instance of [AppDatabase].
@Riverpod(keepAlive: true)
AppDatabase appDatabase(AppDatabaseRef ref) {
  final db = AppDatabase();
  ref.onDispose(() {
    db.close();
  });
  return db;
}

/// Auto-disposing provider for [KnownHostsDao].
@riverpod
KnownHostsDao knownHostsDao(KnownHostsDaoRef ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.knownHostsDao;
}

/// Auto-disposing provider for [HostsDao].
@riverpod
HostsDao hostsDao(HostsDaoRef ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.hostsDao;
}

/// Auto-disposing provider for [IdentitiesDao].
@riverpod
IdentitiesDao identitiesDao(IdentitiesDaoRef ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.identitiesDao;
}

/// Auto-disposing provider for [TunnelsDao].
@riverpod
TunnelsDao tunnelsDao(TunnelsDaoRef ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.tunnelsDao;
}

/// Auto-disposing provider for [SnippetsDao].
@riverpod
SnippetsDao snippetsDao(SnippetsDaoRef ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.snippetsDao;
}

/// Auto-disposing provider for [RunbooksDao].
@riverpod
RunbooksDao runbooksDao(RunbooksDaoRef ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.runbooksDao;
}

/// Provider for [EncryptionEngine].
@riverpod
EncryptionEngine encryptionEngine(EncryptionEngineRef ref) {
  return EncryptionEngine();
}

/// Provider for [SecureStorageService].
@riverpod
SecureStorageService secureStorageService(SecureStorageServiceRef ref) {
  return SecureStorageService();
}

