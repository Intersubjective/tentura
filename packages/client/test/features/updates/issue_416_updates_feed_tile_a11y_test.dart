// #416: an Activity row says "Dismiss update" once, a feed row menu is not
// the generic "Show menu", and the actor avatar reads "<Name>, open profile".
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/a11y_spoken.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _anna = Profile(id: 'u1', displayName: 'Anna Lee');

AttentionReceipt _receipt() => AttentionReceipt(
  id: 'r1',
  category: 'requestProgress',
  kind: 'helpOfferSubmitted',
  priority: 'normal',
  title: 'Offered help',
  body: 'Garden cleanup',
  actionUrl: '/#/view?id=b1',
  createdAt: DateTime.utc(2026, 6, 19, 16, 40),
  collapsedCount: 1,
  presentationKey: 'help_offer_submitted',
  presentationPayloadJson: '{}',
  surface: AttentionSurface.activity,
  actorUserId: _anna.id,
  beaconId: 'b1',
  itemKind: AttentionItemKind.requestActivity,
);

Future<void> _pump(
  WidgetTester tester, {
  bool activityRow = false,
  Locale locale = const Locale('en'),
}) async {
  final screen = ScreenCubit.local(FakeUiEffectPort());
  await tester.binding.setSurfaceSize(const Size(360, 200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    BlocProvider<ScreenCubit>.value(
      value: screen,
      child: MaterialApp(
        locale: locale,
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 200)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: UpdatesFeedTile(
                receipt: _receipt(),
                actor: _anna,
                onTap: () {},
                onMarkSeen: () {},
                onMarkUnseen: () {},
                activityRow: activityRow,
                onDismiss: activityRow ? () {} : null,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Engine-visible semantics nodes owned by render objects inside [finder]'s
/// subtree that carry a tap action of their own.
List<SemanticsNode> _ownTapNodesUnder(Finder finder) {
  final nodes = <SemanticsNode>{};
  void visit(Element element) {
    final node = element.renderObject?.debugSemantics;
    if (node != null &&
        !node.isMergedIntoParent &&
        node.getSemanticsData().hasAction(SemanticsAction.tap)) {
      nodes.add(node);
    }
    element.visitChildren(visit);
  }

  visit(finder.evaluate().single);
  return nodes.toList();
}

void main() {
  testWidgets('an Activity row announces Dismiss update once', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, activityRow: true);

    expect(
      spokenCount('Dismiss update'),
      1,
      reason: spokenNodes().join(' | '),
    );
    handle.dispose();
  });

  testWidgets('the feed row menu is not the generic Show menu', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    final menu = find.byType(PopupMenuButton<void>);
    expect(menu, findsOneWidget);
    // The node that carries the menu's own tap action must carry its own
    // name: an ancestor (the row) being labelled does not count.
    final tapNodes = _ownTapNodesUnder(menu);
    expect(tapNodes, hasLength(1), reason: spokenNodes().join(' | '));
    final menuName = spokenTextOf(tapNodes.single);
    expect(menuName.trim(), isNotEmpty);
    expect(menuName, isNot(contains('Show menu')));
    expect(spokenCount('Show menu'), 0, reason: spokenNodes().join(' | '));
    handle.dispose();
  });

  testWidgets('the actor avatar reads <Name>, open profile', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    final node = tester.getSemantics(find.byType(TenturaAvatar));
    expect(node.label, 'Anna Lee, open profile');
    expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(spokenLines(), isNot(contains('AL')));
    handle.dispose();
  });

  testWidgets('the avatar name is localized', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, locale: const Locale('ru'));

    final node = tester.getSemantics(find.byType(TenturaAvatar));
    expect(node.label, 'Anna Lee, открыть профиль');
    expect(spokenLines(), isNot(contains('AL')));
    handle.dispose();
  });
}
