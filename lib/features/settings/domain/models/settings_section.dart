import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// The wireframe's settings sections, in navigation order.
enum SettingsSection {
  appearance(
    'Appearance',
    LucideIcons.palette,
    'Theme and chrome palette. Applies immediately.',
  ),
  terminal(
    'Terminal',
    LucideIcons.squareTerminal,
    'Font, palette and cursor behaviour. Applies to open sessions '
        'immediately.',
  ),
  security(
    'Security',
    LucideIcons.shieldCheck,
    'Clipboard, host keys and biometrics.',
  ),
  deviceLink(
    'Device Link',
    LucideIcons.smartphone,
    'Phones paired to this machine.',
  ),
  aiAccess(
    'AI Access',
    LucideIcons.bot,
    'AI agent access, registered clients, and the kill switch.',
  ),
  vault('Vault', LucideIcons.lockKeyhole, 'Master password and auto-lock.'),
  account(
    'Account',
    LucideIcons.circleUser,
    'Optional. Only cloud backup needs one.',
  ),

  /// Copies the user asks for: a file on disk, and revisions in the account.
  backup(
    'Backup',
    LucideIcons.cloudUpload,
    'Copies you take: to a file, or to your account.',
  ),

  /// The thing that runs on its own. Split from Backup because they are two
  /// features that happened to share a screen: one is a snapshot taken at a
  /// moment the user chose, the other writes to the account in both
  /// directions on its own schedule.
  sync(
    'Sync',
    LucideIcons.cloudCog,
    'Keeps your devices in step on its own, in both directions.',
  ),
  about('About', LucideIcons.info, 'Version, updates and licenses.');

  const SettingsSection(this.label, this.icon, this.meta);

  final String label;
  final IconData icon;

  /// The one-line description under a section's title.
  final String meta;

  /// The section a `/settings/<name>` path points at, or null when the path
  /// segment names nothing — a stale deep link should land on the index
  /// rather than on a guessed section.
  static SettingsSection? byName(String? name) {
    if (name == null) return null;
    for (final section in values) {
      if (section.name == name) return section;
    }
    return null;
  }
}

/// How the sections are grouped on the compact index.
///
/// Ten flat rows is the same wall of switches the one-page phone layout was,
/// only shorter; the groups are what let someone look for "the cloud one"
/// without reading all ten labels.
enum SettingsSectionGroup {
  general('General', [SettingsSection.appearance, SettingsSection.terminal]),
  security('Security', [SettingsSection.security, SettingsSection.vault]),
  connections('Connections', [
    SettingsSection.deviceLink,
    SettingsSection.aiAccess,
  ]),
  cloud('Cloud', [
    SettingsSection.account,
    SettingsSection.backup,
    SettingsSection.sync,
  ]),
  app('App', [SettingsSection.about]);

  const SettingsSectionGroup(this.label, this.sections);

  final String label;
  final List<SettingsSection> sections;
}
