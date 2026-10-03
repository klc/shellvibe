import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/app/widgets/shellvibe_ui.dart';

/// On a wide screen the actions of a page header and a work toolbar sit at
/// the right edge. They used to stop near the middle: the row splits its
/// width between title and actions, and the Wrap holding the actions shrank
/// to them at the left of its half.
void main() {
  const width = 1200.0;
  const action = Key('header_action');

  Future<void> pumpAt(WidgetTester tester, Widget header) async {
    tester.view.physicalSize = const Size(width, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShadApp(
        home: Material(
          child: Align(alignment: Alignment.topLeft, child: header),
        ),
      ),
    );
  }

  Widget button() => const SizedBox(key: action, width: 100, height: 32);

  testWidgets('ShellVibePageHeader puts its actions at the right edge', (
    tester,
  ) async {
    await pumpAt(
      tester,
      ShellVibePageHeader(
        icon: Icons.add,
        title: 'Tunnels',
        actions: [button()],
      ),
    );
    final headerRight = tester.getTopRight(find.byType(ShellVibePageHeader)).dx;
    expect(tester.getTopRight(find.byKey(action)).dx, closeTo(headerRight, 32));
  });

  testWidgets('ShellVibeWorkToolbar puts its actions at the right edge', (
    tester,
  ) async {
    await pumpAt(
      tester,
      ShellVibeWorkToolbar(title: 'All snippets', actions: [button()]),
    );
    final toolbarRight = tester
        .getTopRight(find.byType(ShellVibeWorkToolbar))
        .dx;
    expect(
      tester.getTopRight(find.byKey(action)).dx,
      closeTo(toolbarRight, 32),
    );
  });
}
