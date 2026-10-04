import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/features/snippets/domain/models/snippet_model.dart';
import 'package:shellvibe/features/snippets/domain/models/variable_declaration.dart';
import 'package:shellvibe/features/snippets/presentation/widgets/snippet_form_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> open(
    WidgetTester tester,
    void Function(SnippetModel?) onResult, {
    SnippetModel? snippet,
  }) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShadTheme(
        data: ShadThemeData(
          colorScheme: const ShadSlateColorScheme.light(),
          brightness: Brightness.light,
        ),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => onResult(
                  await SnippetFormDialog.show(
                    context,
                    snippet: snippet,
                    workspaceId: 'default',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the helper text explains both kinds of placeholder', (
    tester,
  ) async {
    await open(tester, (_) {});
    final help = tester.widget<Text>(find.byKey(const Key('placeholder_help')));
    expect(help.data, contains(r'${INPUT:name}'));
    expect(help.data, contains(r'${SV:HOST}'));
    expect(help.data, contains(r'${SV:HOST_LABEL}'));
    expect(help.data, contains(r'${SV:USER}'));
    expect(help.data, contains(r'${SV:PORT}'));
  });

  testWidgets('placeholders in the code get rows; declarations are saved', (
    tester,
  ) async {
    SnippetModel? saved;
    await open(tester, (r) => saved = r);
    expect(find.byKey(const Key('variables_empty')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('snippet_title_field')),
      'Deploy',
    );
    await tester.enterText(
      find.byKey(const Key('snippet_code_field')),
      r'deploy ${INPUT:env} ${INPUT:pw} ${SV:HOST} ${HOME}',
    );
    await tester.pumpAndSettle();

    // One row per prompted placeholder; the per-host and shell ones are not.
    expect(find.byKey(const Key('variable_row_env')), findsOneWidget);
    expect(find.byKey(const Key('variable_row_pw')), findsOneWidget);
    expect(find.byKey(const Key('variable_row_HOST')), findsNothing);
    expect(find.byKey(const Key('variable_row_HOME')), findsNothing);

    await tester.tap(find.byKey(const Key('variable_type_env_enum')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('variable_options_env')),
      'staging, prod',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('variable_default_env')),
      'staging',
    );
    await tester.tap(find.byKey(const Key('variable_type_pw_secret')));
    await tester.pumpAndSettle();
    // A secret has no default to type.
    expect(find.byKey(const Key('variable_default_pw')), findsNothing);

    await tester.tap(find.byKey(const Key('snippet_save_button')));
    await tester.pumpAndSettle();

    final env = saved!.variables.firstWhere((v) => v.name == 'env');
    expect(env.type, VariableType.enumeration);
    expect(env.options, ['staging', 'prod']);
    expect(env.defaultValue, 'staging');
    final pw = saved!.variables.firstWhere((v) => v.name == 'pw');
    expect(pw.type, VariableType.secret);
    expect(pw.defaultValue, isNull);
  });

  testWidgets('a declaration whose placeholder is gone is dropped on save', (
    tester,
  ) async {
    SnippetModel? saved;
    await open(
      tester,
      (r) => saved = r,
      snippet: const SnippetModel(
        id: 'sn',
        workspaceId: 'default',
        title: 'Deploy',
        code: r'deploy ${INPUT:env} ${INPUT:gone}',
        variables: [
          VariableDeclaration(name: 'env', type: VariableType.secret),
          VariableDeclaration(name: 'gone', type: VariableType.secret),
        ],
      ),
    );

    await tester.enterText(
      find.byKey(const Key('snippet_code_field')),
      r'deploy ${INPUT:env}',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('variable_row_gone')), findsNothing);

    await tester.tap(find.byKey(const Key('snippet_save_button')));
    await tester.pumpAndSettle();
    expect(saved!.variables.map((v) => v.name), ['env']);
  });

  testWidgets('a placeholder left as plain required text stores nothing', (
    tester,
  ) async {
    SnippetModel? saved;
    await open(tester, (r) => saved = r);
    await tester.enterText(find.byKey(const Key('snippet_title_field')), 'T');
    await tester.enterText(
      find.byKey(const Key('snippet_code_field')),
      r'echo ${INPUT:x}',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('snippet_save_button')));
    await tester.pumpAndSettle();
    expect(saved!.variables, isEmpty);
  });
}
