import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_placement_marker.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// Contract of the marker shown on a node whose placement did not reach the
// server: `status` selects the "Saving…" cue or the "Not saved" badge, and the
// badge offers Retry and Discard through a secondary-tap menu, a hover toolbar
// and a plain tap (touch has neither), never through a long press alone.
//
// Pinned API shape (the task names none, so these are the contract chosen
// here): `ConstellationPlacementMarker({status, onRetry, onDiscard})` and
// `ConstellationPlacementMarkerStatus.{notSaved, saving}`.

Map<String, dynamic> _en = {};

String _text(String key) => _en[key] as String;

/// The exact copy for [key], rendered inside the marker badge itself.
Finder _inBadge(String key) => find.descendant(
  of: find.byType(ConstellationPlacementMarker),
  matching: find.text(_text(key)),
);

Future<void> _pumpMarker(
  WidgetTester tester, {
  ConstellationPlacementMarkerStatus status =
      ConstellationPlacementMarkerStatus.notSaved,
  VoidCallback? onRetry,
  VoidCallback? onDiscard,
}) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('en'),
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: Center(
        child: ConstellationPlacementMarker(
          status: status,
          onRetry: onRetry ?? () {},
          onDiscard: onDiscard ?? () {},
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(() {
    _en =
        jsonDecode(File('l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
  });

  group('Placement marker', () {
    testWidgets('a not-saved marker says the move was not saved', (
      tester,
    ) async {
      await _pumpMarker(tester);

      expect(find.byType(ConstellationPlacementMarker), findsOneWidget);
      expect(_inBadge('constellationPlacementNotSaved'), findsOneWidget);
      expect(find.text(_text('constellationPlacementSaving')), findsNothing);
    });

    testWidgets('a saving marker shows the cue and offers no actions', (
      tester,
    ) async {
      await _pumpMarker(
        tester,
        status: ConstellationPlacementMarkerStatus.saving,
      );

      expect(_inBadge('constellationPlacementSaving'), findsOneWidget);
      expect(
        find.textContaining(_text('constellationPlacementNotSaved')),
        findsNothing,
      );
      await tester.tap(find.byType(ConstellationPlacementMarker));
      await tester.pump();
      expect(find.text(_text('constellationPlacementRetry')), findsNothing);
      expect(find.text(_text('constellationPlacementDiscard')), findsNothing);
    });

    testWidgets('a plain tap opens Retry and Discard for touch users', (
      tester,
    ) async {
      await _pumpMarker(tester);
      expect(find.text(_text('constellationPlacementRetry')), findsNothing);

      await tester.tap(find.byType(ConstellationPlacementMarker));
      await tester.pumpAndSettle();

      expect(find.text(_text('constellationPlacementRetry')), findsOneWidget);
      expect(find.text(_text('constellationPlacementDiscard')), findsOneWidget);
    });

    testWidgets('a secondary tap opens Retry and Discard', (tester) async {
      await _pumpMarker(tester);

      await tester.tap(
        find.byType(ConstellationPlacementMarker),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(find.text(_text('constellationPlacementRetry')), findsOneWidget);
      expect(find.text(_text('constellationPlacementDiscard')), findsOneWidget);
    });

    testWidgets('holding a press without releasing does not open the actions', (
      tester,
    ) async {
      await _pumpMarker(tester);

      final press = await tester.startGesture(
        tester.getCenter(find.byType(ConstellationPlacementMarker)),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text(_text('constellationPlacementRetry')), findsNothing);
      expect(find.text(_text('constellationPlacementDiscard')), findsNothing);
      await press.cancel();
    });

    testWidgets('hovering with a mouse reveals the Retry and Discard toolbar', (
      tester,
    ) async {
      await _pumpMarker(tester);
      expect(find.text(_text('constellationPlacementRetry')), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.byType(ConstellationPlacementMarker)),
      );
      await tester.pumpAndSettle();

      expect(find.text(_text('constellationPlacementRetry')), findsOneWidget);
      expect(find.text(_text('constellationPlacementDiscard')), findsOneWidget);

      await mouse.moveTo(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text(_text('constellationPlacementRetry')), findsNothing);
    });

    testWidgets('choosing Retry calls onRetry once and not onDiscard', (
      tester,
    ) async {
      var retries = 0;
      var discards = 0;
      await _pumpMarker(
        tester,
        onRetry: () => retries++,
        onDiscard: () => discards++,
      );

      await tester.tap(find.byType(ConstellationPlacementMarker));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_text('constellationPlacementRetry')));
      await tester.pumpAndSettle();

      expect(retries, 1);
      expect(discards, 0);
    });

    testWidgets('choosing Discard calls onDiscard once and not onRetry', (
      tester,
    ) async {
      var retries = 0;
      var discards = 0;
      await _pumpMarker(
        tester,
        onRetry: () => retries++,
        onDiscard: () => discards++,
      );

      await tester.tap(find.byType(ConstellationPlacementMarker));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_text('constellationPlacementDiscard')));
      await tester.pumpAndSettle();

      expect(discards, 1);
      expect(retries, 0);
    });

    testWidgets('the not-saved marker is announced as a button', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpMarker(tester);

      final node = tester.getSemantics(
        find.byType(ConstellationPlacementMarker),
      );
      expect(node.label, contains(_text('constellationPlacementNotSaved')));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      semantics.dispose();
    });
  });
}
