import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/graph/ui/widget/adaptive_context_overlay.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _mapHeight = 400.0;

Future<void> _pumpSheet(
  WidgetTester tester, {
  required bool reduceMotion,
  VoidCallback? onDismiss,
  ValueChanged<double>? onExtent,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 800),
          disableAnimations: reduceMotion,
        ),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: SizedBox(
              height: _mapHeight,
              child: Stack(
                children: [
                  const ColoredBox(
                    color: Color(0xFFE0E0E0),
                    child: SizedBox.expand(),
                  ),
                  AdaptiveContextOverlay(
                    compactDetents: true,
                    mapStackHeight: _mapHeight,
                    onDismiss: onDismiss,
                    onCompactExtentChanged: onExtent,
                    child: const ColoredBox(color: Colors.blue),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('AdaptiveContextOverlay compact detents', () {
    testWidgets('opens at peek height against map stack', (tester) async {
      double? extent;
      await _pumpSheet(
        tester,
        reduceMotion: true,
        onExtent: (h) => extent = h,
      );
      await tester.pump();
      final tt = tester.element(find.byType(AdaptiveContextOverlay)).tt;
      expect(extent, closeTo(_mapHeight * tt.fieldSheetPeekFraction, 1));
      expect(
        find.byKey(const Key('field.context_sheet.handle')),
        findsOneWidget,
      );
    });

    testWidgets('handle tap toggles expanded detent', (tester) async {
      await _pumpSheet(tester, reduceMotion: true);
      await tester.pump();
      final handle = find.byKey(const Key('field.context_sheet.handle'));
      final tt = tester.element(handle).tt;
      final peek = _mapHeight * tt.fieldSheetPeekFraction;
      final sheetBefore = tester.getSize(find.byType(AnimatedContainer));
      expect(sheetBefore.height, closeTo(peek, 1));

      await tester.tap(handle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final expandedCap = _mapHeight - tt.fieldSheetMinMapHeight;
      expect(
        tester.getSize(find.byType(AnimatedContainer)).height,
        closeTo(expandedCap, 2),
      );
    });

    testWidgets('reduced motion lands on target height after one pump', (
      tester,
    ) async {
      await _pumpSheet(tester, reduceMotion: true);
      await tester.pump();
      await tester.tap(find.byKey(const Key('field.context_sheet.handle')));
      await tester.pump();
      final tt = tester.element(find.byType(AdaptiveContextOverlay)).tt;
      expect(
        tester.getSize(find.byType(AnimatedContainer)).height,
        closeTo(_mapHeight - tt.fieldSheetMinMapHeight, 1),
      );
    });
  });
}
