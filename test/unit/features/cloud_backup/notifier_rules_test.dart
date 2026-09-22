import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Rules that live in the notifiers, checked in the source.
///
/// The same reasoning as `sync_notifier_lifecycle_test`: each of these is a
/// line of glue between a service and a provider, and standing up the
/// account, the entitlement, the database, secure storage and a scripted HTTP
/// transport to assert one of them would test the harness rather than the
/// rule. What each rule prevents is written next to it, because that is the
/// part a future reader needs.
void main() {
  String bodyOf(String source, String signature) {
    final start = source.indexOf(signature);
    expect(start, isNot(-1), reason: '$signature no longer exists');

    // From the end of the signature, so an optional-parameter brace in the
    // signature itself is not mistaken for the start of the body.
    final open = source.indexOf('{', start + signature.length);
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

  group('the backup schedule', () {
    late String source;

    setUpAll(() {
      source = File(
        'lib/features/cloud_backup/presentation/notifiers/'
        'cloud_backup_notifier.dart',
      ).readAsStringSync();
    });

    test('the mark is only written for an upload that landed', () {
      // The mark says "this interval's backup has been taken". Written after
      // a refusal -- a throttle, a body over the plan limit, a server that
      // could not be reached -- it makes the device wait out the whole
      // interval again. On a weekly schedule one dropped connection is then a
      // week with no backup, and nothing on the screen says so.
      final body = bodyOf(source, 'Future<void> maybeBackUpOnSchedule()');

      final attempt = body.indexOf('await backUpNow();');
      // The last one: an earlier branch writes the mark for an interval that
      // had nothing to back up, which is not the write this rule is about.
      final mark = body.lastIndexOf('writeAutoBackupMark');

      expect(attempt, isNot(-1));
      expect(mark, greaterThan(attempt));

      final between = body.substring(attempt, mark);

      expect(
        between.contains('messageIsError'),
        isTrue,
        reason:
            'Between the attempt and the mark there has to be a check that '
            'the attempt succeeded. A conflict check alone lets every other '
            'refusal count as the interval\'s backup.',
      );
      expect(
        between.contains('conflictingServerRevision'),
        isTrue,
        reason: 'A conflict still has to stop the mark being written.',
      );
    });
  });

  group('the sync pass', () {
    late String source;

    setUpAll(() {
      source = File(
        'lib/features/cloud_backup/presentation/notifiers/sync_notifier.dart',
      ).readAsStringSync();
    });

    test('the joining pass reports what it could not read', () {
      // `_pullThenPush` is the pass that runs the moment a join finishes,
      // which is the first and likeliest place a key that does not match the
      // account's shows itself. Rebuilding the result without the count
      // reports that device as a clean sync that happened to pull nothing --
      // the exact silence the count exists to break.
      final body = bodyOf(source, 'Future<SyncResult> _pullThenPush(');

      expect(
        body.contains('unreadable: pulled.unreadable'),
        isTrue,
        reason:
            'Every field `pull` returns has to survive being repacked into '
            'the result the notifier publishes.',
      );
    });
  });

  group('the sync key', () {
    late String source;

    setUpAll(() {
      source = File(
        'lib/features/cloud_backup/presentation/notifiers/sync_notifier.dart',
      ).readAsStringSync();
    });

    test('a stored key does not end the search on its own', () {
      // Two devices switching sync on before either has written a ground each
      // mint a key. If holding a key were reason enough to stop looking,
      // neither would ever see the other's -- and each would push a log the
      // other silently discards, forever, with nothing failing.
      final body = bodyOf(source, 'Future<Uint8List> _resolveSyncKey(');

      final stored = body.indexOf('final stored = await store.readSyncKey();');
      final ground = body.indexOf('ground.readGround(');

      expect(stored, isNot(-1));
      expect(ground, greaterThan(stored));

      expect(
        body.contains('adoptGroundSyncKey'),
        isTrue,
        reason:
            'The ground is what every joining device starts from, so the key '
            'it carries is the account\'s and has to overrule this device\'s.',
      );
      expect(
        RegExp(r'readJoinState\(\)').hasMatch(body),
        isTrue,
        reason:
            'The ground is read while the join is unfinished and not on every '
            'start afterwards, or each launch re-downloads a snapshot to '
            're-confirm a key that cannot change.',
      );
    });

    test('adopting the account key re-arms the join', () {
      // The join runs once per instance, and this notifier survives rebuilds.
      // A rebuild that discovers the re-key sets the flag, finds the join
      // already marked started, and returns -- so the forced ground rewrite,
      // the one thing that carries this device's rows to the others, never
      // runs. The join state written to disk says it has to run again.
      final body = bodyOf(source, 'Future<Uint8List> _resolveSyncKey(');

      final reKeyed = body.indexOf('if (_reKeyed) {');
      expect(reKeyed, isNot(-1));

      expect(
        body.indexOf('_joinStarted = false', reKeyed),
        isNot(-1),
        reason:
            'The per-instance guard has to be released alongside the join '
            'state on disk, or the repair is skipped on a rebuild.',
      );
    });

    test('adopting the account key forces the ground to be rewritten', () {
      // Everything this device sent before it adopted was sealed with a key
      // nobody else holds. Those rows exist nowhere another device can read
      // them, and a fresh ground written under the right key is the only path
      // they have left -- which is why the staleness test does not apply.
      final body = bodyOf(source, 'Future<void> _joinThenSync()');

      expect(
        body.contains('_refreshGround(force: _reKeyed)'),
        isTrue,
        reason: 'A re-keyed device has to rewrite the ground unconditionally.',
      );

      final refresh = bodyOf(
        source,
        'Future<void> _refreshGround({bool force = false}) async',
      );

      expect(
        refresh.contains('if (force)'),
        isTrue,
        reason: 'The forced path has to skip refreshIfStale entirely.',
      );
    });
  });
}
