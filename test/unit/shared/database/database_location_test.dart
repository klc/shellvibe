import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shellvibe/shared/database/app_database.dart';

void main() {
  late Directory root;
  late Directory support;
  late Directory documents;

  setUp(() {
    root = Directory.systemTemp.createTempSync('db_location_test');
    // Not created: the first launch may find no support directory yet.
    support = Directory(p.join(root.path, 'support'));
    documents = Directory(p.join(root.path, 'documents'))..createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<File> resolve() =>
      resolveDatabaseFile(supportDir: support, documentsDir: documents);

  File inDocuments(String name) => File(p.join(documents.path, name));

  test('a database in Documents moves to application support', () async {
    inDocuments('shellvibe.sqlite').writeAsStringSync('db');

    final file = await resolve();

    expect(file.path, p.join(support.path, 'shellvibe.sqlite'));
    expect(file.readAsStringSync(), 'db');
    expect(inDocuments('shellvibe.sqlite').existsSync(), isFalse);
  });

  test('the pre-rename name moves too', () async {
    inDocuments('terly2.sqlite').writeAsStringSync('old');

    final file = await resolve();

    expect(file.path, p.join(support.path, 'shellvibe.sqlite'));
    expect(file.readAsStringSync(), 'old');
  });

  test(
    'a database already in application support is never overwritten',
    () async {
      support.createSync();
      File(p.join(support.path, 'shellvibe.sqlite')).writeAsStringSync('new');
      inDocuments('shellvibe.sqlite').writeAsStringSync('stale');

      final file = await resolve();

      expect(file.readAsStringSync(), 'new');
      expect(inDocuments('shellvibe.sqlite').readAsStringSync(), 'stale');
    },
  );

  test('a database with a journal beside it stays where it is', () async {
    inDocuments('shellvibe.sqlite').writeAsStringSync('db');
    inDocuments('shellvibe.sqlite-journal').writeAsStringSync('pending');

    final file = await resolve();

    expect(file.path, inDocuments('shellvibe.sqlite').path);
    expect(
      File(p.join(support.path, 'shellvibe.sqlite')).existsSync(),
      isFalse,
    );
  });

  test('a fresh install starts in application support', () async {
    final file = await resolve();

    expect(file.path, p.join(support.path, 'shellvibe.sqlite'));
  });
}
