import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../shared/providers/database_providers.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
import '../../data/services/ssh_config_import_service.dart';

part 'ssh_config_import_provider.g.dart';

/// Provides the SSH config import service bound to the app database and vault.
@riverpod
SshConfigImportService sshConfigImportService(Ref ref) {
  return SshConfigImportService(
    db: ref.watch(appDatabaseProvider),
    vaultKeyService: ref.watch(vaultKeyServiceProvider),
    encryptionEngine: ref.watch(encryptionEngineProvider),
  );
}
