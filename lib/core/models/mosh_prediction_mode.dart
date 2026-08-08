/// Controls when Mosh local prediction is allowed to show anything.
///
/// This is a shared contract between persisted settings, the prediction engine,
/// and terminal presentation. It deliberately lives outside the network
/// implementation so settings do not depend on an engine class.
enum MoshPredictionMode {
  /// Never record or show predictions.
  never,

  /// Show predictions only when the measured RTT makes them useful.
  adaptive,

  /// Show predictions whenever the epoch has been confirmed.
  always,
}
