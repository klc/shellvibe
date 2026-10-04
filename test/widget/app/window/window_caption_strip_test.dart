import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/app/widgets/window_caption_strip.dart';
import 'package:shellvibe/app/window/window_chrome.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('window_manager');
  late List<String> calls;
  late bool maximized;

  setUp(() {
    calls = [];
    maximized = false;
    debugWindowChromeOverride = TargetPlatform.linux;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'isMaximized':
              return maximized;
            case 'maximize':
              maximized = true;
            case 'unmaximize':
              maximized = false;
          }
          return null;
        });
  });

  tearDown(() {
    debugWindowChromeOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpStrip(WidgetTester tester) async {
    await tester.pumpWidget(
      ShadTheme(
        data: ShadThemeData(
          colorScheme: const ShadSlateColorScheme.dark(),
          brightness: Brightness.dark,
        ),
        child: const MaterialApp(home: Scaffold(body: WindowCaptionStrip())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('each button drives the window', (tester) async {
    await pumpStrip(tester);

    await tester.tap(find.byKey(const Key('window_caption_minimize')));
    await tester.tap(find.byKey(const Key('window_caption_maximize')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('window_caption_close')));
    await tester.pumpAndSettle();

    expect(calls, containsAllInOrder(['minimize', 'maximize', 'close']));
  });

  testWidgets('a maximised window offers restore instead', (tester) async {
    maximized = true;
    await pumpStrip(tester);

    expect(find.byTooltip('Restore'), findsOneWidget);
    await tester.tap(find.byKey(const Key('window_caption_maximize')));
    await tester.pumpAndSettle();

    expect(calls, contains('unmaximize'));
  });

  testWidgets('draws nothing where the platform keeps its title bar', (
    tester,
  ) async {
    debugWindowChromeOverride = TargetPlatform.android;
    await pumpStrip(tester);

    expect(find.byKey(const Key('window_caption_close')), findsNothing);
  });
}
