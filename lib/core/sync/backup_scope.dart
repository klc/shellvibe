/// What a backup carries.
///
/// A backup used to be all-or-nothing. It can now be narrowed to a set of
/// categories, which means a restore has to be able to tell "this category was
/// empty" from "this category was never backed up" -- the payload therefore
/// records the scope it was written with (see `included` in the payload).
library;

/// One user-selectable slice of a backup.
///
/// Workspaces and host groups are deliberately absent: everything else
/// references them, they are small and they hold no secrets, so making them
/// optional would only produce breakage the user did not ask for.
enum BackupCategory {
  hosts('hosts'),
  identities('identities'),
  snippetsAndRunbooks('snippets'),
  portForwards('port_forwards'),
  knownHosts('known_hosts'),
  templates('templates'),
  bookmarks('bookmarks'),

  /// App settings, which live in secure storage rather than the database.
  settings('settings');

  const BackupCategory(this.wireName);

  /// Stable name written into the payload manifest. Never derived from
  /// [name]: renaming a Dart identifier must not change what old backups mean.
  final String wireName;

  /// Payload keys this category owns.
  List<String> get payloadKeys => switch (this) {
    BackupCategory.hosts => const ['hosts'],
    BackupCategory.identities => const ['identities'],
    BackupCategory.snippetsAndRunbooks => const [
      'snippets',
      'runbooks',
      'runbook_steps',
    ],
    BackupCategory.portForwards => const ['port_forward_rules'],
    BackupCategory.knownHosts => const ['known_hosts'],
    BackupCategory.templates => const ['templates', 'template_panes'],
    BackupCategory.bookmarks => const ['bookmarks'],
    BackupCategory.settings => const ['settings'],
  };

  static BackupCategory? fromWireName(String value) {
    for (final category in BackupCategory.values) {
      if (category.wireName == value) return category;
    }
    return null;
  }
}

/// Categories that cannot be backed up without another one.
///
/// `port_forward_rules.host_id` is NOT NULL, so a port forward without its
/// host is a row that cannot exist. Every other cross-category reference is
/// nullable or not a foreign key at all, and is repaired on import instead.
const Map<BackupCategory, BackupCategory> kBackupCategoryRequires = {
  BackupCategory.portForwards: BackupCategory.hosts,
};

/// An immutable set of [BackupCategory].
class BackupScope {
  final Set<BackupCategory> categories;

  const BackupScope._(this.categories);

  /// Everything. The default, and what "manual backup" meant before scopes
  /// existed.
  static const BackupScope full = BackupScope._({
    BackupCategory.hosts,
    BackupCategory.identities,
    BackupCategory.snippetsAndRunbooks,
    BackupCategory.portForwards,
    BackupCategory.knownHosts,
    BackupCategory.templates,
    BackupCategory.bookmarks,
    BackupCategory.settings,
  });

  factory BackupScope.of(Iterable<BackupCategory> categories) =>
      BackupScope._(Set.unmodifiable(categories.toSet()));

  /// Reads the `included` manifest of a payload.
  ///
  /// A payload without one predates scopes and is therefore complete; that is
  /// the only reading that keeps old backups restorable.
  factory BackupScope.fromManifest(Object? manifest) {
    if (manifest is! List) return full;

    return BackupScope.of(
      manifest.whereType<String>().map(BackupCategory.fromWireName).nonNulls,
    );
  }

  bool contains(BackupCategory category) => categories.contains(category);

  bool get isFull => categories.length == full.categories.length;

  /// Categories selected while the category they require is not.
  ///
  /// The UI blocks this; the check lives here so the rule has one home.
  Set<BackupCategory> get unmetDependencies => {
    for (final entry in kBackupCategoryRequires.entries)
      if (contains(entry.key) && !contains(entry.value)) entry.key,
  };

  List<String> toManifest() => [
    for (final category in BackupCategory.values)
      if (contains(category)) category.wireName,
  ];

  @override
  bool operator ==(Object other) =>
      other is BackupScope &&
      other.categories.length == categories.length &&
      other.categories.containsAll(categories);

  @override
  int get hashCode => Object.hashAllUnordered(categories);

  @override
  String toString() => 'BackupScope(${toManifest().join(', ')})';
}
