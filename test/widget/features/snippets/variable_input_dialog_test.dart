import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/features/snippets/domain/models/variable_declaration.dart';
import 'package:shellvibe/features/snippets/presentation/widgets/variable_input_dialog.dart';

const _declarations = [
  VariableDeclaration(
    name: 'env',
    type: VariableType.enumeration,
    options: ['staging', 'prod'],
    description: 'Where it goes',
  ),
  VariableDeclaration(name: 'region', defaultValue: 'eu-1', required: false),
  VariableDeclaration(name: 'token', type: VariableType.secret),
  VariableDeclaration(name: 'note', label: 'Release note'),
];
const _names = ['env', 'region', 'token', 'note'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> open(
    WidgetTester tester,
    ProviderContainer container,
    void Function(Map<String, String>?) onResult, {
    String? memoryKey = 'runbook:rb',
  }) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async => onResult(
                    await VariableInputDialog.show(
                      context,
                      variables: _names,
                      declarations: _declarations,
                      memoryKey: memoryKey,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(
    WidgetTester tester, {
    String env = 'prod',
    String? region,
    String token = 's3cret',
    String note = 'v2',
  }) async {
    await tester.tap(find.byKey(const Key('variable_input_env')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(env).last);
    await tester.pumpAndSettle();
    if (region != null) {
      await tester.enterText(
        find.byKey(const Key('variable_input_region')),
        region,
      );
    }
    await tester.enterText(
      find.byKey(const Key('variable_input_token')),
      token,
    );
    await tester.enterText(find.byKey(const Key('variable_input_note')), note);
  }

  EditableText editable(WidgetTester tester, String name) => tester.widget(
    find.descendant(
      of: find.byKey(Key('variable_input_$name')),
      matching: find.byType(EditableText),
    ),
  );

  testWidgets('each type is asked for as declared', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await open(tester, container, (_) {});

    // A choice, with its description and label.
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.text('Where it goes'), findsOneWidget);
    expect(find.text('Release note'), findsOneWidget);
    // An optional one says so, and its default is prefilled.
    expect(find.text('region (optional)'), findsOneWidget);
    expect(editable(tester, 'region').controller.text, 'eu-1');
    // A secret is hidden as typed, and not autocorrected or suggested.
    final secret = editable(tester, 'token');
    expect(secret.obscureText, isTrue);
    expect(secret.autocorrect, isFalse);
    expect(secret.enableSuggestions, isFalse);
    expect(secret.controller.text, isEmpty);
    // Plain text is not obscured.
    expect(editable(tester, 'note').obscureText, isFalse);
  });

  testWidgets('required variables must be filled in, optional ones need not', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    Map<String, String>? result;
    await open(tester, container, (r) => result = r);

    await tester.tap(find.byKey(const Key('variable_input_confirm_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('variable_error_env')), findsOneWidget);
    expect(find.byKey(const Key('variable_error_token')), findsOneWidget);
    expect(find.byKey(const Key('variable_error_note')), findsOneWidget);
    // The optional one, prefilled anyway, raises nothing.
    expect(find.byKey(const Key('variable_error_region')), findsNothing);
    expect(result, isNull);

    await fill(tester);
    await tester.tap(find.byKey(const Key('variable_input_confirm_button')));
    await tester.pumpAndSettle();
    expect(result, {
      'env': 'prod',
      'region': 'eu-1',
      'token': 's3cret',
      'note': 'v2',
    });
  });

  testWidgets('the last non-secret values come back, a secret never does', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await open(tester, container, (_) {});
    await fill(tester, region: 'us-2', note: 'second try');
    await tester.tap(find.byKey(const Key('variable_input_confirm_button')));
    await tester.pumpAndSettle();

    // Asked again in the same session.
    await open(tester, container, (_) {});
    expect(editable(tester, 'region').controller.text, 'us-2');
    expect(editable(tester, 'note').controller.text, 'second try');
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const Key('variable_input_env')),
          )
          .initialValue,
      'prod',
    );
    expect(editable(tester, 'token').controller.text, isEmpty);
  });

  testWidgets('what is remembered is per runbook or snippet', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await open(tester, container, (_) {});
    await fill(tester, note: 'only for rb');
    await tester.tap(find.byKey(const Key('variable_input_confirm_button')));
    await tester.pumpAndSettle();

    await open(tester, container, (_) {}, memoryKey: 'runbook:other');
    expect(editable(tester, 'note').controller.text, isEmpty);
  });

  testWidgets('with no memory key nothing is remembered', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await open(tester, container, (_) {}, memoryKey: null);
    await fill(tester, note: 'forgotten');
    await tester.tap(find.byKey(const Key('variable_input_confirm_button')));
    await tester.pumpAndSettle();

    await open(tester, container, (_) {}, memoryKey: null);
    expect(editable(tester, 'note').controller.text, isEmpty);
  });

  testWidgets('cancel returns nothing', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    Map<String, String>? result = {};
    await open(tester, container, (r) => result = r);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
