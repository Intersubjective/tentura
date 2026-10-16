@Timeout(Duration(minutes: 2))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_pinned_block.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';

/// U092 — relative times froze: "Tab QA · Just now" stayed on the Now panel
/// for minutes because the age was computed once, when the widget was built.
/// Ages on screen must keep counting while the screen stays open.
const _me = Profile(id: 'ME', displayName: 'Nina');
const _author = Profile(id: 'UA', displayName: 'Tab QA');

void main() {
  var clock = DateTime.utc(2026, 10, 14, 9, 0, 30);

  setUp(() {
    clock = DateTime.utc(2026, 10, 14, 9, 0, 30);
    RelativeTimestampTicker.debugClock = () => clock;
  });
  tearDown(() => RelativeTimestampTicker.debugClock = null);

  testWidgets('the ticker re-runs its builder every 30 s', (tester) async {
    var builds = 0;
    await tester.pumpWidget(
      RelativeTimestampTicker(
        builder: (context) {
          builds++;
          return const SizedBox();
        },
      ),
    );
    expect(builds, 1);

    await tester.pump(const Duration(seconds: 31));
    expect(builds, 2);
    await tester.pump(const Duration(seconds: 30));
    expect(builds, 3);
  });

  testWidgets('the Now panel step age keeps counting while open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = BeaconViewState(
      beacon: Beacon.empty.copyWith(
        id: 'B1',
        updatedAt: DateTime.utc(2026),
        author: _author,
        status: BeaconStatus.open,
      ),
      myProfile: _me,
      beaconRoomCue: BeaconRoomState(
        beaconId: 'B1',
        updatedAt: DateTime.utc(2026, 10, 14, 9),
        currentLine: 'Van at 9:45',
        updatedBy: 'UA',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BeaconHudPinnedBlock(state: state),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Tab QA · Just now'), findsOneWidget);

    clock = clock.add(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 61));

    expect(find.textContaining('Tab QA · 2m ago'), findsOneWidget);
    expect(find.textContaining('Just now'), findsNothing);
  });

  testWidgets('an Activity mini-card age keeps counting while open', (
    tester,
  ) async {
    final receipt = AttentionReceipt(
      id: 'e1',
      category: 'requestProgress',
      kind: 'helpOfferSubmitted',
      priority: 'normal',
      title: 'Offered help',
      body: 'Body',
      actionUrl: '/#/',
      createdAt: DateTime.utc(2026, 10, 14, 9),
      collapsedCount: 1,
      presentationKey: 'help_offer_submitted',
      presentationPayloadJson: '{}',
      surface: AttentionSurface.activity,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: TenturaResponsiveScope(
            child: AttentionMiniCard(receipt: receipt),
          ),
        ),
      ),
    );
    await tester.pump();
    String age() => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(AttentionMiniCard.ageTooltipKey),
            matching: find.byType(Text),
          ),
        )
        .data!;
    expect(age(), 'Just now');

    clock = clock.add(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 31));

    expect(age(), '2m ago');
  });
}
