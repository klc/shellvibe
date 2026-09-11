import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/constants/app_constants.dart';
import '../../domain/services/update_check_service.dart';

/// Address a security researcher is asked to use, kept in one place so
/// `SECURITY.md` and the application never drift apart.
const String kSecurityContact = 'security@shellvibe.dev';

/// Build identity, the update check, and the third-party licence notices.
///
/// The licence page is not decoration. Most of the dependency tree is MIT,
/// BSD or Apache-2.0, and every one of those licences asks that its notice
/// travel with the distributed binary; `LICENSE` promises exactly that on the
/// project's behalf. Flutter's [showLicensePage] collects the notices the
/// build actually linked, which is the only list that cannot go stale.
final class AboutSettingsSection extends ConsumerStatefulWidget {
  const AboutSettingsSection({super.key});

  @override
  ConsumerState<AboutSettingsSection> createState() =>
      _AboutSettingsSectionState();
}

class _AboutSettingsSectionState extends ConsumerState<AboutSettingsSection> {
  bool _checking = false;
  UpdateCheckResult? _result;

  String get _buildIdentity =>
      '${AppConstants.appName} ${AppConstants.appVersion} · ${_platformLabel()}';

  static String _platformLabel() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS => 'macOS',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iOS',
      _ => 'unknown',
    };
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _checking = true;
      _result = null;
    });
    final result = await ref.read(updateCheckServiceProvider).check();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _result = result;
    });
  }

  Future<void> _open(String url) async {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return;
    await launchUrl(parsed, mode: LaunchMode.externalApplication);
  }

  void _copy(String value, String toast) {
    Clipboard.setData(ClipboardData(text: value));
    ShadToaster.of(context).show(ShadToast(description: Text(toast)));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShadCard(
          child: _cardBody(
            children: [
              ListTile(
                key: const Key('about_build_identity'),
                leading: Icon(LucideIcons.info, color: tokens.brand),
                title: Text(AppConstants.appName),
                subtitle: Text(
                  '${AppConstants.appVersion} · ${_platformLabel()}',
                  style: shellvibeMono(
                    context,
                    size: 11,
                    color: tokens.textMuted,
                  ),
                ),
                // The first thing a bug report asks for, one tap away.
                trailing: ShellVibeIconButton(
                  key: const Key('about_copy_build_identity'),
                  icon: LucideIcons.copy,
                  tooltip: 'Copy version and platform',
                  onPressed: () =>
                      _copy(_buildIdentity, 'Build identity copied.'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ShadCard(
          child: _cardBody(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: Icon(LucideIcons.download, color: tokens.brand),
                title: const Text('Updates'),
                subtitle: Text(
                  'Checked only when you ask. Nothing is sent about this '
                  'installation.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
                ),
                trailing: ShellVibeButton(
                  key: const Key('about_check_for_updates'),
                  label: 'Check for updates',
                  onPressed: _checkForUpdates,
                  busy: _checking,
                ),
              ),
              if (_result != null) ...[
                const Divider(),
                _buildUpdateResult(context, tokens, _result!),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        ShadCard(
          child: _cardBody(
            children: [
              ListTile(
                key: const Key('about_open_licenses'),
                leading: Icon(LucideIcons.scale, color: tokens.brand),
                title: const Text('Open source licenses'),
                subtitle: Text(
                  'Notices for the packages this build was compiled with.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
                ),
                trailing: const Icon(LucideIcons.chevronRight, size: 16),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: AppConstants.appName,
                  applicationVersion: AppConstants.appVersion,
                  applicationLegalese:
                      '© 2026 Mustafa Kılıç. ShellVibe is source available '
                      'under the Functional Source License 1.1 (FSL-1.1-ALv2); '
                      'the ShellVibe name and marks are not covered by it.\n'
                      'Third-party components remain under their own licenses, '
                      'listed here.',
                ),
              ),
              const Divider(),
              ListTile(
                key: const Key('about_security_contact'),
                leading: Icon(LucideIcons.shieldAlert, color: tokens.brand),
                title: const Text('Report a security issue'),
                subtitle: Text(
                  'Found something that puts a user\'s servers at risk? '
                  'Write to $kSecurityContact rather than opening a public '
                  'issue.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
                ),
                trailing: ShellVibeIconButton(
                  key: const Key('about_copy_security_contact'),
                  icon: LucideIcons.copy,
                  tooltip: 'Copy address',
                  onPressed: () =>
                      _copy(kSecurityContact, 'Security address copied.'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUpdateResult(
    BuildContext context,
    ShellVibeTokens tokens,
    UpdateCheckResult result,
  ) {
    final bodySmall = Theme.of(context).textTheme.bodySmall;

    return switch (result) {
      UpdateAvailable(:final version, :final url) => ListTile(
        key: const Key('about_update_available'),
        leading: Icon(LucideIcons.circleArrowUp, color: tokens.brand),
        title: Text('Version $version is available'),
        subtitle: Text(
          'You are running ${AppConstants.appVersion}.',
          style: bodySmall?.copyWith(color: tokens.textMuted),
        ),
        trailing: ShellVibeButton.secondary(
          key: const Key('about_open_release'),
          label: 'Open release',
          onPressed: () => _open(url),
        ),
      ),
      UpToDate(:final version) => ListTile(
        key: const Key('about_up_to_date'),
        leading: Icon(LucideIcons.circleCheck, color: tokens.success),
        title: Text('$version is the newest release.'),
      ),
      UpdateCheckUnavailable(:final reason) => ListTile(
        key: const Key('about_update_unavailable'),
        leading: Icon(LucideIcons.circleAlert, color: tokens.textMuted),
        title: Text(
          reason,
          style: bodySmall?.copyWith(color: tokens.textSecondary),
        ),
      ),
    };
  }
}

/// A card's contents, with the [Material] the [ListTile]s inside need.
///
/// `ShadCard` paints its own background through a `DecoratedBox`, which sits
/// between a `ListTile` and the nearest `Material` and would swallow the
/// tile's ink splashes — Flutter asserts on exactly this arrangement. A
/// transparent `Material` inside the card gives the tiles somewhere to paint
/// without adding a second background.
Widget _cardBody({
  required List<Widget> children,
  CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
}) => Material(
  type: MaterialType.transparency,
  child: Column(crossAxisAlignment: crossAxisAlignment, children: children),
);
