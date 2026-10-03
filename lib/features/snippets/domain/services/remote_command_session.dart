import '../../../hosts/domain/models/host_model.dart';

/// One live command channel on one host, as the run service sees it.
///
/// An abstraction rather than the SSH types so `RunbookRunService` stays pure
/// Dart and testable without a socket. Working directory and environment
/// persist between [run] calls, like a terminal's: a runbook's `cd` in step 1
/// still applies in step 2.
abstract class RemoteCommandSession {
  /// Runs [command] and returns its combined stdout + stderr and exit code.
  ///
  /// Throws when the command cannot be run to completion (it exceeded
  /// [timeout] and was interrupted, or the connection dropped) — an exit code
  /// is only ever a real one.
  Future<(String output, int exitCode)> run(String command, Duration timeout);

  /// Stops whatever [run] is currently executing.
  Future<void> interrupt();

  /// Releases the channel and the connection underneath it. Idempotent.
  Future<void> close();
}

/// Opens a [RemoteCommandSession] on a host.
abstract class RemoteCommandSessionFactory {
  /// Throws with a message fit to show the user when [host] cannot be
  /// connected to; nothing is left open in that case.
  Future<RemoteCommandSession> open(HostModel host);
}

/// A failure to open or use a session, worded for the person running it.
class RemoteCommandException implements Exception {
  final String message;
  const RemoteCommandException(this.message);

  @override
  String toString() => message;
}
