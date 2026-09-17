import 'package:flutter/foundation.dart';

/// Capability codes the server grants.
///
/// Strings rather than an enum: the contract says new values may appear inside
/// v1 and that clients must stay fail-safe about ones they do not know.
abstract final class Capabilities {
  /// Desktop-to-phone terminal sharing over the LAN.
  ///
  /// **Never gate anything on this.** Local Device Link is free, works offline
  /// and works with no account at all, so the app must not ask the server
  /// whether the user may use it. It appears in the entitlement snapshot only
  /// because the server describes the free plan with it.
  static const String localDeviceLink = 'local_device_link';

  /// Revision-based encrypted vault snapshots. The paid feature this client
  /// work exists for.
  static const String cloudBackup = 'cloud_backup';

  /// Multi-device operation-log sync. Server endpoints exist; the client
  /// protocol does not, so nothing reads this yet.
  static const String cloudSync = 'cloud_sync';

  /// Terminal sharing through the relay, off the LAN.
  static const String remoteDeviceLink = 'remote_device_link';

  /// Team-shared workspaces.
  static const String sharedWorkspaces = 'shared_workspaces';
}

/// Plan tiers, highest last.
enum BillingPlan {
  free('free'),
  pro('pro'),
  team('team');

  const BillingPlan(this.code);

  /// Wire value.
  final String code;

  /// Maps a server plan code, falling back to [BillingPlan.free].
  ///
  /// An unrecognised tier is treated as the *lowest* one on purpose: a client
  /// that guessed upward would unlock paid features for a plan it does not
  /// understand.
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

  /// The server sent a status this build does not know. Treated as not
  /// entitled.
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
  /// Largest single backup upload, in bytes. `0` means backups are not
  /// included in the plan at all.
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

  /// All-zero limits, which is what the free plan carries.
  static const BillingLimits none = BillingLimits();

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

/// A provider-independent entitlement snapshot: `GET /api/v1/entitlements`.
///
/// This gates *UI*, not access. Real enforcement is the server's `entitlement:`
/// middleware, which answers `403` regardless of what this object says. That is
/// why tampering with a cached snapshot buys nothing, and why every ambiguous
/// case here resolves to locked: the cost of being wrong in that direction is a
/// paywall the user can dismiss by going online, not a free subscription.
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

  /// What the app assumes before it has heard from the server, and whenever it
  /// cannot trust what it heard.
  static const Entitlement free = Entitlement(
    plan: BillingPlan.free,
    status: BillingStatus.active,
    capabilities: {Capabilities.localDeviceLink},
    limits: BillingLimits.none,
  );

  /// Decodes the `data` member of an entitlement response.
  ///
  /// Never throws. A body this build cannot make sense of resolves to
  /// [Entitlement.free], because a parse failure must not be a way in.
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
          : BillingLimits.none,
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
  /// * [Capabilities.localDeviceLink] is always true. It is free, offline and
  ///   accountless, and no server answer -- including a missing one -- may
  ///   switch it off.
  /// * Everything else additionally requires [BillingStatus.grantsAccess], so
  ///   an expired plan whose capability list the server still echoes stays
  ///   locked.
  bool has(String capability) {
    if (capability == Capabilities.localDeviceLink) return true;

    return status.grantsAccess && capabilities.contains(capability);
  }

  /// Encrypted cloud backup, the paid feature behind the vault sync UI.
  bool get hasCloudBackup => has(Capabilities.cloudBackup);

  /// True while the subscription is past due but still inside grace.
  bool get isInGracePeriod => status == BillingStatus.grace;

  /// True for any plan above [BillingPlan.free] that currently grants access.
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
