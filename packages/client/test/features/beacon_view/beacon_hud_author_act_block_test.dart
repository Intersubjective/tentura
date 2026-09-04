import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_view/ui/presenter/beacon_hud_author_action.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_author_act_block.dart';

BeaconHudAuthorActSpec _spec({
  required BeaconHudAuthorAction action,
  required BeaconHudAuthorActEffectPresentation effectPresentation,
  String label = 'Action',
  String effectLine = 'Effect outcome line',
}) =>
    BeaconHudAuthorActSpec(
      action: action,
      label: label,
      effectLine: effectLine,
      semanticsLabel: '$label. $effectLine',
      icon: Icons.check_circle_outline,
      filled: true,
      effectPresentation: effectPresentation,
    );

Future<void> _pumpBlock(
  WidgetTester tester,
  BeaconHudAuthorActSpec spec,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: BeaconHudAuthorActBlock(
            spec: spec,
            onPressed: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('BeaconHudAuthorActBlock effect presentation', () {
    testWidgets('hiddenKeepSemantics hides effect Text keeps semantics', (
      tester,
    ) async {
      final spec = _spec(
        action: BeaconHudAuthorAction.markEnoughHelp,
        effectPresentation:
            BeaconHudAuthorActEffectPresentation.hiddenKeepSemantics,
        label: 'We have enough help',
        effectLine: 'Signals helpers; request stays open',
      );
      await _pumpBlock(tester, spec);

      expect(find.text(spec.label), findsOneWidget);
      expect(find.text(spec.effectLine), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip && widget.message == spec.effectLine,
        ),
        findsNothing,
      );
      final semantics = tester.getSemantics(find.byType(BeaconHudAuthorActBlock));
      expect(semantics.label, spec.semanticsLabel);
      expect(semantics.flagsCollection.isButton, isTrue);
    });

    testWidgets('closeNow hiddenKeepSemantics hides effect Text', (
      tester,
    ) async {
      final spec = _spec(
        action: BeaconHudAuthorAction.closeNow,
        effectPresentation:
            BeaconHudAuthorActEffectPresentation.hiddenKeepSemantics,
        label: 'Close now',
        effectLine: 'Closes request when all reviews are in',
      );
      await _pumpBlock(tester, spec);

      expect(find.text(spec.effectLine), findsNothing);
      final semantics = tester.getSemantics(find.byType(BeaconHudAuthorActBlock));
      expect(semantics.label, spec.semanticsLabel);
      expect(semantics.flagsCollection.isButton, isTrue);
    });

    testWidgets('tooltip mode has no muted subtitle Text', (tester) async {
      final spec = _spec(
        action: BeaconHudAuthorAction.reviewOffers,
        effectPresentation: BeaconHudAuthorActEffectPresentation.tooltip,
        label: 'Review offers',
        effectLine: 'Opens People; accept adds helper to the discussion',
      );
      await _pumpBlock(tester, spec);

      expect(find.text(spec.effectLine), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip && widget.message == spec.effectLine,
        ),
        findsOneWidget,
      );
    });

    testWidgets('mutedSubtitle shows effect Text', (tester) async {
      final spec = _spec(
        action: BeaconHudAuthorAction.wrapUpForReview,
        effectPresentation: BeaconHudAuthorActEffectPresentation.mutedSubtitle,
        label: 'Wrap up for review',
        effectLine: 'Starts review window; helpers can acknowledge',
      );
      await _pumpBlock(tester, spec);

      expect(find.text(spec.effectLine), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip && widget.message == spec.effectLine,
        ),
        findsNothing,
      );
    });
  });
}
