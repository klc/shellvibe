import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../widgets/mcp_access_settings_section.dart';

/// The AI Access module: the MCP bridge's switch, its clients and its knobs.
/// Desktop only; the router keeps a phone out (see `app_router.dart`).
class McpAccessScreen extends StatelessWidget {
  const McpAccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Scaffold(
      body: Column(
        children: [
          const ShellVibePageHeader(
            icon: LucideIcons.bot,
            title: 'AI Access',
            description:
                'AI agent access, registered clients, and the kill switch.',
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                tokens.pagePadding,
                20,
                tokens.pagePadding,
                32,
              ),
              children: const [McpAccessSettingsSection()],
            ),
          ),
        ],
      ),
    );
  }
}
