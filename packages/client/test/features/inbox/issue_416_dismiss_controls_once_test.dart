// #416: the three "Dismiss update" controls beside the mini card's — the
// Post row, the tombstone row and the Activity feed row — are each announced
// once, and that one announced control is the one that dismisses.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/widget/post_attention_row.dart';
import 'package:tentura/features/inbox/ui/widget/tombstone_row.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/a11y_spoken.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _dismiss = 'Dismiss update';
const _anna = Profile(id: 'u1', displayName: 'Anna Lee');

AttentionReceipt _postGroup() => AttentionReceipt(
  id: 'p1',
  category: 'requestProgress',
  kind: 'relayReceived',
  priority: 'normal',
  title: 'Recommend a dentist',
  body: 'Anna Lee',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 6, 19, 16, 40),
  collapsedCount: 1,
  presentationPayloadJson: '{"eventType":"relayReceived"}',
  surface: AttentionSurface.activity,
  beaconId: 'bpost1',
  beaconKind: kBeaconKindPost,
  beaconAuthorName: 'Anna Lee',
  postRootExcerpt: 'Recommend a dentist downtown',
);

AttentionReceipt _tombstone() => AttentionReceipt(
  id: 't1',
  category: 'forward',
  kind: 'relayReceived',
  priority: 'normal',
  title: 'Garden cleanup',
  body: 'Anna Lee',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 6, 19, 16, 40),
  collapsedCount: 1,
  presentationPayloadJson: '{"eventType":"relayReceived"}',
  surface: AttentionSurface.activity,
  beaconId: 'b1',
  seenAt: DateTime.utc(2026, 6, 19, 17),
  forwardOutcome: AttentionForwardOutcome.helping,
);

AttentionReceipt _activity() => AttentionReceipt(
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

Future<void> _pump(WidgetTester tester, Widget row) async {
  await tester.pumpWidget(
    BlocProvider<ScreenCubit>.value(
      value: ScreenCubit.local(FakeUiEffectPort()),
      child: MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 640)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(width: 360, child: row),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The control is announced once, and the screen reader's tap on that one
/// announced node dismisses (and only dismisses).
void _expectOneDismiss(
  WidgetTester tester, {
  required int Function() dismissed,
  required int Function() opened,
}) {
  expect(spokenCount(_dismiss), 1, reason: spokenNodes().join(' | '));
  tester.semantics.tap(find.semantics.byLabel(_dismiss));
  expect(dismissed(), 1);
  expect(opened(), 0);
}

void main() {
  testWidgets('the Post row dismiss is announced once and dismisses', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      var dismissed = 0;
      var opened = 0;
      await _pump(
        tester,
        PostAttentionRow(
          receipt: _postGroup(),
          onOpen: () => opened++,
          onDismiss: () => dismissed++,
        ),
      );

      expect(find.byKey(PostAttentionRow.dismissKey), findsOneWidget);
      _expectOneDismiss(
        tester,
        dismissed: () => dismissed,
        opened: () => opened,
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('the tombstone row dismiss is announced once and dismisses', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      var dismissed = 0;
      var opened = 0;
      await _pump(
        tester,
        TombstoneRow(
          receipt: _tombstone(),
          forwarder: _anna,
          onOpenBeacon: () => opened++,
          onDismiss: () => dismissed++,
        ),
      );

      expect(find.byKey(TombstoneRow.dismissKey), findsOneWidget);
      _expectOneDismiss(
        tester,
        dismissed: () => dismissed,
        opened: () => opened,
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('the Activity row dismiss is announced once and dismisses', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      var dismissed = 0;
      var opened = 0;
      await _pump(
        tester,
        UpdatesFeedTile(
          receipt: _activity(),
          actor: _anna,
          onTap: () => opened++,
          onMarkSeen: () {},
          onMarkUnseen: () {},
          activityRow: true,
          onDismiss: () => dismissed++,
        ),
      );

      _expectOneDismiss(
        tester,
        dismissed: () => dismissed,
        opened: () => opened,
      );
    } finally {
      handle.dispose();
    }
  });
}
