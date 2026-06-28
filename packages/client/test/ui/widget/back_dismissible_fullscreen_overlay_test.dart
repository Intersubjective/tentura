import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/widget/back_dismissible_fullscreen_overlay.dart';

void main() {
  tearDown(() {
    expect(BackDismissibleFullscreenOverlay.hasOpenOverlay, isFalse);
  });

  Future<void> pumpHarness(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  unawaited(
                    pushBackDismissibleFullscreenOverlay<void>(
                      context,
                      Material(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('fullscreen overlay'),
                              TextButton(
                                onPressed: () => Navigator.of(
                                  context,
                                  rootNavigator: true,
                                ).pop(),
                                child: const Text('close overlay'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('open overlay'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('system back closes the fullscreen overlay first', (
    tester,
  ) async {
    await pumpHarness(tester);

    await tester.tap(find.text('open overlay'));
    await tester.pumpAndSettle();

    expect(find.text('fullscreen overlay'), findsOneWidget);
    expect(BackDismissibleFullscreenOverlay.hasOpenOverlay, isTrue);

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(find.text('fullscreen overlay'), findsNothing);
    expect(BackDismissibleFullscreenOverlay.hasOpenOverlay, isFalse);
    expect(find.text('open overlay'), findsOneWidget);
  });

  testWidgets('parent guard pop uses the overlay back path', (tester) async {
    await pumpHarness(tester);

    await tester.tap(find.text('open overlay'));
    await tester.pumpAndSettle();

    expect(find.text('fullscreen overlay'), findsOneWidget);

    final popped = BackDismissibleFullscreenOverlay.popTopOverlay();
    await tester.pumpAndSettle();

    expect(popped, isTrue);
    expect(find.text('fullscreen overlay'), findsNothing);
    expect(BackDismissibleFullscreenOverlay.hasOpenOverlay, isFalse);
    expect(find.text('open overlay'), findsOneWidget);
  });

  testWidgets('explicit close unregisters the fullscreen overlay', (
    tester,
  ) async {
    await pumpHarness(tester);

    await tester.tap(find.text('open overlay'));
    await tester.pumpAndSettle();

    expect(BackDismissibleFullscreenOverlay.hasOpenOverlay, isTrue);

    await tester.tap(find.text('close overlay'));
    await tester.pumpAndSettle();

    expect(find.text('fullscreen overlay'), findsNothing);
    expect(BackDismissibleFullscreenOverlay.hasOpenOverlay, isFalse);
    expect(find.text('open overlay'), findsOneWidget);
  });
}
