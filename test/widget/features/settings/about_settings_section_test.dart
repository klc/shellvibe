import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/core/constants/app_constants.dart';
import 'package:shellvibe/features/settings/domain/services/update_check_service.dart';
import 'package:shellvibe/features/settings/presentation/widgets/about_settings_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSection(
    WidgetTester tester, {
    UpdateCheckService? service,
  }) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (service != null)
            updateCheckServiceProvider.overrideWithValue(service),
        ],
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: AboutSettingsSection()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapCheck(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('about_check_for_updates')));
    await tester.pumpAndSettle();
  }

  group('AboutSettingsSection', () {
    testWidgets('shows the build identity a bug report asks for', (
      tester,
    ) async {
      await pumpSection(tester);

      expect(find.byKey(const Key('about_build_identity')), findsOneWidget);
      expect(find.text(AppConstants.appName), findsOneWidget);
      expect(
        find.textContaining(AppConstants.appVersion),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('checks nothing until the button is pressed', (tester) async {
      var calls = 0;
      await pumpSection(
        tester,
        service: UpdateCheckService(
          fetch: (_) async {
            calls++;
            return json.encode({'tag_name': 'v1.0.0'});
          },
        ),
      );

      expect(calls, 0, reason: 'the section must not poll on its own');
      expect(find.byKey(const Key('about_up_to_date')), findsNothing);

      await tapCheck(tester);
      expect(calls, 1);
    });

    testWidgets('reports an available update and offers the release', (
      tester,
    ) async {
      await pumpSection(
        tester,
        service: UpdateCheckService(
          fetch: (_) async => json.encode({
            'tag_name': 'v99.0.0',
            'html_url': 'https://example.test/v99.0.0',
          }),
        ),
      );
      await tapCheck(tester);

      expect(find.byKey(const Key('about_update_available')), findsOneWidget);
      expect(find.text('Version 99.0.0 is available'), findsOneWidget);
      expect(find.byKey(const Key('about_open_release')), findsOneWidget);
    });

    testWidgets('reports being up to date', (tester) async {
      await pumpSection(
        tester,
        service: UpdateCheckService(
          fetch: (_) async =>
              json.encode({'tag_name': 'v${AppConstants.appVersion}'}),
        ),
      );
      await tapCheck(tester);

      expect(find.byKey(const Key('about_up_to_date')), findsOneWidget);
      expect(find.byKey(const Key('about_open_release')), findsNothing);
    });

    testWidgets('states plainly when the feed cannot be reached', (
      tester,
    ) async {
      // The answer a private repository gives an unauthenticated caller,
      // which is what this build points at today.
      await pumpSection(
        tester,
        service: UpdateCheckService(
          fetch: (_) async =>
              throw const UpdateFeedHttpException(HttpStatus.notFound),
        ),
      );
      await tapCheck(tester);

      expect(find.byKey(const Key('about_update_unavailable')), findsOneWidget);
      expect(find.textContaining('No published releases'), findsOneWidget);
    });

    testWidgets('opens the third-party licence notices', (tester) async {
      await pumpSection(tester);

      await tester.tap(find.byKey(const Key('about_open_licenses')));
      await tester.pumpAndSettle();

      expect(find.byType(LicensePage), findsOneWidget);
    });

    testWidgets('names a security contact matching SECURITY.md', (
      tester,
    ) async {
      await pumpSection(tester);

      expect(find.byKey(const Key('about_security_contact')), findsOneWidget);
      expect(find.textContaining(kSecurityContact), findsOneWidget);

      final policy = File('SECURITY.md').readAsStringSync();
      expect(
        policy,
        contains(kSecurityContact),
        reason: 'the app and SECURITY.md must name the same address',
      );
    });
  });
}
