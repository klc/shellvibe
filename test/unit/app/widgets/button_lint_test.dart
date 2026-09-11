import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Scans the presentation layer for buttons written outside the house
/// component, so the interface cannot drift back into six kinds of button.
///
/// It had drifted once already. `ShellVibeBrandButton` and its quiet sibling
/// were written to be the app's buttons, then reached from three files while
/// everything else went straight to the library or rolled its own — which is
/// how the app ended up with icon buttons at 30, 32, 34 and 36px, in three
/// different greys, at three different radii. A component nothing enforces is
/// a suggestion.
void main() {
  /// Where the house buttons themselves are built.
  const componentLayer = {'lib/app/widgets/shellvibe_ui.dart'};

  /// Buttons that are a different affordance rather than a different style,
  /// with the reason each is not a [ShellVibeButton].
  const exempt = <String, String>{
    'lib/app/widgets/app_navigation_shell.dart':
        '_RailButton is a navigation item — it carries a selected state and '
        'stacks its label under its glyph, which no button does',
    'lib/features/terminal/presentation/views/terminal_tab_view.dart':
        '_TabBarIconButton is shaped as a tab: full tab-strip height, rounded '
        'on the top corners only, and ruled on three sides so it joins the '
        'strip rather than floating on it',
  };

  /// `File.path` uses the host separator; the lists here are posix.
  String posix(String path) => path.replaceAll(r'\', '/');

  /// Button widgets that must not appear outside the component layer. Each was
  /// in the codebase before the unification and is gone from it now.
  final banned = RegExp(
    r'\b(ShadButton|ShadIconButton|IconButton|ElevatedButton|OutlinedButton'
    r'|FilledButton|TextButton|MaterialButton|CupertinoButton)\b',
  );

  /// A locally declared button class — the other way the house component gets
  /// bypassed, and the one that produced the four icon-button sizes.
  final localButtonClass = RegExp(r'^class\s+_\w*Button\b', multiLine: true);

  List<File> presentationFiles() =>
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !componentLayer.contains(posix(f.path)))
          .toList()
        ..sort((a, b) => posix(a.path).compareTo(posix(b.path)));

  /// Strips `//` comments so prose about a retired widget is not a violation.
  String withoutComments(String source) => source
      .split('\n')
      .map((l) => l.trimLeft().startsWith('//') ? '' : l)
      .join('\n');

  test('no library or ad-hoc button survives outside the house component', () {
    final violations = <String>[];
    for (final file in presentationFiles()) {
      final path = posix(file.path);
      final source = withoutComments(file.readAsStringSync());
      for (final m in banned.allMatches(source)) {
        violations.add('$path: ${m.group(1)}');
      }
      if (exempt.containsKey(path)) continue;
      for (final m in localButtonClass.allMatches(source)) {
        violations.add('$path: ${m.group(0)?.trim()}');
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'Use ShellVibeButton or ShellVibeIconButton. A button that needs '
          'something they do not offer is a change to the component, not a '
          'seventh kind of button:\n${violations.join('\n')}',
    );
  });

  test('the exemptions still name files that exist', () {
    for (final path in exempt.keys) {
      expect(
        File(path).existsSync(),
        isTrue,
        reason: '$path is exempted but is not in the tree any more',
      );
    }
  });
}
