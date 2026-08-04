import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:terly2/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:terly2/features/terminal/presentation/widgets/resizable_split.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Pumps a 800x400 `ResizableSplit` and drags its divider by [offset].
  /// Returns the ratio reported by `onRatioChanged` after the gesture.
  ///
  /// The drag recognizer consumes ~18px of touch slop before the divider
  /// starts moving, so exact pixel offsets are not asserted; instead tests
  /// assert direction, clamping, and that pane geometry always matches the
  /// reported ratio exactly (widths/height sum minus the 10px divider).
  Future<double> pumpAndDrag(
    WidgetTester tester, {
    required Axis axis,
    required Offset offset,
    double initial = 0.5,
  }) async {
    double? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 400,
            child: StatefulBuilder(
              builder: (context, setState) => ResizableSplit(
                axis: axis,
                ratio: captured ?? initial,
                first: Container(key: const Key('first'), color: Colors.red),
                second:
                    Container(key: const Key('second'), color: Colors.blue),
                dividerColor: Colors.black,
                onRatioChanged: (r) => setState(() => captured = r),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('split_divider')),
      offset,
    );
    await tester.pump();
    return captured!;
  }

  // The 10px divider leaves 790 shared px across 800 total width.
  double firstWidthOfRatio(double ratio) => 790 * (1 - ratio);
  double secondWidthOfRatio(double ratio) => 790 * ratio;

  group('ResizableSplit', () {
    testWidgets('horizontal drag right moves the divider right (first grows)',
        (tester) async {
      final ratio = await pumpAndDrag(
        tester,
        axis: Axis.horizontal,
        offset: const Offset(120, 0),
      );
      // Divider follows the pointer: dragging right shrinks [second]'s share.
      expect(ratio, lessThan(0.5));
      expect(ratio, greaterThan(kSplitPaneMinRatio));
      // pane widths track the reported ratio exactly
      expect(tester.getSize(find.byKey(const Key('first'))).width,
          closeTo(firstWidthOfRatio(ratio), 1));
      expect(tester.getSize(find.byKey(const Key('second'))).width,
          closeTo(secondWidthOfRatio(ratio), 1));
      // total pane span is stable: 800 - 10px divider
      expect(
        tester.getSize(find.byKey(const Key('first'))).width +
            tester.getSize(find.byKey(const Key('second'))).width,
        closeTo(790, 1),
      );
    });

    testWidgets('horizontal drag left moves the divider left (second grows)',
        (tester) async {
      final ratio = await pumpAndDrag(
        tester,
        axis: Axis.horizontal,
        offset: const Offset(-120, 0),
      );
      expect(ratio, greaterThan(0.5));
      expect(ratio, lessThan(kSplitPaneMaxRatio));
    });

    testWidgets('horizontal drag clamps to max ratio', (tester) async {
      final ratio = await pumpAndDrag(
        tester,
        axis: Axis.horizontal,
        offset: const Offset(-5000, 0),
      );
      expect(ratio, kSplitPaneMaxRatio);
    });

    testWidgets('horizontal drag clamps to min ratio', (tester) async {
      final ratio = await pumpAndDrag(
        tester,
        axis: Axis.horizontal,
        offset: const Offset(5000, 0),
      );
      expect(ratio, kSplitPaneMinRatio);
    });

    testWidgets('vertical axis drag down moves the divider down (top grows)',
        (tester) async {
      final ratio = await pumpAndDrag(
        tester,
        axis: Axis.vertical,
        offset: const Offset(0, 120),
      );
      expect(ratio, lessThan(0.5));
      // top pane shrinks; heights sum to 400 - 10px divider
      final firstH = tester.getSize(find.byKey(const Key('first'))).height;
      final secondH = tester.getSize(find.byKey(const Key('second'))).height;
      expect(firstH, closeTo(390 * (1 - ratio), 1));
      expect(secondH, closeTo(390 * ratio, 1));
      expect(firstH + secondH, closeTo(390, 1));
    });

    testWidgets('a ratio the owner does not publish is not kept locally',
        (tester) async {
      // The owner is free to ignore or clamp what a drag reports (a notifier
      // may reject it, or already be at that value). The pane must then go
      // back to the owner's ratio rather than sit at one only it knows about
      // — which would survive until the next drag and then be lost anyway.
      var reported = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: ResizableSplit(
                axis: Axis.horizontal,
                ratio: 0.5,
                first: Container(key: const Key('first'), color: Colors.red),
                second: Container(key: const Key('second'), color: Colors.blue),
                dividerColor: Colors.black,
                onRatioChanged: (_) => reported++,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('split_divider'))),
      );
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const Key('first'))).width,
        greaterThan(500), // local drag ratio is in effect mid-gesture
      );

      await gesture.up();
      await tester.pump();

      expect(reported, 1); // the owner heard about it...
      // ...and, having kept ratio at 0.5, that is where the pane sits.
      expect(
        tester.getSize(find.byKey(const Key('first'))).width,
        closeTo(firstWidthOfRatio(0.5), 1),
      );
    });

    testWidgets('shows resize cursor over the divider on desktop-like platform',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: ResizableSplit(
                axis: Axis.horizontal,
                ratio: 0.5,
                first: const SizedBox(),
                second: const SizedBox(),
                dividerColor: Colors.black,
                onRatioChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final mouseRegion = tester.widget<MouseRegion>(
        find
            .descendant(
              of: find.byKey(const ValueKey('split_divider')),
              matching: find.byType(MouseRegion),
            )
            .first,
      );
      expect(mouseRegion.cursor, SystemMouseCursors.resizeLeftRight);
    });
  });
}