/// How a run spreads over its hosts.
enum RunMode {
  /// Several hosts at once, up to [RunStrategy.concurrency].
  parallel,

  /// One host at a time, in the order given; the first failure stops the rest
  /// from starting. A canary: try it on one, and only go on if it held.
  rolling,
}

/// A run's host strategy, chosen per run in the target sheet.
class RunStrategy {
  final RunMode mode;

  /// Hosts in flight at once under [RunMode.parallel]; always 1 for rolling.
  final int concurrency;

  /// The default, and what one host or an unchosen strategy gets.
  static const int defaultConcurrency = 4;

  /// The ceiling: every host is a fresh SSH connection plus its jump chain.
  static const int maxConcurrency = 8;

  const RunStrategy._(this.mode, this.concurrency);

  /// Parallel at [defaultConcurrency], as a constant for default arguments.
  static const RunStrategy defaultParallel = RunStrategy._(
    RunMode.parallel,
    defaultConcurrency,
  );

  /// Values outside 1..[maxConcurrency] are clamped.
  factory RunStrategy.parallel([int concurrency = defaultConcurrency]) =>
      RunStrategy._(RunMode.parallel, concurrency.clamp(1, maxConcurrency));

  const RunStrategy.rolling() : this._(RunMode.rolling, 1);

  bool get isRolling => mode == RunMode.rolling;

  /// The stored form: `parallel:4` or `rolling`.
  String get wireName => isRolling ? 'rolling' : 'parallel:$concurrency';

  /// Reads [wireName]; anything unrecognised is the default parallel strategy.
  factory RunStrategy.parse(String? value) {
    if (value == 'rolling') return const RunStrategy.rolling();
    final n = int.tryParse(value?.split(':').last ?? '');
    return RunStrategy.parallel(n ?? defaultConcurrency);
  }

  String get label => isRolling ? 'rolling' : 'parallel ×$concurrency';

  @override
  bool operator ==(Object other) =>
      other is RunStrategy &&
      other.mode == mode &&
      other.concurrency == concurrency;

  @override
  int get hashCode => Object.hash(mode, concurrency);
}
