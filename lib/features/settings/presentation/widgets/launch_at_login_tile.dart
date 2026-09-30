import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/window/launch_at_login.dart';

/// Whether this machine can register a login item, asked once.
final launchAtLoginSupportedProvider = FutureProvider<bool>((ref) async {
  try {
    return await ref.read(launchAtLoginProvider).isSupported();
  } catch (_) {
    return false;
  }
});

/// "Start at login", for the desktop Window section.
///
/// Its state is the OS's, not a setting: see [LaunchAtLogin]. It follows the
/// tray setting, because a launch at login starts with the window hidden and
/// only the tray icon to find the app by. With the tray off the switch cannot
/// be turned on; one that is already on can still be turned off, since the
/// login item is on the machine either way.
class LaunchAtLoginTile extends ConsumerWidget {
  const LaunchAtLoginTile({super.key, required this.trayEnabled});

  final bool trayEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supported = ref.watch(launchAtLoginSupportedProvider).value ?? false;
    if (!supported) return const SizedBox.shrink();

    final enabled = ref.watch(launchAtLoginEnabledProvider).value ?? false;
    return SwitchListTile(
      key: const Key('settings_launch_at_login_switch'),
      title: const Text('Start at Login'),
      subtitle: Text(
        trayEnabled
            ? 'Starts ShellVibe when you sign in, hidden in the tray until '
                  'you open it.'
            : 'Turn on the tray icon first: a hidden start needs it to be '
                  'found again.',
      ),
      value: enabled,
      onChanged: trayEnabled || enabled
          ? (value) => _set(context, ref, value)
          : null,
    );
  }

  Future<void> _set(BuildContext context, WidgetRef ref, bool value) async {
    try {
      await ref.read(launchAtLoginEnabledProvider.notifier).setEnabled(value);
    } catch (e) {
      if (!context.mounted) return;
      ShadToaster.of(context).show(
        ShadToast.destructive(
          title: const Text('Could not change start at login'),
          description: Text('$e'),
        ),
      );
    }
  }
}
