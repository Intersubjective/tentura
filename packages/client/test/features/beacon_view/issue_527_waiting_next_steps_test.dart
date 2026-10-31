// #527 (rest): after Offer help the waiting state on the Request page says
// what happens next ("Offer sent to …" + "You'll be notified …"), shows one
// Forward (the bottom, secondary one; More actions drops its duplicate) and
// lets a long offer quote expand to its full text, on a phone and a desktop.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_lobby/domain/use_case/beacon_lobby_case.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_action_button.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_showcase_surface.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_forward_overflow.dart';
import 'package:tentura/ui/test_ids.dart';

import '../beacon_lobby/fake_lobby_port.dart';
import 'beacon_view_screen_harness.dart';

void main() {
  const viewer = 'dave';
  const me = Profile(id: viewer, displayName: 'Dave');
  const shortOffer = 'I have a van!';
  final longOffer =
      'I have a van! Can do 10-12 on Saturday, '
      '${List.filled(40, 'and I can bring straps, blankets and a dolly').join(', ')}.';
  const pendingKey = Key('beaconShowcaseOfferPending');
  const nextKey = Key('beaconShowcaseOfferNext');
  const quoteKey = Key('beaconShowcaseOfferPendingMessage');
  const toggleKey = Key('beaconShowcaseOfferPendingMessageToggle');
  const withdrawKey = Key('beaconShowcaseWithdrawOffer');
  const phone = Size(375, 812);
  const desktop = Size(1280, 800);

  tearDown(() async {
    await unregisterBeaconViewHarnessGetIt();
    if (GetIt.I.isRegistered<BeaconLobbyCase>()) {
      await GetIt.I.unregister<BeaconLobbyCase>();
    }
  });

  BeaconViewState waiting({
    String message = shortOffer,
    int offerKind = 0,
    BeaconStatus status = BeaconStatus.open,
  }) {
    final author = beaconViewHarnessAuthorState();
    return author.copyWith(
      beacon: author.beacon.copyWith(
        status: status,
        description: 'Help us move on Saturday.',
        accessLevel: BeaconAccessLevel.observer,
        viewerCanForward: true,
      ),
      myProfile: me,
      helpOffers: [
        TimelineHelpOffer(
          user: me,
          message: message,
          createdAt: kBeaconViewHarnessNow,
          updatedAt: kBeaconViewHarnessNow,
          offerKind: offerKind,
        ),
      ],
      isHelpOffered: true,
    );
  }

  Future<void> pump(
    WidgetTester tester,
    Size size, {
    String message = shortOffer,
    int offerKind = 0,
    BeaconStatus status = BeaconStatus.open,
  }) async {
    GetIt.I.registerSingleton<BeaconLobbyCase>(
      lobbyCaseFor(
        FakeLobbyPort(
          viewerId: viewer,
          authorId: kBeaconViewHarnessAuthorId,
          offerers: {viewer},
        ),
        FakeRealtimeSyncPort(),
      ),
    );
    await pumpBeaconViewHarness(
      tester,
      size: size,
      beaconState: waiting(
        message: message,
        offerKind: offerKind,
        status: status,
      ),
      threadsState: beaconViewHarnessThreadsState(),
    );
    await tester.pumpAndSettle();
  }

  for (final (name, size) in [('phone', phone), ('desktop', desktop)]) {
    testWidgets('$name: says what happens next, with Withdraw', (
      tester,
    ) async {
      await pump(tester, size);
      expect(find.byType(BeaconShowcaseSurface), findsOneWidget);

      expect(find.byKey(pendingKey), findsOneWidget);
      expect(find.text('Offer sent to Author'), findsOneWidget);
      expect(find.byKey(nextKey), findsOneWidget);
      expect(
        find.text(
          "You'll be notified when they answer. "
          'You can withdraw the offer until then.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(withdrawKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name: exactly one Forward, secondary, none in More actions', (
      tester,
    ) async {
      await pump(tester, size);

      final bottomForward = find.descendant(
        of: find.byType(BeaconShowcaseSurface),
        matching: find.text('Forward'),
      );
      expect(bottomForward, findsOneWidget);
      // Secondary: the waiting state does not push forwarding.
      final forwardButton = tester.widget<BeaconHudActionButton>(
        find.ancestor(
          of: bottomForward,
          matching: find.byType(BeaconHudActionButton),
        ),
      );
      expect(forwardButton.filled, isFalse);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      expect(find.byKey(TestIds.key(TestIds.beaconForward)), findsNothing);
      expect(find.text('Forward'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name: a long offer expands and collapses on tap', (
      tester,
    ) async {
      await pump(tester, size, message: longOffer);

      expect(tester.widget<Text>(find.byKey(quoteKey)).maxLines, 2);
      final toggle = find.byKey(toggleKey);
      expect(toggle, findsOneWidget);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(quoteKey)).maxLines, isNull);

      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(quoteKey)).maxLines, 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a short offer is not a toggle', (tester) async {
    await pump(tester, phone);

    expect(find.byKey(quoteKey), findsOneWidget);
    expect(find.byKey(toggleKey), findsNothing);
  });

  testWidgets('a backup offer: they may contact you if more help is needed', (
    tester,
  ) async {
    await pump(tester, phone, offerKind: 1, status: BeaconStatus.enoughHelp);

    expect(find.text('Backup offer sent to Author'), findsOneWidget);
    expect(
      find.text(
        'They may contact you if more help is needed. '
        'You can withdraw the offer at any time.',
      ),
      findsOneWidget,
    );
  });

  test('More actions keeps Forward when the showcase has none to show', () {
    final s = waiting();
    expect(beaconShowcaseOwnsForward(s), isTrue);
    expect(
      beaconShowcaseOwnsForward(
        s.copyWith(beacon: s.beacon.copyWith(viewerCanForward: false)),
      ),
      isFalse,
    );
    // Not waiting (no offer): nothing changes.
    expect(
      beaconShowcaseOwnsForward(
        s.copyWith(helpOffers: const [], isHelpOffered: false),
      ),
      isFalse,
    );
  });
}
