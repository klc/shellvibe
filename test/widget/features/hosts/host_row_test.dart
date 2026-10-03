import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/app/theme/shellvibe_tokens.dart';
import 'package:shellvibe/core/utils/platform_capabilities.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/hosts/presentation/widgets/host_list_header.dart';
import 'package:shellvibe/features/hosts/presentation/widgets/host_row.dart';

/// The row's trailing controls sit in a slot of fixed width so the header can
/// line its columns up with them. On a touch host every control grows to the
/// touch target, and a slot measured under a pointer overflowed an iPad row.
void main() {
  tearDown(() {
    debugPlatformCapabilitiesOverride = null;
  });

  final host = HostModel(
    id: 'h1',
    workspaceId: 'default',
    label: 'Test Box',
    hostname: '10.0.0.5',
    username: 'root',
    port: 22,
    createdAt: DateTime(2026),
  );

  final platforms = TargetPlatformVariant({
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.macOS,
  });

  /// Pumps one row on the platform the variant set, and returns the slot's
  /// width alongside the width the header reserves for it.
  Future<(double, double)> pumpRow(
    WidgetTester tester, {
    required bool selected,
    required bool compact,
  }) async {
    debugPlatformCapabilitiesOverride = defaultTargetPlatform;
    tester.view.physicalSize = const Size(1032, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ShadTheme(
        data: ShadThemeData(
          colorScheme: const ShadSlateColorScheme.dark(),
          brightness: Brightness.dark,
        ),
        child: MaterialApp(
          home: Material(
            child: SizedBox(
              width: compact ? 390 : 1000,
              child: HostRow(
                host: host,
                groups: const [],
                connected: false,
                isConnecting: false,
                selected: selected,
                compact: compact,
                isFavorite: true,
                onSelect: () {},
                onConnect: () {},
                onOpenSftp: () {},
                onEdit: () {},
                onDelete: () {},
                onToggleFavorite: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final tokens = ShellVibeTokens.resolve(
      tester.element(find.byType(HostRow)),
    );
    return (
      tester.getSize(find.byKey(const Key('host_actions_h1'))).width,
      hostActionsWidth(tokens, compact: compact),
    );
  }

  testWidgets('a wide row fits its trailing controls', (tester) async {
    final (slot, reserved) = await pumpRow(
      tester,
      selected: false,
      compact: false,
    );

    expect(tester.takeException(), isNull);
    expect(slot, reserved);
  }, variant: platforms);

  testWidgets('a selected wide row fits its Open pill', (tester) async {
    final (slot, reserved) = await pumpRow(
      tester,
      selected: true,
      compact: false,
    );

    expect(tester.takeException(), isNull);
    expect(slot, reserved);
  }, variant: platforms);

  testWidgets('a phone row fits its trailing controls', (tester) async {
    final (slot, reserved) = await pumpRow(
      tester,
      selected: false,
      compact: true,
    );

    expect(tester.takeException(), isNull);
    expect(slot, reserved);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
