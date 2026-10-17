/// How often a backup runs without being asked.
///
/// Off by default. A feature shipping is not a reason to start writing to
/// someone's account on a schedule they did not choose.
enum BackupFrequency {
  off('off', null),
  hourly('hourly', Duration(hours: 1)),
  daily('daily', Duration(days: 1)),
  weekly('weekly', Duration(days: 7));

  const BackupFrequency(this.wireName, this.interval);

  /// Stable name in storage. Never derived from [name]: renaming a Dart
  /// identifier must not silently change someone's schedule.
  final String wireName;

  /// How long between backups, or null when off.
  final Duration? interval;

  /// What the user is actually promised.
  ///
  /// There is no background task, so the check runs when the app is open or
  /// coming back to the foreground. "Daily" therefore means "once a day, the
  /// first time you open it" -- and saying so is better than a schedule that
  /// quietly does not happen on a device nobody opened.
  String get promise => switch (this) {
    BackupFrequency.off => 'Only when you ask.',
    BackupFrequency.hourly => 'At most once an hour, while the app is open.',
    BackupFrequency.daily => 'Once a day, the first time you open the app.',
    BackupFrequency.weekly => 'Once a week, the first time you open the app.',
  };

  String get label => switch (this) {
    BackupFrequency.off => 'Off',
    BackupFrequency.hourly => 'Hourly',
    BackupFrequency.daily => 'Daily',
    BackupFrequency.weekly => 'Weekly',
  };

  static BackupFrequency fromWireName(String? value) {
    for (final frequency in BackupFrequency.values) {
      if (frequency.wireName == value) return frequency;
    }

    return BackupFrequency.off;
  }
}
