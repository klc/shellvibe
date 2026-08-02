import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/app/app.dart';
import 'package:terly2/shared/database/app_database.dart';
import 'package:terly2/shared/providers/database_providers.dart';

void main() {
  testWidgets('TerlyApp smoke test', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const TerlyApp(),
      ),
    );

    await tester.pumpAndSettle();

    // The rail is icon-only, so the brand is a mark rather than a wordmark.
    expect(find.byKey(const Key('header_brand_logo')), findsOneWidget);
  });
}
