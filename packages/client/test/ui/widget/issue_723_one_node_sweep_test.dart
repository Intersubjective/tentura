// #723 sweep: the same `Semantics(button: true, child: <Button>)` wrapper
// that made the composer read `button "Emoji" > button "Emoji"` sat on the
// inbox card actions (Offer help, Forward, dismiss) and on the author's
// "Mark enough help" confirm. Each is now one node carrying the name, the
// tap and the e2e identifier.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/request_attention_predicate.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_author_confirm_sheets.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/card_triage_action_row.dart';

import '../../support/semantics_identifier.dart';

Widget _host(Widget child) {
  const size = Size(1280, 800);
  return MaterialApp(
    locale: const Locale('en'),
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: MediaQuery(
      data: const MediaQueryData(size: size),
      child: TenturaResponsiveScope(
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

List<SemanticsNode> _nodes(bool Function(SemanticsNode node) test) =>
    find.semantics.byPredicate(test).evaluate().toList();

bool _isButton(SemanticsNode node) =>
    node.getSemanticsData().flagsCollection.isButton;

List<SemanticsNode> _buttonsInside(SemanticsNode node) {
  final out = <SemanticsNode>[];
  bool visit(SemanticsNode child) {
    if (_isButton(child)) out.add(child);
    child.visitChildren(visit);
    return true;
  }

  node.visitChildren(visit);
  return out;
}

/// Exactly one node has [identifier]; it is the button named [name], with a
/// tap, no button inside it, and no other button carries the same name.
void _expectOneNode(String identifier, String name) {
  final withId = _nodes((n) => n.getSemanticsData().identifier == identifier);
  expect(withId, hasLength(1), reason: 'nodes with $identifier');
  final node = withId.single;
  expect(
    node,
    allOf(
      isSemantics(label: name, isButton: true, hasTapAction: true),
      hasSemanticsIdentifier(identifier),
    ),
  );
  expect(_buttonsInside(node), isEmpty, reason: 'a button inside $name');
  final named = _nodes((n) {
    final d = n.getSemanticsData();
    return _isButton(n) && (d.label == name || d.tooltip == name);
  });
  expect(named, hasLength(1), reason: 'buttons named $name');
}

void main() {
  group('CardTriageActionRow', () {
    testWidgets('Offer help, Forward and dismiss are one node each', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var offers = 0;
      var forwards = 0;
      var dismissals = 0;
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 600,
            child: CardTriageActionRow(
              onOfferHelp: () async => offers++,
              onForward: () => forwards++,
              secondaryIcon: Icons.close,
              secondaryTooltip: 'Remove from Activity',
              onSecondary: () async => dismissals++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      _expectOneNode(TestIds.inboxOfferHelp, 'Offer help');
      _expectOneNode(TestIds.inboxForward, 'Forward');
      _expectOneNode(TestIds.inboxDismiss, 'Remove from Activity');

      // The screen-reader tap still runs each action.
      for (final id in [
        TestIds.inboxOfferHelp,
        TestIds.inboxForward,
        TestIds.inboxDismiss,
      ]) {
        tester.semantics.tap(
          find.semantics.byPredicate(
            (n) => n.getSemanticsData().identifier == id,
          ),
        );
        await tester.pump();
      }
      expect((offers, forwards, dismissals), (1, 1, 1));
      handle.dispose();
    });

    // Guard: an ordinary tap on the visible buttons still works.
    testWidgets('tapping the buttons runs their actions', (tester) async {
      var offers = 0;
      var forwards = 0;
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 600,
            child: CardTriageActionRow(
              onOfferHelp: () async => offers++,
              onForward: () => forwards++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(TestIds.key(TestIds.inboxOfferHelp)));
      await tester.tap(find.byKey(TestIds.key(TestIds.inboxForward)));
      await tester.pump();
      expect((offers, forwards), (1, 1));
    });
  });

  testWidgets('RequestAttentionCard: Offer help is one node', (tester) async {
    final handle = tester.ensureSemantics();
    var offers = 0;
    await tester.pumpWidget(
      _host(
        RequestAttentionCard(
          beacon: Beacon(
            id: 'b723',
            title: 'Move boxes',
            createdAt: DateTime.utc(2026, 10),
            updatedAt: DateTime.utc(2026, 10),
            author: const Profile(id: 'a1', displayName: 'Ana'),
          ),
          variant: RequestAttentionCardVariant.pinned,
          facts: const RequestAttentionFacts(
            requestId: 'b723',
            pendingForward: true,
          ),
          onOpenBeacon: () {},
          onOpenTimeline: () {},
          onOfferHelp: () => offers++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    _expectOneNode(TestIds.inboxOfferHelp, 'Offer help');
    tester.semantics.tap(
      find.semantics.byPredicate(
        (n) => n.getSemanticsData().identifier == TestIds.inboxOfferHelp,
      ),
    );
    await tester.pump();
    expect(offers, 1);
    handle.dispose();
  });

  testWidgets('Mark enough help confirm is one node and confirms', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    bool? confirmed;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              confirmed = await showBeaconHudMarkEnoughHelpConfirmSheet(
                context: context,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    _expectOneNode(TestIds.beaconHudMarkEnoughHelpConfirm, 'Mark enough help');
    tester.semantics.tap(
      find.semantics.byPredicate(
        (n) =>
            n.getSemanticsData().identifier ==
            TestIds.beaconHudMarkEnoughHelpConfirm,
      ),
    );
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
    handle.dispose();
  });
}
