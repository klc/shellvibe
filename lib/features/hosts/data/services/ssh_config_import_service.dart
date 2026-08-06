import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../../core/crypto/encryption_engine.dart';
import '../../../../shared/database/app_database.dart';
import '../../../vault/data/repositories/vault_repository.dart';
import '../../../vault/data/vault_key_service.dart';
import '../../domain/models/ssh_config_models.dart';
import '../../domain/services/ssh_config_resolver.dart';

/// Reads a file's content, or null when it does not exist / cannot be read.
typedef SshConfigFileReader = String? Function(String path);

/// Lists a directory's direct children (basenames, sorted), or null when the
/// directory does not exist.
typedef SshConfigDirListerFn = List<String>? Function(String dirPath);

/// How an alias that already exists in the target workspace is handled.
enum SshConfigConflictPolicy { skip, overwrite, duplicate }

/// User choices for one import run.
class SshConfigImportOptions {
  final String workspaceId;
  final String? groupId;
  final SshConfigConflictPolicy conflictPolicy;

  /// When true, readable `IdentityFile`s are imported into the vault as
  /// `key` identities (deduplicated by key content). Requires an unlocked
  /// vault when any key is present — otherwise [VaultLockedException] is
  /// thrown before anything is written.
  final bool importIdentityFiles;
  final bool importTunnels;

  /// When true, `ProxyJump` targets that match no imported or existing host
  /// get a minimal host entry created for them.
  final bool createMissingJumpHosts;

  /// When non-null, only aliases in this set are imported (preview selection).
  final Set<String>? onlyAliases;

  const SshConfigImportOptions({
    required this.workspaceId,
    this.groupId,
    this.conflictPolicy = SshConfigConflictPolicy.skip,
    this.importIdentityFiles = true,
    this.importTunnels = true,
    this.createMissingJumpHosts = true,
    this.onlyAliases,
  });
}

/// Outcome of one import run.
class SshConfigImportResult {
  final int hostsAdded;
  final int hostsUpdated;
  final int hostsSkipped;
  final int identitiesAdded;
  final int tunnelsAdded;
  final int jumpHostsAdded;
  final List<SshConfigWarning> warnings;

  const SshConfigImportResult({
    required this.hostsAdded,
    required this.hostsUpdated,
    required this.hostsSkipped,
    required this.identitiesAdded,
    required this.tunnelsAdded,
    required this.jumpHostsAdded,
    required this.warnings,
  });
}

/// Imports an OpenSSH `~/.ssh/config` file into a workspace.
///
/// Flow: resolve the config with [SshConfigResolver] (pattern semantics,
/// Includes, tokens), map each concrete alias to a host row, optionally
/// import private keys into the vault (AES-256-GCM under the vault DEK,
/// deduplicated by key content), resolve `ProxyJump` targets, then write
/// everything in a single drift transaction so a failure rolls back the whole
/// run.
///
/// All file access goes through [readFile]/[listDir], which default to
/// `dart:io` and can be faked in tests.
class SshConfigImportService {
  final AppDatabase db;
  final VaultKeyService vaultKeyService;
  final EncryptionEngine encryptionEngine;
  final String homePath;
  final Map<String, String> environment;
  final SshConfigFileReader readFile;
  final SshConfigDirListerFn listDir;
  late final VaultRepository _vaultRepository;

  SshConfigImportService({
    required this.db,
    required this.vaultKeyService,
    required this.encryptionEngine,
    String? homePath,
    Map<String, String>? environment,
    SshConfigFileReader? readFile,
    SshConfigDirListerFn? listDir,
  })  : homePath = homePath ?? _defaultHomePath(),
        environment = environment ?? Platform.environment,
        readFile = readFile ?? _fsRead,
        listDir = listDir ?? _fsList {
    _vaultRepository = VaultRepository(
      identitiesDao: db.identitiesDao,
      encryptionEngine: encryptionEngine,
      vaultKeyService: vaultKeyService,
    );
  }

  /// `HOME` is absent on Windows, where the equivalent is `USERPROFILE`.
  static String _defaultHomePath() {
    final env = Platform.environment;
    return env['HOME'] ?? env['USERPROFILE'] ?? '/';
  }

  static String? _fsRead(String path) {
    try {
      final file = File(path);
      return file.existsSync() ? file.readAsStringSync() : null;
    } catch (_) {
      return null;
    }
  }

  static List<String>? _fsList(String dirPath) {
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return null;
      return dir.listSync().map((e) => p.basename(e.path)).toList()..sort();
    } catch (_) {
      return null;
    }
  }

  SshConfigResolver _resolver() {
    return SshConfigResolver(
      loader: (path) async => readFile(path),
      lister: (dir) async => listDir(dir),
      homePath: homePath,
      environment: environment,
    );
  }

  /// Resolves [content] for the import preview dialog without writing anything.
  Future<SshConfigResolution> previewConfig({
    required String path,
    required String content,
  }) {
    return _resolver().resolveContent(path, content);
  }

  /// Resolves and imports [content] according to [options].
  ///
  /// Throws [VaultLockedException] when identity files are requested and the
  /// vault is locked — the caller must surface this so the user can unlock.
  Future<SshConfigImportResult> importConfig({
    required String path,
    required String content,
    required SshConfigImportOptions options,
  }) async {
    final resolution = await _resolver().resolveContent(path, content);
    final warnings = [...resolution.warnings];
    final drafts = options.onlyAliases == null
        ? resolution.hosts
        : resolution.hosts
              .where((h) => options.onlyAliases!.contains(h.alias))
              .toList();

    // Fetch the DEK once, before any write, so a locked vault fails cleanly.
    SecretKey? dek;
    final hasKeyFiles =
        options.importIdentityFiles &&
        drafts.any((h) => h.identityFiles.isNotEmpty);
    if (hasKeyFiles) {
      dek = await vaultKeyService.getDek();
    }

    await db.workspacesDao.ensureWorkspaceExists(options.workspaceId);

    return db.transaction(() async {
      final existingHosts =
          await db.hostsDao.getHostsByWorkspace(options.workspaceId);
      final usedLabels = {for (final h in existingHosts) h.label};
      final existingByLabel = {for (final h in existingHosts) h.label: h};

      // ── Pass 1: identities + hosts (jump links land in pass 2) ──────────
      final keyHashToId = <String, String>{};
      if (hasKeyFiles) {
        final existing = await _vaultRepository.getAllIdentities(
          decryptSecrets: true,
          onlyPrivateKey: true,
          workspaceId: options.workspaceId,
        );
        for (final identity in existing) {
          if (identity.authType == 'key' && identity.privateKey != null) {
            keyHashToId[await _keyHash(identity.privateKey!)] = identity.id;
          }
        }
      }
      final identityIdByPath = <String, String>{};
      final reportedIdentityIssuePaths = <String>{};

      // hostIdByAlias is keyed by the config alias, unconditionally — pass 2
      // and pass 3 use it to find the host a jump link/tunnel belongs to.
      // hostIdByLowerLabel is keyed by the lowercased *label actually written
      // to the DB* (which diverges from the alias under `duplicate`), and is
      // only used by pass 2 to resolve what a ProxyJump target points at.
      final hostIdByAlias = <String, String>{};
      final hostIdByLowerLabel = <String, String>{};
      var hostsAdded = 0;
      var hostsUpdated = 0;
      var hostsSkipped = 0;
      var identitiesAdded = 0;

      for (final draft in drafts) {
        // Conflict policy by label. `skip` bails out before any identity
        // work so a skipped host never leaves an orphan vault entry behind.
        final conflicts = usedLabels.contains(draft.alias);
        if (conflicts && options.conflictPolicy == SshConfigConflictPolicy.skip) {
          hostsSkipped++;
          continue;
        }

        // Identity: first readable IdentityFile wins; dedupe by content hash.
        String? identityId;
        if (hasKeyFiles && draft.identityFiles.isNotEmpty) {
          for (final keyPath in draft.identityFiles) {
            final cached = identityIdByPath[keyPath];
            if (cached != null) {
              identityId = cached;
              break;
            }
            final keyContent = readFile(keyPath);
            if (keyContent == null || keyContent.trim().isEmpty) {
              if (reportedIdentityIssuePaths.add(keyPath)) {
                warnings.add(
                  SshConfigWarning(
                    message: 'IdentityFile not readable: $keyPath '
                        '(host ${draft.alias})',
                  ),
                );
              }
              continue;
            }
            if (_looksLikePublicKey(keyContent)) {
              if (reportedIdentityIssuePaths.add(keyPath)) {
                warnings.add(
                  SshConfigWarning(
                    message: 'IdentityFile is a public key, not a private key: '
                        '$keyPath (host ${draft.alias})',
                  ),
                );
              }
              continue;
            }
            if (_isEncryptedPrivateKey(keyContent)) {
              // Still imported — Terly just cannot use it without a
              // passphrase prompt, which does not exist yet at connect time.
              warnings.add(
                SshConfigWarning(
                  message: 'IdentityFile $keyPath is passphrase-protected; '
                      'Terly cannot decrypt it at connect time '
                      '(host ${draft.alias}).',
                  severity: SshConfigWarningSeverity.warning,
                ),
              );
            }
            final hash = await _keyHash(keyContent);
            final knownId = keyHashToId[hash];
            if (knownId != null) {
              identityId = knownId;
              identityIdByPath[keyPath] = knownId;
              break;
            }
            final newId = const Uuid().v4();
            final encrypted = await encryptionEngine.encrypt(
              plaintext: keyContent,
              secretKey: dek!,
            );
            await db.identitiesDao.insertIdentity(
              IdentitiesCompanion(
                id: Value(newId),
                workspaceId: Value(options.workspaceId),
                title: Value(p.basename(keyPath)),
                username: Value(draft.username ?? ''),
                authType: const Value('key'),
                privateKeyEncrypted: Value(encrypted),
                createdAt: Value(DateTime.now()),
              ),
            );
            identitiesAdded++;
            identityIdByPath[keyPath] = newId;
            keyHashToId[hash] = newId;
            identityId = newId;
            break;
          }
        }

        if (conflicts) {
          if (options.conflictPolicy == SshConfigConflictPolicy.overwrite) {
            final target = existingByLabel[draft.alias];
            if (target == null) {
              // Should not happen — usedLabels and existingByLabel are built
              // from the same snapshot — but no crash if it ever does.
              warnings.add(
                SshConfigWarning(
                  message: 'Host "${draft.alias}" marked as existing but '
                      'not found; skipped.',
                ),
              );
              hostsSkipped++;
              continue;
            }
            await db.hostsDao.updateHostById(
              target.id,
              HostsCompanion(
                hostname: Value(draft.hostname),
                username: Value(draft.username),
                port: Value(draft.port),
                // `identityId` is only null here because key import was off
                // or this host has no IdentityFile — not because the config
                // wants the link cleared. `Value(null)` would wipe an
                // existing host->identity link on every overwrite whenever
                // keys aren't being imported; absent leaves it untouched.
                identityId: identityId != null
                    ? Value(identityId)
                    : const Value.absent(),
                groupId: Value(options.groupId),
                // Cleared here; pass 2 re-writes it when the config has a
                // ProxyJump.
                jumpHostId: const Value(null),
              ),
            );
            if (options.importTunnels) {
              // Overwrite replaces the host's forwarding rules rather than
              // stacking duplicates next to the old ones.
              await (db.delete(db.portForwardRules)
                    ..where((t) => t.hostId.equals(target.id)))
                  .go();
            }
            hostIdByAlias[draft.alias] = target.id;
            hostIdByLowerLabel[draft.alias.toLowerCase()] = target.id;
            hostsUpdated++;
          } else {
            // duplicate
            final label = _freeLabel(usedLabels, draft.alias);
            final id = await _insertHost(
              options.workspaceId,
              label: label,
              draft: draft,
              identityId: identityId,
              groupId: options.groupId,
            );
            hostIdByAlias[draft.alias] = id;
            hostIdByLowerLabel[label.toLowerCase()] = id;
            hostsAdded++;
          }
        } else {
          final id = await _insertHost(
            options.workspaceId,
            label: draft.alias,
            draft: draft,
            identityId: identityId,
            groupId: options.groupId,
          );
          usedLabels.add(draft.alias);
          hostIdByAlias[draft.alias] = id;
          hostIdByLowerLabel[draft.alias.toLowerCase()] = id;
          hostsAdded++;
        }
      }

      // ── Pass 2: ProxyJump resolution ─────────────────────────────────────
      final jumpTargetIds = <String, String>{}; // lowercased target -> host id
      final existingByLowerLabel = {
        for (final h in existingHosts) h.label.toLowerCase(): h.id,
      };
      final existingByLowerHostname = {
        for (final h in existingHosts) h.hostname.toLowerCase(): h.id,
      };
      var jumpHostsAdded = 0;

      for (final draft in drafts) {
        final jump = draft.jumpHost;
        final hostId = hostIdByAlias[draft.alias];
        if (jump == null || hostId == null) continue;
        final key = jump.host.toLowerCase();
        final targetId = jumpTargetIds[key] ??
            hostIdByLowerLabel[key] ??
            existingByLowerLabel[key] ??
            existingByLowerHostname[key] ??
            (options.createMissingJumpHosts
                ? await _insertHost(
                    options.workspaceId,
                    label: jump.host,
                    draft: ResolvedSshConfig(
                      alias: jump.host,
                      hostname: jump.host,
                      username: jump.username,
                      port: jump.port ?? 22,
                    ),
                    identityId: null,
                    groupId: options.groupId,
                  )
                : null);
        if (targetId == null) {
          warnings.add(
            SshConfigWarning(
              message: 'ProxyJump target "${jump.host}" does not match any '
                  'imported or existing host; jump link skipped '
                  '(host ${draft.alias}).',
            ),
          );
          continue;
        }
        if (!jumpTargetIds.containsKey(key)) {
          jumpTargetIds[key] = targetId;
          if (hostIdByLowerLabel[key] == null &&
              existingByLowerLabel[key] == null &&
              existingByLowerHostname[key] == null) {
            jumpHostsAdded++;
          }
        }
        await db.hostsDao.updateHostById(
          hostId,
          HostsCompanion(jumpHostId: Value(targetId)),
        );
      }

      // ── Pass 3: port forwarding rules ────────────────────────────────────
      var tunnelsAdded = 0;
      if (options.importTunnels) {
        for (final draft in drafts) {
          final hostId = hostIdByAlias[draft.alias];
          if (hostId == null || draft.forwards.isEmpty) continue;
          for (final forward in draft.forwards) {
            await db.tunnelsDao.insertRule(
              PortForwardRulesCompanion(
                id: Value(const Uuid().v4()),
                hostId: Value(hostId),
                type: Value(forward.type),
                localPort: Value(forward.localPort),
                remoteHost: Value(forward.remoteHost),
                remotePort: Value(forward.remotePort),
                autoStart: const Value(false),
              ),
            );
            tunnelsAdded++;
          }
        }
      }

      return SshConfigImportResult(
        hostsAdded: hostsAdded,
        hostsUpdated: hostsUpdated,
        hostsSkipped: hostsSkipped,
        identitiesAdded: identitiesAdded,
        tunnelsAdded: tunnelsAdded,
        jumpHostsAdded: jumpHostsAdded,
        warnings: warnings,
      );
    });
  }

  Future<String> _insertHost(
    String workspaceId, {
    required String label,
    required ResolvedSshConfig draft,
    required String? identityId,
    required String? groupId,
  }) async {
    final id = const Uuid().v4();
    await db.hostsDao.insertHost(
      HostsCompanion(
        id: Value(id),
        workspaceId: Value(workspaceId),
        groupId: Value(groupId),
        identityId: Value(identityId),
        label: Value(label),
        hostname: Value(draft.hostname),
        username: Value(draft.username),
        port: Value(draft.port),
        protocol: const Value('ssh'),
        colorTag: const Value.absent(),
        jumpHostId: const Value.absent(),
        createdAt: Value(DateTime.now()),
      ),
    );
    return id;
  }

  /// Returns [base], or `base (2)`, `base (3)`, … — the first label not in
  /// [used] (which gains the returned label).
  String _freeLabel(Set<String> used, String base) {
    var label = base;
    var n = 2;
    while (!used.add(label)) {
      label = '$base ($n)';
      n++;
    }
    return label;
  }

  Future<String> _keyHash(String keyContent) async {
    final digest = await Sha256().hash(utf8.encode(keyContent.trim()));
    return base64.encode(digest.bytes);
  }

  bool _looksLikePublicKey(String content) {
    final trimmed = content.trim();
    if (trimmed.contains('PRIVATE KEY')) return false;
    const prefixes = [
      'ssh-rsa ',
      'ssh-ed25519 ',
      'ssh-dss ',
      'ecdsa-sha2-',
      'sk-ssh-',
    ];
    return prefixes.any(trimmed.startsWith);
  }

  /// True when [content] is a private key that needs a passphrase to
  /// decrypt. Terly has no connect-time passphrase prompt, so such keys are
  /// still imported but flagged with a warning rather than silently failing
  /// later.
  bool _isEncryptedPrivateKey(String content) {
    if (content.contains('Proc-Type: 4,ENCRYPTED')) return true;
    if (!content.contains('BEGIN OPENSSH PRIVATE KEY')) return false;
    try {
      final body = content.split('\n').where((line) {
        final trimmed = line.trim();
        return trimmed.isNotEmpty &&
            !trimmed.startsWith('-----BEGIN') &&
            !trimmed.startsWith('-----END');
      }).join();
      final bytes = base64.decode(body);

      // OpenSSH private key binary format: magic, then the cipher name as a
      // uint32-length-prefixed string. `none` means unencrypted.
      const magic = 'openssh-key-v1\x00';
      final magicBytes = utf8.encode(magic);
      if (bytes.length < magicBytes.length + 4) return false;
      for (var i = 0; i < magicBytes.length; i++) {
        if (bytes[i] != magicBytes[i]) return false;
      }
      var offset = magicBytes.length;
      final cipherLen = (bytes[offset] << 24) |
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];
      offset += 4;
      if (cipherLen < 0 || offset + cipherLen > bytes.length) return false;
      final cipherName = utf8.decode(bytes.sublist(offset, offset + cipherLen));
      return cipherName != 'none';
    } catch (_) {
      return false;
    }
  }
}
