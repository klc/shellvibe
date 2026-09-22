import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/hosts/presentation/notifiers/host_groups_notifier.dart';
import '../features/hosts/presentation/notifiers/hosts_notifier.dart';
import '../features/snippets/presentation/notifiers/snippets_notifier.dart';
import '../features/snippets/presentation/notifiers/runbooks_notifier.dart';
import '../features/tunnels/presentation/providers/tunnels_providers.dart';
import '../features/vault/presentation/notifiers/identities_notifier.dart';
import '../features/workspaces/presentation/notifiers/workspaces_notifier.dart';

/// Re-reads everything a backup restore rewrote underneath the app.
///
/// A restore writes to the database directly, row by row, rather than going
/// through the repositories. The list notifiers read their tables once in
/// `build()` and hold the result, so nothing on screen noticed: hosts,
/// identities and snippets stayed as they were until the app was restarted.
/// Telling the user to reopen the app is not a fix, it is the bug with
/// instructions.
///
/// Lives in `app/` because it is the one place allowed to know about every
/// feature at once. `core/` and `shared/` sit below features and must not
/// import them.
///
/// Invalidating rather than converting the notifiers to database streams: a
/// restore is a rare, explicit act, and rebuilding seven providers at that
/// moment is cheaper in both runtime and review than making every list in the
/// app reactive to catch one event a user triggers by hand.
///
/// Two entry points rather than one, because a notifier holds a `Ref` and a
/// widget a `WidgetRef`; they share no supertype, and the parameter type of
/// `invalidate` is not part of this Riverpod version's public API. A wrapper
/// clever enough to take both would be harder to read than the repetition.
void invalidateRestoredData(Ref ref) {
  // Workspaces first: the lists below are scoped by the selected workspace, so
  // a stale selection would filter freshly restored rows straight back out.
  ref.invalidate(workspaceManagerProvider);

  ref.invalidate(hostsProvider);
  ref.invalidate(hostGroupsProvider);
  ref.invalidate(identitiesProvider);
  ref.invalidate(undecryptableIdentityIdsProvider);
  ref.invalidate(tunnelsProvider);
  ref.invalidate(snippetsProvider);
  ref.invalidate(runbooksProvider);
}

/// [invalidateRestoredData], for a widget.
void invalidateRestoredDataFor(WidgetRef ref) {
  ref.invalidate(workspaceManagerProvider);

  ref.invalidate(hostsProvider);
  ref.invalidate(hostGroupsProvider);
  ref.invalidate(identitiesProvider);
  ref.invalidate(undecryptableIdentityIdsProvider);
  ref.invalidate(tunnelsProvider);
  ref.invalidate(snippetsProvider);
  ref.invalidate(runbooksProvider);
}
