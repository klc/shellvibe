import 'dart:async';

import 'package:drift/drift.dart';

/// Runs before every test file under `test/`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Several tests open two databases on purpose: two devices syncing, or a
  // backup restored from one database into another. Each of those printed a
  // screenful of "created the database class multiple times" warning that
  // buried real output.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  await testMain();
}
