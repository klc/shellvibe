import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/network/ssh_session_manager.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../../vault/presentation/notifiers/vault_notifier.dart';
import '../../data/live_template_runner_target.dart';
import '../../data/repositories/templates_repository.dart';
import '../../domain/models/template_model.dart';
import '../../domain/services/template_capture.dart';
import '../../domain/services/template_runner.dart';

part 'templates_notifier.g.dart';

@riverpod
TemplatesRepository templatesRepository(Ref ref) {
  return TemplatesRepository(ref.watch(templatesDaoProvider));
}

@riverpod
TemplateCapture templateCapture(Ref ref) => const TemplateCapture();

@riverpod
TemplateRunner templateRunner(Ref ref) => const TemplateRunner();

/// Kept alive deliberately: saving and running a template are fired from
/// toolbars that do not watch this provider, so an auto-disposing notifier
/// would be torn down mid-call and blow up assigning `state` after the await.
@Riverpod(keepAlive: true)
class TemplatesNotifier extends _$TemplatesNotifier {
  @override
  Future<List<TemplateModel>> build() async {
    final repo = ref.watch(templatesRepositoryProvider);
    return repo.getTemplatesByWorkspace(ref.watch(activeWorkspaceIdProvider));
  }

  /// Saves every open tab and split pane as a new template.
  ///
  /// Returns null when there is nothing open to capture.
  Future<TemplateModel?> saveCurrentLayout({
    required String name,
    String? description,
  }) async {
    final tabsState = ref.read(terminalTabsProvider);
    if (tabsState.tabs.isEmpty) return null;

    final template = ref
        .read(templateCaptureProvider)
        .capture(
          workspaceId: ref.read(activeWorkspaceIdProvider),
          name: name,
          description: description,
          tabs: tabsState.tabs,
          activeTabId: tabsState.activeTabId,
        );

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(templatesRepositoryProvider);
      await repo.addTemplate(template);
      return repo.getTemplatesByWorkspace(ref.read(activeWorkspaceIdProvider));
    });

    return template;
  }

  Future<void> updateTemplate(TemplateModel template) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(templatesRepositoryProvider);
      await repo.updateTemplate(template);
      return repo.getTemplatesByWorkspace(ref.read(activeWorkspaceIdProvider));
    });
  }

  Future<void> renameTemplate(TemplateModel template, String name) {
    return updateTemplate(template.copyWith(name: name));
  }

  Future<void> deleteTemplate(String id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(templatesRepositoryProvider);
      await repo.deleteTemplate(id);
      return repo.getTemplatesByWorkspace(ref.read(activeWorkspaceIdProvider));
    });
  }

  /// Recreates [template]'s layout **in addition to** whatever is already open;
  /// nothing currently on screen is closed.
  ///
  /// [resolveIdentity] decrypts a host's stored credentials and [onHostKeyPrompt]
  /// carries host key verification, so both stay on the UI layer that can show
  /// the dialogs.
  Future<TemplateRunResult> runTemplate(
    TemplateModel template, {
    required TemplateIdentityResolver resolveIdentity,
    HostKeyPromptCallback? onHostKeyPrompt,
  }) async {
    final runner = ref.read(templateRunnerProvider);
    final hosts = await ref.read(hostsProvider.future);
    final hostsById = <String, HostModel>{
      for (final host in hosts) host.id: host,
    };

    // Panes that use stored credentials must not connect behind a locked vault
    // — the same gate the launch shell runs through. Refusing the whole run
    // rather than the credentialed panes keeps a half-built layout off screen.
    if (runner.requiresUnlockedVault(template, hostsById)) {
      final vault = ref.read(vaultProvider);
      if (vault.isLoading && !vault.hasValue ||
          vault.value?.status == VaultStatus.locked) {
        return const TemplateRunResult(
          openedPanes: 0,
          warnings: [
            'Vault is locked — unlock it to run templates that use stored '
                'credentials.',
          ],
        );
      }
    }

    final notifier = ref.read(terminalTabsProvider.notifier);
    return runner.run(
      template,
      target: LiveTemplateRunnerTarget(
        notifier: notifier,
        readActiveTabId: () => ref.read(terminalTabsProvider).activeTabId,
        onHostKeyPrompt: onHostKeyPrompt,
      ),
      hostsById: hostsById,
      resolveIdentity: resolveIdentity,
      supportsLocalShell: supportsLocalShell,
    );
  }
}
