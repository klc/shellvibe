import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/crypto/encryption_engine.dart';
import '../database/app_database.dart';
import '../database/daos/hosts_dao.dart';
import '../database/daos/identities_dao.dart';
import '../database/daos/known_hosts_dao.dart';
import '../database/daos/runbooks_dao.dart';
import '../database/daos/snippets_dao.dart';
import '../database/daos/templates_dao.dart';
import '../database/daos/tunnels_dao.dart';
import '../storage/secure_storage_service.dart';

part 'database_providers.g.dart';

/// Provides a single instance of [AppDatabase].
///
/// The drift database is deliberately **not** closed on dispose. The connection
/// is a `NativeDatabase.createInBackground` executor, so closing it here frees
/// the sqlite3 connection while the executor isolate is still going down; at
/// isolate shutdown the VM runs every attached `sqlite3_finalize` native
/// finalizer against that freed connection, crashing the app with SIGSEGV on
/// exit (macOS release, "[Process exited with code 255]"). Letting the process
/// exit reclaim the DB is safe: the finalizers then run against a live
/// connection and SQLite's WAL recovery makes the file crash-safe.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  return AppDatabase();
}

/// Auto-disposing provider for [KnownHostsDao].
@riverpod
KnownHostsDao knownHostsDao(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.knownHostsDao;
}

/// Auto-disposing provider for [HostsDao].
@riverpod
HostsDao hostsDao(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.hostsDao;
}

/// Auto-disposing provider for [IdentitiesDao].
@riverpod
IdentitiesDao identitiesDao(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.identitiesDao;
}

/// Auto-disposing provider for [TunnelsDao].
@riverpod
TunnelsDao tunnelsDao(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.tunnelsDao;
}

/// Auto-disposing provider for [SnippetsDao].
@riverpod
SnippetsDao snippetsDao(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.snippetsDao;
}

/// Auto-disposing provider for [RunbooksDao].
@riverpod
RunbooksDao runbooksDao(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.runbooksDao;
}

/// Auto-disposing provider for [TemplatesDao].
@riverpod
TemplatesDao templatesDao(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.templatesDao;
}

/// Provider for [EncryptionEngine].
@riverpod
EncryptionEngine encryptionEngine(Ref ref) {
  return EncryptionEngine();
}

/// Provider for [SecureStorageService].
@riverpod
SecureStorageService secureStorageService(Ref ref) {
  return SecureStorageService();
}

