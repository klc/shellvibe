import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../shared/database/app_database.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../../../shared/storage/secure_storage_service.dart';
import '../../../workspaces/domain/models/workspace_model.dart';
import '../../data/mcp_providers.dart';
import '../../data/mcp_server_controller.dart';
import '../../data/repositories/mcp_repository_providers.dart';

part 'mcp_settings_notifier.g.dart';

/// Everything the AI Access settings screen needs to render: the master
/// switch, the running server's own view of itself, the registered client
/// list, and the numeric knobs the user can tune.
class McpSettingsState {
  final bool masterEnabled;

  /// A snapshot of [McpServerController.isRunning]/`.port` taken on
  /// [McpSettingsNotifier.build] and refreshed explicitly after this
  /// notifier's own [McpSettingsNotifier.setMasterEnabled] and
  /// [McpSettingsNotifier.panic] calls — not a live stream. The controller
  /// exposes plain getters, not a change notifier, and this feature does not
  /// own that file, so a stop triggered from outside this notifier (e.g. the
  /// vault-lock listener in `mcp_server_controller.dart`) will not repaint
  /// this screen until it next rebuilds. Acceptable for a settings surface
  /// the user is actively looking at when they flip the switch; not a
  /// promise of real-time accuracy while the screen sits unfocused.
  final bool serverRunning;
  final int? serverPort;
  final List<McpClient> clients;
  final int defaultCommandTimeoutSeconds;
  final int outputCapBytes;
  final int sessionIdleTimeoutMinutes;
  final int auditRetentionDays;

  const McpSettingsState({
    required this.masterEnabled,
    required this.serverRunning,
    required this.serverPort,
    required this.clients,
    required this.defaultCommandTimeoutSeconds,
    required this.outputCapBytes,
    required this.sessionIdleTimeoutMinutes,
    required this.auditRetentionDays,
  });

  McpSettingsState copyWith({
    bool? masterEnabled,
    bool? serverRunning,
    int? serverPort,
    bool clearServerPort = false,
    List<McpClient>? clients,
    int? defaultCommandTimeoutSeconds,
    int? outputCapBytes,
    int? sessionIdleTimeoutMinutes,
    int? auditRetentionDays,
  }) {
    return McpSettingsState(
      masterEnabled: masterEnabled ?? this.masterEnabled,
      serverRunning: serverRunning ?? this.serverRunning,
      serverPort: clearServerPort ? null : (serverPort ?? this.serverPort),
      clients: clients ?? this.clients,
      defaultCommandTimeoutSeconds:
          defaultCommandTimeoutSeconds ?? this.defaultCommandTimeoutSeconds,
      outputCapBytes: outputCapBytes ?? this.outputCapBytes,
      sessionIdleTimeoutMinutes:
          sessionIdleTimeoutMinutes ?? this.sessionIdleTimeoutMinutes,
      auditRetentionDays: auditRetentionDays ?? this.auditRetentionDays,
    );
  }
}

/// The subset of [McpSettingsState] that is actually persisted. Server
/// liveness and the client list are not stored here — they are read fresh
/// from [McpServerController] and [McpClientRepository] on every [build],
/// which is the only source of truth for either.
class _PersistedMcpSettings {
  final bool masterEnabled;
  final int defaultCommandTimeoutSeconds;
  final int outputCapBytes;
  final int sessionIdleTimeoutMinutes;
  final int auditRetentionDays;

  const _PersistedMcpSettings({
    this.masterEnabled = false,
    this.defaultCommandTimeoutSeconds = 60,
    this.outputCapBytes = 100 * 1024,
    this.sessionIdleTimeoutMinutes = 30,
    this.auditRetentionDays = 90,
  });

  _PersistedMcpSettings copyWith({
    bool? masterEnabled,
    int? defaultCommandTimeoutSeconds,
    int? outputCapBytes,
    int? sessionIdleTimeoutMinutes,
    int? auditRetentionDays,
  }) {
    return _PersistedMcpSettings(
      masterEnabled: masterEnabled ?? this.masterEnabled,
      defaultCommandTimeoutSeconds:
          defaultCommandTimeoutSeconds ?? this.defaultCommandTimeoutSeconds,
      outputCapBytes: outputCapBytes ?? this.outputCapBytes,
      sessionIdleTimeoutMinutes:
          sessionIdleTimeoutMinutes ?? this.sessionIdleTimeoutMinutes,
      auditRetentionDays: auditRetentionDays ?? this.auditRetentionDays,
    );
  }

  Map<String, Object?> toJson() => {
    'masterEnabled': masterEnabled,
    'defaultCommandTimeoutSeconds': defaultCommandTimeoutSeconds,
    'outputCapBytes': outputCapBytes,
    'sessionIdleTimeoutMinutes': sessionIdleTimeoutMinutes,
    'auditRetentionDays': auditRetentionDays,
  };

  factory _PersistedMcpSettings.fromJson(Map<String, dynamic> json) {
    const fallback = _PersistedMcpSettings();
    return _PersistedMcpSettings(
      masterEnabled: json['masterEnabled'] as bool? ?? fallback.masterEnabled,
      defaultCommandTimeoutSeconds:
          json['defaultCommandTimeoutSeconds'] as int? ??
          fallback.defaultCommandTimeoutSeconds,
      outputCapBytes: json['outputCapBytes'] as int? ?? fallback.outputCapBytes,
      sessionIdleTimeoutMinutes:
          json['sessionIdleTimeoutMinutes'] as int? ??
          fallback.sessionIdleTimeoutMinutes,
      auditRetentionDays:
          json['auditRetentionDays'] as int? ?? fallback.auditRetentionDays,
    );
  }
}

/// Reads and writes [_PersistedMcpSettings], one JSON blob per workspace.
///
/// **Why this does not go through `SettingsRepository`/`AppSettingsModel`.**
/// Those own one flat, single-workspace JSON blob (`shellvibe_app_settings`)
/// and are off limits for this feature by design. AI Access settings are
/// inherently per-workspace — a client's visibility follows the workspace it
/// was registered against, not whichever workspace the UI happens to be
/// showing — which `AppSettingsModel`'s single
/// `activeWorkspaceId` field has no room to express without widening that
/// model into a per-workspace map — a change to a file this feature does not
/// own. Rather than force that edit, this keeps its own key per workspace
/// (`mcp_settings_<workspaceId>`) in the same [SecureStorageService] instance
/// `SettingsRepository` already uses, following the exact
/// read-JSON-blob/write-JSON-blob shape that file established. Secure storage
/// (not a plain preferences store) is deliberate too: even though nothing
/// stored here is a secret by itself, it keeps this feature from introducing
/// a second local-storage mechanism into the app for no reason.
class _McpSettingsStore {
  final SecureStorageService _storage;

  const _McpSettingsStore(this._storage);

  String _keyFor(String workspaceId) => 'mcp_settings_$workspaceId';

  Future<_PersistedMcpSettings> load(String workspaceId) async {
    final raw = await _storage.read(key: _keyFor(workspaceId));
    if (raw == null || raw.isEmpty) return const _PersistedMcpSettings();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return _PersistedMcpSettings.fromJson(json);
    } catch (_) {
      // A corrupted or foreign-shaped blob must not crash Settings; it just
      // falls back to the safest defaults (master switch off).
      return const _PersistedMcpSettings();
    }
  }

  Future<void> save(String workspaceId, _PersistedMcpSettings settings) {
    return _storage.write(
      key: _keyFor(workspaceId),
      value: jsonEncode(settings.toJson()),
    );
  }
}

/// Bounds enforced on the user-tunable numeric settings. Values outside
/// these ranges are clamped rather than rejected, so a slider or stepper
/// widget can never hand this notifier something that breaks a downstream
/// assumption elsewhere in the MCP layer.
abstract final class McpSettingsBounds {
  /// Upper bound matches `PersistentShellSession._kMaxTimeout` — the hard
  /// ceiling `run_command` itself enforces per call
  /// (`core/mcp/shell/persistent_shell_session.dart`), so this setting can
  /// never promise a default the shell layer would refuse to honor.
  static const int minCommandTimeoutSeconds = 5;
  static const int maxCommandTimeoutSeconds = 600;

  static const int minOutputCapBytes = 10 * 1024;
  static const int maxOutputCapBytes = 5 * 1024 * 1024;

  static const int minSessionIdleTimeoutMinutes = 1;
  static const int maxSessionIdleTimeoutMinutes = 180;

  static const int minAuditRetentionDays = 1;
  static const int maxAuditRetentionDays = 365;
}

/// Owns the current workspace's AI-access settings: the master switch, the
/// live server/client view, and the tunable numeric knobs.
///
/// Flipping the master switch is the one place this notifier reaches outside
/// its own storage: on -> [McpServerController.start], off ->
/// [McpServerController.stop]. Every other setter here only persists a value
/// for whatever later reads it (the tool dispatcher's per-call defaults).
@riverpod
class McpSettingsNotifier extends _$McpSettingsNotifier {
  String _workspaceId = '';

  @override
  Future<McpSettingsState> build() async {
    final workspaceId = ref.watch(activeWorkspaceIdProvider);
    _workspaceId = workspaceId;

    final store = _McpSettingsStore(ref.watch(secureStorageServiceProvider));
    final persisted = await store.load(workspaceId);

    final controller = ref.watch(mcpServerControllerProvider);
    final clients = await ref
        .watch(mcpClientRepositoryProvider)
        .listClients(workspaceId);

    // The persisted switch is the user's standing instruction, not a record
    // of what happened to be running last time. Reading it without acting on
    // it leaves the switch showing "on" after every app launch while nothing
    // is listening — the settings screen reports a server that does not
    // exist, and the bridge fails with "ShellVibe is not running" against an
    // app that is plainly open. Reconciling is scheduled rather than awaited
    // so `build` stays synchronous-ish and cannot deadlock on a provider it
    // is itself constructing.
    if (persisted.masterEnabled && !controller.isRunning) {
      Future<void>.microtask(ensureServerMatchesSetting);
    }

    return McpSettingsState(
      masterEnabled: persisted.masterEnabled,
      serverRunning: controller.isRunning,
      serverPort: controller.port,
      clients: clients,
      defaultCommandTimeoutSeconds: persisted.defaultCommandTimeoutSeconds,
      outputCapBytes: persisted.outputCapBytes,
      sessionIdleTimeoutMinutes: persisted.sessionIdleTimeoutMinutes,
      auditRetentionDays: persisted.auditRetentionDays,
    );
  }

  /// Brings the running server in line with the persisted master switch.
  ///
  /// Called at boot and again whenever the vault becomes available: the
  /// server cannot start behind a locked vault (it resolves SSH credentials),
  /// so an app that launches locked must still come up serving once the user
  /// unlocks, without them having to visit this screen and toggle the switch
  /// by hand.
  Future<void> ensureServerMatchesSetting() async {
    final current = state.value;
    if (current == null) return;

    final controller = ref.read(mcpServerControllerProvider);
    if (current.masterEnabled == controller.isRunning) return;

    try {
      if (current.masterEnabled) {
        await controller.start();
      } else {
        await controller.stop();
      }
    } on Object {
      // A vault that is still locked, or a port range with nothing free, is
      // a reason to stay stopped — not to crash the settings screen. The
      // state below reports what is actually true either way, so the switch
      // and the status line cannot disagree with reality.
    }

    if (!ref.mounted) return;
    state = AsyncValue.data(
      current.copyWith(
        serverRunning: controller.isRunning,
        serverPort: controller.port,
        clearServerPort: !controller.isRunning,
      ),
    );
  }

  /// Flips the master switch: on starts the MCP HTTP server for this
  /// workspace, off stops it. Default is OFF for every workspace that has
  /// never set this — see [_PersistedMcpSettings]'s default constructor —
  /// so a user who never opens this screen never runs an agent-facing
  /// server.
  Future<void> setMasterEnabled(bool enabled) async {
    final current = state.value;
    if (current == null || current.masterEnabled == enabled) return;

    final controller = ref.read(mcpServerControllerProvider);
    if (enabled) {
      await controller.start();
    } else {
      await controller.stop();
    }

    await _persist(current, masterEnabled: enabled);
    state = AsyncValue.data(
      current.copyWith(
        masterEnabled: enabled,
        serverRunning: controller.isRunning,
        serverPort: controller.port,
        clearServerPort: !controller.isRunning,
      ),
    );
  }

  Future<void> setDefaultCommandTimeoutSeconds(int seconds) async {
    final clamped = seconds
        .clamp(
          McpSettingsBounds.minCommandTimeoutSeconds,
          McpSettingsBounds.maxCommandTimeoutSeconds,
        )
        .toInt();
    await _updateAndPersist(
      (s) => s.copyWith(defaultCommandTimeoutSeconds: clamped),
    );
  }

  Future<void> setOutputCapBytes(int bytes) async {
    final clamped = bytes
        .clamp(
          McpSettingsBounds.minOutputCapBytes,
          McpSettingsBounds.maxOutputCapBytes,
        )
        .toInt();
    await _updateAndPersist((s) => s.copyWith(outputCapBytes: clamped));
  }

  Future<void> setSessionIdleTimeoutMinutes(int minutes) async {
    final clamped = minutes
        .clamp(
          McpSettingsBounds.minSessionIdleTimeoutMinutes,
          McpSettingsBounds.maxSessionIdleTimeoutMinutes,
        )
        .toInt();
    await _updateAndPersist(
      (s) => s.copyWith(sessionIdleTimeoutMinutes: clamped),
    );
  }

  Future<void> setAuditRetentionDays(int days) async {
    final clamped = days
        .clamp(
          McpSettingsBounds.minAuditRetentionDays,
          McpSettingsBounds.maxAuditRetentionDays,
        )
        .toInt();
    await _updateAndPersist((s) => s.copyWith(auditRetentionDays: clamped));
  }

  /// Registers a new client for the current workspace and returns its raw
  /// bearer token. The caller (the settings screen) is responsible for
  /// showing it exactly once — this notifier never stores or re-exposes it,
  /// mirroring [McpClientRepository.createClient]'s own contract.
  Future<String> addClient(String name) async {
    final repo = ref.read(mcpClientRepositoryProvider);
    final (:clientId, :rawToken) = _asNamedRecord(
      await repo.createClient(workspaceId: _workspaceId, name: name),
    );
    await _refreshClients();
    return rawToken;
  }

  Future<void> revokeClient(String clientId) async {
    await ref.read(mcpClientRepositoryProvider).revokeClient(clientId);
    await _refreshClients();
  }

  /// Cuts every form of agent access in one call: closes every open MCP
  /// session, revokes every host grant, drops every remembered approval,
  /// revokes every client token across every workspace, and stops the
  /// server.
  ///
  /// This asks no confirmation question — a kill switch that hesitates is
  /// not a kill switch. The caller (the settings screen's destructive
  /// button) is where any "are you sure" UX belongs, if the product ever
  /// wants one; this method itself always executes immediately and
  /// unconditionally. It is also the single implementation of panic in this
  /// codebase: the AI Activity panel's own panic button calls this rather
  /// than re-closing sessions or re-revoking grants itself, so there is
  /// exactly one place that has to get "cut everything, nothing left
  /// half-revoked" right.
  ///
  /// Client revocation is deliberately not scoped to [_workspaceId]: a user
  /// hitting this button wants every agent shut out, not just the one
  /// belonging to whichever workspace Settings happened to be showing. Grant
  /// and approval revocation are already global at the repository layer
  /// ([McpGrantRepository.revokeEverything], [McpApprovalRepository.revokeAll])
  /// for the same reason.
  Future<void> panic() async {
    await ref.read(mcpSessionPoolProvider).closeAll();
    await ref.read(mcpGrantRepositoryProvider).revokeEverything();
    await ref.read(mcpApprovalRepositoryProvider).revokeAll();

    final clientRepo = ref.read(mcpClientRepositoryProvider);
    final workspaces = await ref.read(workspacesProvider.future);
    for (final WorkspaceModel workspace in workspaces) {
      final clients = await clientRepo.listClients(workspace.id);
      for (final client in clients) {
        if (client.revokedAt == null) {
          await clientRepo.revokeClient(client.id);
        }
      }
    }

    await ref.read(mcpServerControllerProvider).stop();

    final current = state.value;
    if (current != null) {
      await _persist(current, masterEnabled: false);
    }
    ref.invalidateSelf();
  }

  Future<void> _refreshClients() async {
    final current = state.value;
    if (current == null) return;
    final clients = await ref
        .read(mcpClientRepositoryProvider)
        .listClients(_workspaceId);
    state = AsyncValue.data(current.copyWith(clients: clients));
  }

  Future<void> _updateAndPersist(
    McpSettingsState Function(McpSettingsState) apply,
  ) async {
    final current = state.value;
    if (current == null) return;
    final updated = apply(current);
    await _persist(
      updated,
      masterEnabled: updated.masterEnabled,
      defaultCommandTimeoutSeconds: updated.defaultCommandTimeoutSeconds,
      outputCapBytes: updated.outputCapBytes,
      sessionIdleTimeoutMinutes: updated.sessionIdleTimeoutMinutes,
      auditRetentionDays: updated.auditRetentionDays,
    );
    state = AsyncValue.data(updated);
  }

  Future<void> _persist(
    McpSettingsState base, {
    bool? masterEnabled,
    int? defaultCommandTimeoutSeconds,
    int? outputCapBytes,
    int? sessionIdleTimeoutMinutes,
    int? auditRetentionDays,
  }) {
    final store = _McpSettingsStore(ref.read(secureStorageServiceProvider));
    return store.save(
      _workspaceId,
      _PersistedMcpSettings(
        masterEnabled: masterEnabled ?? base.masterEnabled,
        defaultCommandTimeoutSeconds:
            defaultCommandTimeoutSeconds ?? base.defaultCommandTimeoutSeconds,
        outputCapBytes: outputCapBytes ?? base.outputCapBytes,
        sessionIdleTimeoutMinutes:
            sessionIdleTimeoutMinutes ?? base.sessionIdleTimeoutMinutes,
        auditRetentionDays: auditRetentionDays ?? base.auditRetentionDays,
      ),
    );
  }

  /// [McpClientRepository.createClient] returns a positional record; this
  /// gives the two fields names at the one call site that needs them, purely
  /// for readability.
  ({String clientId, String rawToken}) _asNamedRecord(
    (String, String) record,
  ) => (clientId: record.$1, rawToken: record.$2);
}
