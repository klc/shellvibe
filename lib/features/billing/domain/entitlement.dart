import 'package:flutter/foundation.dart';

/// Capability codes the server grants.
///
/// Strings rather than an enum: the contract says new values may appear inside
/// v1 and that clients must stay fail-safe about ones they do not know.
abstract final class Capabilities {
  /// Desktop-to-phone terminal sharing over the LAN.
  ///
  /// **Never gate anything on this.** Local Device Link works offline and with
  /// no account at all, so the app must not ask the server whether the user
  /// may use it. It appears in the entitlement snapshot only because the
  /// server describes the free plan with it.
  static const String localDeviceLink = 'local_device_link';

  /// Revision-based encrypted vault snapshots. On the free plan.
  static const String cloudBackup = 'cloud_backup';

  /// Multi-device operation-log sync. On the free plan.
  static const String cloudSync = 'cloud_sync';

  /// Terminal sharing through the relay, off the LAN. On the free plan.
  static const String remoteDeviceLink = 'remote_device_link';

  /// Team-shared workspaces. The one capability the free plan does *not*
  /// carry, and so the only one a gate here would be about. No client
  /// surface reads it yet.
  static const String sharedWorkspaces = 'shared_workspaces';
}

/// Plan tiers, highest last.
///
/// Every feature this client ships is on [free]. [pro] is historical -- it
/// exists because accounts granted it before the switch still report it --
/// and [team] is the only tier that adds anything, which today is
/// [Capabilities.sharedWorkspaces] and nothing the client draws.
enum BillingPlan {
  free('free'),
  pro('pro'),
  team('team');

  const BillingPlan(this.code);

  /// Wire value.
  final String code;

  /// Maps a server plan code, falling back to [BillingPlan.free].
  ///
  /// An unrecognised tier is treated as the *lowest* one on purpose. Free
  /// already carries everything the client draws, so nothing is lost by
  /// guessing down, while guessing up would show a tier's surface to an
  /// account this build cannot confirm is on it.
  static BillingPlan fromCode(Object? value) => switch (value) {
    'pro' => BillingPlan.pro,
    'team' => BillingPlan.team,
    _ => BillingPlan.free,
  };
}

/// Lifecycle of the subscription behind the plan.
enum BillingStatus {
  /// Paid and current.
  active('active'),

  /// Payment failed but the provider's grace window has not closed.
  grace('grace'),

  /// Over, or never started.
  expired('expired'),

  /// The server sent a status this build does not know. Treated as granting
  /// nothing beyond [Entitlement.freeCapabilities].
  unknown('unknown');

  const BillingStatus(this.code);

  final String code;

  static BillingStatus fromCode(Object? value) => switch (value) {
    'active' => BillingStatus.active,
    'grace' => BillingStatus.grace,
    'expired' => BillingStatus.expired,
    null => BillingStatus.active, // A free account reports no subscription.
    _ => BillingStatus.unknown,
  };

  /// Whether capabilities should be honoured in this state.
  bool get grantsAccess => this == active || this == grace;
}

/// Numeric plan limits from `data.limits`.
@immutable
final class BillingLimits {
  /// Largest single backup upload, in bytes.
  final int maxBackupSizeBytes;

  /// How many revisions the server keeps before pruning the oldest.
  final int maxBackupRevisions;

  final int relayConcurrentSessions;
  final int teamSeats;

  const BillingLimits({
    this.maxBackupSizeBytes = 0,
    this.maxBackupRevisions = 0,
    this.relayConcurrentSessions = 0,
    this.teamSeats = 0,
  });

  /// All-zero limits. Not a plan -- it is what an object built with no
  /// arguments holds, and it is never what a missing server answer resolves
  /// to. See [freePlan].
  static const BillingLimits none = BillingLimits();

  /// The free plan's numbers, mirroring `config/billing.limits.free` on the
  /// server.
  ///
  /// This is the fallback for every ambiguous case: a body without a `limits`
  /// member, and the snapshot the app assumes before it has heard from the
  /// server at all. Falling back to zero would read as "backups are not
  /// included", which is no longer a state this product has -- it would take
  /// a free feature away over a parse failure.
  ///
  /// The server is still the one enforcing these. A client that guessed high
  /// gets a `413` on upload, not free storage.
  static const BillingLimits freePlan = BillingLimits(
    maxBackupSizeBytes: 5 * 1024 * 1024,
    maxBackupRevisions: 10,
    relayConcurrentSessions: 2,
  );

  static BillingLimits fromJson(Map<String, Object?> json) => BillingLimits(
    maxBackupSizeBytes: _int(json['max_backup_size_bytes']),
    maxBackupRevisions: _int(json['max_backup_revisions']),
    relayConcurrentSessions: _int(json['relay_concurrent_sessions']),
    teamSeats: _int(json['team_seats']),
  );

  Map<String, Object?> toJson() => {
    'max_backup_size_bytes': maxBackupSizeBytes,
    'max_backup_revisions': maxBackupRevisions,
    'relay_concurrent_sessions': relayConcurrentSessions,
    'team_seats': teamSeats,
  };

  static int _int(Object? value) => switch (value) {
    final int v => v,
    final num v => v.toInt(),
    final String v => int.tryParse(v) ?? 0,
    _ => 0,
  };

  @override
  bool operator ==(Object other) =>
      other is BillingLimits &&
      other.maxBackupSizeBytes == maxBackupSizeBytes &&
      other.maxBackupRevisions == maxBackupRevisions &&
      other.relayConcurrentSessions == relayConcurrentSessions &&
      other.teamSeats == teamSeats;

  @override
  int get hashCode => Object.hash(
    maxBackupSizeBytes,
    maxBackupRevisions,
    relayConcurrentSessions,
    teamSeats,
  );
}

/// An entitlement snapshot: `GET /api/v1/entitlements`.
///
/// Every feature this client ships is on the free plan, so in practice this
/// object carries *limits* -- how large a backup may be, how many revisions
/// the server keeps -- rather than permission. [freeCapabilities] says so in
/// code: those never depend on what came back.
///
/// It still answers [has] for anything outside that set, and there the old
/// rule holds: this gates UI, not access. Real enforcement is the server's
/// `entitlement:` middleware, which answers `403` regardless of what this
/// object says, so tampering with a cached snapshot buys nothing.
@immutable
final class Entitlement {
  final BillingPlan plan;
  final BillingStatus status;

  /// Capability codes the server reports, unfiltered.
  final Set<String> capabilities;

  final BillingLimits limits;

  /// When the current period ends, if the plan has an end.
  final DateTime? expiresAt;

  /// When the provider's grace window closes, if one is open.
  final DateTime? graceEndsAt;

  const Entitlement({
    required this.plan,
    required this.status,
    required this.capabilities,
    required this.limits,
    this.expiresAt,
    this.graceEndsAt,
  });

  /// The capabilities the free plan carries, which is every one this client
  /// draws a surface for.
  ///
  /// Held here rather than read off [capabilities] because they do not depend
  /// on a subscription: no server answer -- a missing one, an unparseable
  /// one, or one reporting an expired tier -- may switch them off. Only
  /// [Capabilities.sharedWorkspaces] sits outside this set.
  static const Set<String> freeCapabilities = {
    Capabilities.localDeviceLink,
    Capabilities.cloudBackup,
    Capabilities.cloudSync,
    Capabilities.remoteDeviceLink,
  };

  /// What the app assumes before it has heard from the server, and whenever it
  /// cannot trust what it heard.
  static const Entitlement free = Entitlement(
    plan: BillingPlan.free,
    status: BillingStatus.active,
    capabilities: freeCapabilities,
    limits: BillingLimits.freePlan,
  );

  /// Decodes the `data` member of an entitlement response.
  ///
  /// Never throws. A body this build cannot make sense of resolves to
  /// [Entitlement.free] -- the whole product, minus the one tier the client
  /// has no surface for. A parse failure is not a reason to take a free
  /// feature away, and it is not a way into a tier either.
  static Entitlement fromJson(Map<String, Object?> json) {
    final rawCapabilities = json['capabilities'];
    final capabilities = rawCapabilities is List
        ? rawCapabilities.whereType<String>().toSet()
        : const <String>{};

    final limits = json['limits'];

    return Entitlement(
      plan: BillingPlan.fromCode(json['plan']),
      status: BillingStatus.fromCode(json['status']),
      capabilities: capabilities,
      limits: limits is Map<String, Object?>
          ? BillingLimits.fromJson(limits)
          : BillingLimits.freePlan,
      expiresAt: _dateTime(json['expires_at']),
      graceEndsAt: _dateTime(json['grace_ends_at']),
    );
  }

  Map<String, Object?> toJson() => {
    'plan': plan.code,
    'status': status.code,
    'capabilities': capabilities.toList(growable: false),
    'limits': limits.toJson(),
    'expires_at': expiresAt?.toIso8601String(),
    'grace_ends_at': graceEndsAt?.toIso8601String(),
  };

  /// Whether [capability] is unlocked.
  ///
  /// Two rules on top of "is it in the list":
  ///
  /// * Anything in [freeCapabilities] is always true. Those are not bought,
  ///   so no server answer -- including a missing one -- may switch them off.
  /// * Everything else additionally requires [BillingStatus.grantsAccess], so
  ///   an expired tier whose capability list the server still echoes stays
  ///   locked.
  bool has(String capability) {
    if (freeCapabilities.contains(capability)) return true;

    return status.grantsAccess && capabilities.contains(capability);
  }

  /// Encrypted cloud backup. Free, so this is always true; call sites keep
  /// reading it because the question they are asking is a real one and the
  /// answer is allowed to change again.
  bool get hasCloudBackup => has(Capabilities.cloudBackup);

  /// True while the subscription is past due but still inside grace.
  bool get isInGracePeriod => status == BillingStatus.grace;

  /// True for any tier above [BillingPlan.free] that currently grants access.
  bool get isPaid => plan != BillingPlan.free && status.grantsAccess;

  static DateTime? _dateTime(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  @override
  bool operator ==(Object other) =>
      other is Entitlement &&
      other.plan == plan &&
      other.status == status &&
      other.limits == limits &&
      other.expiresAt == expiresAt &&
      other.graceEndsAt == graceEndsAt &&
      setEquals(other.capabilities, capabilities);

  @override
  int get hashCode => Object.hash(
    plan,
    status,
    limits,
    expiresAt,
    graceEndsAt,
    Object.hashAllUnordered(capabilities),
  );

  @override
  String toString() => 'Entitlement(${plan.code}/${status.code})';
}
