import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Starting sync must not tear down what it is starting.
///
/// `_start` used to begin with `_stop`, and `_stop` drops the engine, the join
/// service and the ground service. `build` constructed all three and then
/// called `_start`, which threw them away a line later. Nothing failed:
/// `syncNow` returns at its null check, so the debounce timer, the five minute
/// poll and the foreground pass all ran and did nothing -- for every build
/// since automatic sync was switched on.
///
/// Checked in the source rather than through the notifier because the failure
/// is structural: the two methods answer different questions and one of them
/// must not call the other. A behavioural test would need the account, the
/// entitlement, the database and secure storage stood up to assert a field is
/// not null, and would still not say why.
void main() {
  late String source;

  setUpAll(() {
    source = File(
      'lib/features/cloud_backup/presentation/notifiers/sync_notifier.dart',
    ).readAsStringSync();
  });

  String bodyOf(String signature) {
    final start = source.indexOf(signature);
    expect(start, isNot(-1), reason: '$signature no longer exists');

    final open = source.indexOf('{', start);
    var depth = 0;

    for (var i = open; i < source.length; i++) {
      if (source[i] == '{') depth++;
      if (source[i] == '}') {
        depth--;
        if (depth == 0) return source.substring(open, i);
      }
    }

    fail('Could not find the end of $signature');
  }

  test('_start cancels timers without dropping the engine', () {
    final body = bodyOf('void _start(AppDatabase db)');

    expect(
      body.contains('_stopTimers()'),
      isTrue,
      reason: '_start has to cancel what is already scheduled.',
    );
    expect(
      RegExp(r'_stop\(\)').hasMatch(body),
      isFalse,
      reason:
          '_start must not call _stop: it runs after build has constructed '
          'the engine, the join service and the ground service, and _stop '
          'drops all three. Nothing reports that, because syncNow returns '
          'quietly when the engine is null.',
    );
  });

  test('_stopTimers leaves the services alone', () {
    final body = bodyOf('void _stopTimers()');

    for (final field in ['_engine', '_join', '_ground']) {
      expect(
        body.contains('$field = null'),
        isFalse,
        reason:
            '_stopTimers is the restart path. Clearing $field here is the '
            'bug this test exists for.',
      );
    }
  });

  test('_stop still shuts everything down', () {
    // The teardown path is the one `onDispose` uses, and a disposed notifier
    // that kept its engine would go on syncing into a provider nobody holds.
    final body = bodyOf('void _stop()');

    expect(body.contains('_stopTimers()'), isTrue);

    for (final field in ['_engine', '_join', '_ground']) {
      expect(
        body.contains('$field = null'),
        isTrue,
        reason: '_stop has to release $field.',
      );
    }
  });

  test('the join is started after build returns, not from inside it', () {
    // Published from inside build, the join's own failure is written to a
    // state that does not exist yet and the screen keeps saying it is
    // watching for changes.
    final body = bodyOf('Future<SyncState> build()');

    expect(
      body.contains('Future(() => unawaited(_startJoinOnce()))'),
      isTrue,
      reason:
          'The join has to run on the event queue, after the state it '
          'reports into has been assigned.',
    );
  });
}
