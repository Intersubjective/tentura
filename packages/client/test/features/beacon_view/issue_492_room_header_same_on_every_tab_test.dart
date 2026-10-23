import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_threads/ui/widget/thread_detail.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_anchor_status.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_app_bar_title.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'beacon_view_screen_harness.dart';

/// #492: on a narrow (mobile) window the request header changed shape per
/// tab. Now / People showed «title + status line»; Chat swapped the status
/// line for the involved-people face pile, so the chat had no status at all.
/// The header is one widget on every tab: title + status line.
const _kTitle = 'Harness request';

Finder get _topBar => find.byType(TenturaTopBar);

Finder _inTopBar(Finder matching) =>
    find.descendant(of: _topBar, matching: matching);

Future<void> _tapTab(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(TestIds.key(id)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _pumpCompact(WidgetTester tester) async {
  await pumpBeaconViewHarness(
    tester,
    size: kBeaconViewHarnessCompact,
    beaconState: beaconViewHarnessAuthorState(),
    threadsState: beaconViewHarnessThreadsState(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = lookupL10n(const Locale('en'));
  final status = beaconViewStatusSlots(
    l10n,
    beaconViewHarnessAuthorState(),
  ).presentation;

  setUp(() async {
    await registerBeaconViewHarnessGetIt();
  });

  tearDown(() async {
    await unregisterBeaconViewHarnessGetIt();
  });

  group('#492 mobile request header', () {
    testWidgets('Chat tab keeps the title and the status line', (
      tester,
    ) async {
      // Raw precondition: the harness request has a non-empty status.
      expect(status.slot1.trim(), isNotEmpty);

      await _pumpCompact(tester);

      // Now tab (control): title + status in the top bar.
      expect(_inTopBar(find.text(_kTitle)), findsOneWidget);
      expect(
        _inTopBar(find.textContaining(status.slot1, findRichText: true)),
        findsOneWidget,
      );

      await tapBeaconChatTabAndWaitForRoom(tester);

      // Chat tab: the same title, once, and the same status line.
      expect(_inTopBar(find.text(_kTitle)), findsOneWidget);
      expect(
        _inTopBar(find.textContaining(status.slot1, findRichText: true)),
        findsOneWidget,
      );
      expect(_inTopBar(find.byType(TenturaStatusLine)), findsOneWidget);
    });

    testWidgets('one title + status header on Now, Chat and People', (
      tester,
    ) async {
      await _pumpCompact(tester);

      BeaconViewAppBarTitle header() => tester.widget<BeaconViewAppBarTitle>(
        _inTopBar(find.byType(BeaconViewAppBarTitle)),
      );

      final onNow = header();
      expect(onNow.showBeaconContent, isTrue);
      expect(onNow.beacon.title, _kTitle);
      expect(onNow.phaseStatus.statusLine, status.statusLine);

      await tapBeaconChatTabAndWaitForRoom(tester);
      // Guard: the top bar carries exactly one header and one title on Chat
      // (no second two-row «title + face pile» header beside it).
      expect(_inTopBar(find.byType(BeaconViewAppBarTitle)), findsOneWidget);
      expect(_inTopBar(find.text(_kTitle)), findsOneWidget);
      final onChat = header();
      expect(onChat.beacon.title, onNow.beacon.title);
      expect(onChat.showBeaconContent, isTrue);
      expect(onChat.phaseStatus.statusLine, onNow.phaseStatus.statusLine);

      await _tapTab(tester, TestIds.beaconTabPeople);
      expect(find.byType(ThreadDetail), findsNothing);
      final onPeople = header();
      expect(onPeople.beacon.title, onNow.beacon.title);
      expect(onPeople.phaseStatus.statusLine, onNow.phaseStatus.statusLine);

      // Back to Now: still the same header (no state leak from Chat).
      await _tapTab(tester, TestIds.beaconTabNow);
      expect(header().phaseStatus.statusLine, onNow.phaseStatus.statusLine);
      expect(_inTopBar(find.text(_kTitle)), findsOneWidget);
    });
  });
}
