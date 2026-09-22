import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/constants/app_constants.dart';
import '../../domain/models/settings_section.dart';
import '../widgets/settings_section_view.dart';

export '../../domain/models/settings_section.dart'
    show SettingsSection, SettingsSectionGroup;

/// Settings, at both tiers.
///
/// Which section is open lives in the route rather than in this widget, so a
/// section is linkable, survives a rebuild, and means the same thing to both
/// layouts: `/settings` is the index, `/settings/<name>` is one section.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.section});

  /// The open section, or null for the index. The wide layout has no index —
  /// its nav column is always on screen — so there null means the first
  /// section.
  final SettingsSection? section;

  @override
  Widget build(BuildContext context) {
    final tierTokens = ShellVibeTokens.resolve(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // The section nav is this module's context column, so it appears at the
        // same tier every other module's does; below it the same sections
        // become an index that opens one section at a time.
        final showSectionNav =
            constraints.maxWidth >= tierTokens.breakpointMedium;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: showSectionNav
              ? _buildWideLayout(context)
              : (section == null
                    ? _buildIndex(context)
                    : _SettingsSectionPage(section: section!)),
        );
      },
    );
  }

  /// Phone layout: an index of sections, each one a page of its own.
  ///
  /// The sections used to be concatenated into a single scroll here. That put
  /// every control the app has on one page, and cloud backup and sync made it
  /// long enough that finding anything meant scrolling past everything.
  Widget _buildIndex(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          const ShellVibePageHeader(
            icon: LucideIcons.settings2,
            title: 'Settings',
            description: 'Application, terminal, security and sync controls',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                for (final group in SettingsSectionGroup.values)
                  if (group.availableSections.isNotEmpty) ...[
                    ShellVibeSectionLabel(label: group.label),
                    _buildIndexCard(context, [
                      for (final entry in group.availableSections)
                        _IndexTile(
                          itemKey: Key('settings_section_${entry.name}'),
                          icon: entry.icon,
                          label: entry.label,
                          meta: entry.meta,
                          onTap: () => GoRouter.maybeOf(
                            context,
                          )?.go('/settings/${entry.name}'),
                        ),
                    ]),
                    const SizedBox(height: 4),
                  ],
                // Tunnels, snippets and workspaces are not among the five
                // mobile tabs, so this is their entry point.
                ..._buildToolsGroup(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Wide layout: the section list is a slab of its own, exactly like a
  /// module's context column, so Settings reads as part of the same shell
  /// rather than a page nested inside it.
  Widget _buildWideLayout(BuildContext context) {
    final active = section ?? SettingsSection.values.first;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionNav(context),
        Expanded(
          child: ShellVibePanel(
            gradientExtent: 200,
            child: Column(
              children: [
                ShellVibeWorkToolbar(title: active.label, meta: active.meta),
                Expanded(child: SettingsSectionView(section: active)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// A group of index rows in one card, hairline-separated.
  Widget _buildIndexCard(BuildContext context, List<Widget> tiles) {
    final tokens = ShellVibeTokens.resolve(context);
    return ShadCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: tokens.border,
                indent: 52,
              ),
            tiles[i],
          ],
        ],
      ),
    );
  }

  Widget _buildSectionNav(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final active = section ?? SettingsSection.values.first;
    return ShellVibePanel(
      width: tokens.contextColumnWidth,
      gradientExtent: 140,
      margin: EdgeInsets.only(right: tokens.panelGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ShellVibeSectionLabel(
                  label: AppConstants.appName,
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 6),
                Text(
                  'Settings',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              children: [
                // The wide nav keeps the same grouping as the phone index, so
                // the two layouts agree about what belongs with what.
                for (final group in SettingsSectionGroup.values)
                  if (group.availableSections.isNotEmpty) ...[
                    ShellVibeSectionLabel(label: group.label),
                    for (final entry in group.availableSections)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: ShellVibeNavItem(
                          itemKey: Key('settings_section_${entry.name}'),
                          icon: entry.icon,
                          label: entry.label,
                          selected: entry == active,
                          onTap: () => GoRouter.maybeOf(
                            context,
                          )?.go('/settings/${entry.name}'),
                        ),
                      ),
                  ],
              ],
            ),
          ),
          // Build identity at the foot of the column: it is the first thing a
          // bug report asks for, and About is one click away from here anyway.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: tokens.textPrimary.withValues(alpha: 0.02),
              border: Border(
                top: BorderSide(
                  color: tokens.textPrimary.withValues(alpha: 0.05),
                ),
              ),
            ),
            child: Text(
              '${AppConstants.appName} ${AppConstants.appVersion}\n'
              '${platformLabel()}',
              style: shellvibeMono(
                context,
                size: 10.5,
                color: tokens.textSubtle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Secondary modules that have no mobile tab of their own.
  List<Widget> _buildToolsGroup(BuildContext context) {
    return [
      ShellVibeSectionLabel(label: 'Tools'),
      _buildIndexCard(context, [
        for (final entry in const [
          (
            '/tunnels',
            'Tunnels',
            LucideIcons.network,
            'Local and remote port forwards.',
          ),
          (
            '/snippets',
            'Snippets & Runbooks',
            LucideIcons.zap,
            'Saved commands and multi-step runbooks.',
          ),
          (
            '/workspaces',
            'Workspaces',
            LucideIcons.panelTop,
            'Saved session layouts.',
          ),
        ])
          _IndexTile(
            itemKey: Key('settings_tool_${entry.$1.substring(1)}'),
            icon: entry.$3,
            label: entry.$2,
            meta: entry.$4,
            onTap: () => GoRouter.maybeOf(context)?.go(entry.$1),
          ),
      ]),
    ];
  }
}

/// One row of the compact index: what the section is, and that it opens.
class _IndexTile extends StatelessWidget {
  const _IndexTile({
    required this.itemKey,
    required this.icon,
    required this.label,
    required this.meta,
    required this.onTap,
  });

  final Key itemKey;
  final IconData icon;
  final String label;
  final String meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    // ShadCard paints its own background, so the tile needs a transparent
    // Material of its own for ink to stay visible.
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        key: itemKey,
        leading: Icon(icon, size: 18, color: tokens.brand),
        title: Text(label),
        subtitle: Text(
          meta,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: tokens.textMuted),
        ),
        trailing: const Icon(LucideIcons.chevronRight, size: 16),
        onTap: onTap,
      ),
    );
  }
}

/// The platform this build is running on, for the nav column's build stamp.
String platformLabel() {
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

/// One section on a page of its own, on the compact tier.
///
/// The wide tier never builds this: there the same section is shown in the
/// work panel beside a nav column that is always on screen, so there is no
/// page to go back from.
class _SettingsSectionPage extends StatelessWidget {
  const _SettingsSectionPage({required this.section});

  final SettingsSection section;

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 16, 6),
            child: Row(
              children: [
                ShellVibeIconButton(
                  buttonKey: const Key('settings_section_back'),
                  icon: LucideIcons.chevronLeft,
                  tooltip: 'Settings',
                  // go, not pop: the page is also reachable by deep link, and
                  // then there is nothing behind it to pop to.
                  onPressed: () => GoRouter.maybeOf(context)?.go('/settings'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        section.label,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        section.meta,
                        style: TextStyle(fontSize: 12, color: tokens.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SettingsSectionView(
              section: section,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            ),
          ),
        ],
      ),
    );
  }
}
