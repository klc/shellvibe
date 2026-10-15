import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'notifiers/settings_notifier.dart';

/// Copies [value] to the clipboard under the clipboard auto-clear setting,
/// then shows [toast] -- the one routine every "copy secret" control shares.
Future<void> copySecretWithAutoClear(
  WidgetRef ref,
  BuildContext context,
  String value, {
  required String toast,
}) async {
  final seconds =
      ref.read(settingsProvider).value?.clipboardAutoClearSeconds ?? 30;
  await ref
      .read(clipboardAutoClearServiceProvider)
      .copyAndScheduleClear(value, duration: Duration(seconds: seconds));
  if (context.mounted) {
    ShadToaster.of(context).show(ShadToast(description: Text(toast)));
  }
}
