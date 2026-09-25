import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/diagnostics/crash_log.dart';

/// The platform, as a bug report names it.
String currentPlatformLabel() {
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

/// A scrubbed report around [rawLog], or around no log at all.
CrashReport buildProblemReport(String? rawLog) => CrashReport.fromLog(
  appVersion: AppConstants.appVersion,
  platform: currentPlatformLabel(),
  osVersion: kIsWeb ? '' : Platform.operatingSystemVersion,
  rawLog: rawLog,
  homeDirectory: kIsWeb
      ? null
      : Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'],
);

/// Offers the crashes written since the last launch, once.
///
/// Release builds only: a debug session logs every framework assertion, and
/// asking the developer about each one on the next hot restart is noise. The
/// log is marked offered before the dialog opens, so dismissing it -- or the
/// app dying again with it open -- does not bring the same crash back.
Future<void> offerUnreportedCrash(BuildContext context) async {
  if (!kReleaseMode) return;

  final log = await CrashLog.open();
  final unoffered = await log.readUnoffered();
  if (unoffered == null) return;
  await log.markOffered();

  if (!context.mounted) return;
  await showProblemReportDialog(
    context,
    report: buildProblemReport(unoffered),
    afterCrash: true,
  );
}

/// Shows [report] for the user to read, copy, or file as a GitHub issue.
///
/// Nothing is sent from here. "Report on GitHub" opens the new-issue page in
/// the browser with the report filled in, and the user still edits and
/// submits it themselves.
Future<void> showProblemReportDialog(
  BuildContext context, {
  required CrashReport report,
  bool afterCrash = false,
}) {
  return showShadDialog<void>(
    context: context,
    builder: (dialogContext) {
      final tokens = ShellVibeTokens.resolve(dialogContext);
      final body = report.body();

      return ShadDialog(
        key: const Key('problem_report_dialog'),
        title: Text(
          afterCrash
              ? 'ShellVibe ran into an error last time'
              : 'Report a problem',
        ),
        description: Text(
          'Reporting opens a new GitHub issue in your browser with the text '
          'below filled in. Home folders, addresses and user@host pairs are '
          'already masked, but read it for host names or paths before you '
          'submit: the issue is public.',
          style: Theme.of(
            dialogContext,
          ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
        ),
        actions: adaptiveDialogActions(dialogContext, [
          ShellVibeButton.secondary(
            key: const Key('problem_report_close'),
            label: afterCrash ? 'Not now' : 'Close',
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          ShellVibeButton.secondary(
            key: const Key('problem_report_copy'),
            label: 'Copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: body));
              ShadToaster.of(
                dialogContext,
              ).show(const ShadToast(description: Text('Report copied.')));
            },
          ),
          ShellVibeButton(
            key: const Key('problem_report_open_issue'),
            label: 'Report on GitHub',
            onPressed: () async {
              await launchUrl(
                report.issueUri(),
                mode: LaunchMode.externalApplication,
              );
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
          ),
        ]),
        actionsAxis: adaptiveDialogActionsAxis(dialogContext),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320, maxWidth: 560),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: tokens.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                body,
                key: const Key('problem_report_preview'),
                style: shellvibeMono(
                  dialogContext,
                  size: 11,
                  color: tokens.textSecondary,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
