import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/beacon_display_status_dto.dart';
import 'package:tentura/features/beacon_view/data/repository/coordination_repository.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/ui/widget/beacon_involved_people_face_pile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_hud_derivation.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/first_load_gate.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_now_surface.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../../support/remote_wire_harness.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_screen_harness.dart';

const _author = Profile(id: 'Uauthor', displayName: 'Author');
const _recipients = [
  Profile(id: 'Ubob', displayName: 'Bob'),
  Profile(id: 'Ucarol', displayName: 'Carol'),
];
final _request = Beacon(
  id: 'BdeclinedForwards',
  title: 'Need a ladder on Saturday',
  author: _author,
  createdAt: DateTime.utc(2026, 10, 19),
  updatedAt: DateTime.utc(2026, 10, 19),
  startAt: DateTime.utc(2099, 6, 20, 12),
  viewerCanForward: true,
);

class _DelayedAuthorForwards extends FakeBeaconViewForwardRepository {
  final requested = Completer<void>();
  final response = Completer<List<ForwardEdge>>();

  @override
  Future<List<ForwardEdge>> fetchEdges({required String beaconId}) {
    if (!requested.isCompleted) requested.complete();
    return response.future;
  }

  @override
  Future<bool> currentUserHasForwardedBeacon(String beaconId) async => true;

  @override
  Future<Map<String, List<String>>> fetchReasonsByBeacon({
    required String beaconId,
  }) async => const {};

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) async => (
    beacon: _request,
    forwardedToIds: {for (final p in _recipients) p.id},
    helpOfferedIds: const <String>{},
    withdrawnIds: const <String>{},
    declinedOfferIds: const <String>{},
    rejectedIds: {for (final p in _recipients) p.id},
    watchingIds: const <String>{},
    onwardForwarderIds: const <String>{},
    myForwardedRecipientNotes: {for (final p in _recipients) p.id: ''},
    myForwardedRecipientEdgeIds: {
      for (final p in _recipients) p.id: 'edge-${p.id}',
    },
    myForwardedRecipientReadAts: {for (final p in _recipients) p.id: null},
    myForwardedRecipientHasOnwardChild: {
      for (final p in _recipients) p.id: false,
    },
    myForwardedRecipientRejected: {for (final p in _recipients) p.id: true},
  );

  void release() {
    if (response.isCompleted) return;
    response.complete([
      for (final recipient in _recipients)
        ForwardEdge(
          id: 'edge-${recipient.id}',
          beaconId: _request.id,
          sender: _author,
          recipient: recipient,
          createdAt: DateTime.utc(2026, 10, 19, 12),
          recipientRejected: true,
        ),
    ]);
  }
}

Future<void> _until(bool Function() ready, String reason) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail(reason);
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

// The offers cross the real HTTP/Ferry/mapper boundary; only scheduling is
// controlled here. Other Request dependencies use the existing screen harness.
class _DelayedWireOffers extends FakeBeaconViewCoordinationRepository {
  _DelayedWireOffers(this.repository);
  final CoordinationRepository repository;
  final release = Completer<void>();

  @override
  Future<List<FakeHelpOfferCoordinationRow>> fetchHelpOffersWithCoordination({
    required String beaconId,
  }) async {
    await release.future;
    return repository.fetchHelpOffersWithCoordination(beaconId: beaconId);
  }
}

class _DelayedDisplay extends FakeBeaconDisplayRepository {
  final release = Completer<void>();

  @override
  Future<List<BeaconDisplayStatusDto>> fetchDisplayStatuses(
    List<String> beaconIds,
  ) async {
    await release.future;
    return super.fetchDisplayStatuses(beaconIds);
  }
}

// A still-loading discussion keeps the shared gate unready even after all
// Request slices finish. Timeout can then reveal unknown forwards with known
// (empty) offers and a completed display read.
class _PendingRoom extends BeaconViewRecordingRoomCubit {
  _PendingRoom({required super.beaconId});

  @override
  RoomState get state => super.state.copyWith(firstLoadDone: false);
}

class _PendingRoomRecorder extends BeaconViewRoomCubitRecorder {
  @override
  BeaconViewRecordingRoomCubit call({
    required String beaconId,
    String? threadItemId,
    DateTime? initialUnreadAnchorAt,
  }) {
    final room = _PendingRoom(beaconId: beaconId);
    created.add(room);
    return room;
  }
}

Map<String, dynamic> _pendingHelperOffer() => {
  '__typename': 'HelpOfferWithCoordinationRow',
  'beaconId': _request.id,
  'userId': 'Uhelper',
  'message': 'I can bring a ladder',
  'helpType': null,
  'roleLabel': null,
  'status': 0,
  'withdrawReason': null,
  'createdAt': '2026-10-19T12:00:00.000Z',
  'updatedAt': '2026-10-19T12:00:00.000Z',
  'editedAt': null,
  'responseType': null,
  'responseUpdatedAt': null,
  'responseAuthorUserId': null,
  'roomAccess': 0,
  'admissionAction': null,
  'lastDeclineReason': null,
  'lastRemoveReason': null,
  'stakeState': 0,
  'offerKind': 0,
  'isDirectAuthorForward': false,
  'authorSeenAt': null,
  'user': {
    '__typename': 'User',
    'id': 'Uhelper',
    'displayName': 'Helper',
    'description': '',
    'my_vote': null,
    'trusts_viewer': false,
    'is_mutual_friend': false,
    'image': null,
    'user_presence': null,
    'user_availability': null,
  },
};

int _gateSpinners() => find
    .descendant(
      of: find.byType(TenturaFirstLoadGate),
      matching: find.byType(CircularProgressIndicator),
    )
    .evaluate()
    .where((element) {
      var inContent = false;
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is TenturaFirstLoadGate) return false;
        if (ancestor.widget is Visibility) inContent = true;
        return true;
      });
      return !inContent;
    })
    .length;

Finder _splitText(String text) => find.descendant(
  of: find.byKey(beaconSplitChatHeaderKey),
  matching: find.textContaining(text, findRichText: true),
);

// Coverage map: #545 round-9 desktop -> desktop split cases below; the
// already-passing phone item is a 375x667 RU regression control.
// Sibling matrix (author/helper x normal/timeout): desktop 1365x900 and
// landscape tablet 1024x900 each exercise all four cells. Phone author normal
// is covered in RU. Phone helper and timeout are outside this split-header
// regression: at 375px Now has no split header or adjacent discussion pane
// whose pending load could hold this timeout scenario. The shared helper
// status and discussion-timeout paths are exercised at both wider sizes.
Future<void> _checkChromeReveal(
  WidgetTester tester, {
  bool helper = false,
  bool timeout = false,
  bool delayOffersUntilForwardsFail = false,
  bool tablet = false,
  bool phone = false,
}) async {
  final sent = <WireSent>[];
  await withRemoteWire(
    {
      'HelpOffersWithCoordination': {
        '__typename': 'query_root',
        'helpOffersWithCoordination': [if (helper) _pendingHelperOffer()],
      },
    },
    sent,
    (remote) async {
      final offers = _DelayedWireOffers(CoordinationRepository(remote));
      final display = _DelayedDisplay();
      final forwards = _DelayedAuthorForwards();
      final repository = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => _request;
      final viewer = helper
          ? const Profile(id: 'Uhelper', displayName: 'Helper')
          : _author;
      final cubit = BeaconViewCubit(
        id: _request.id,
        myProfile: viewer,
        beaconViewCase: buildTestBeaconViewCase(
          beaconRepo: repository,
          forward: forwards,
          coordinationRepo: offers,
          displayRepo: display,
        ),
        effects: FakeUiEffectPort(),
      );
      final host = beaconViewHarnessHost(
        beaconId: _request.id,
        recorder: timeout ? _PendingRoomRecorder() : null,
      );
      BeaconViewHarness? harness;
      addTearDown(unregisterBeaconViewHarnessGetIt);
      try {
        // Normal author: offers/display finish, only fetchEdges is pending.
        // Helper: offers arrive first, display holds the gate for one frame.
        // Timeout: only the discussion holds the gate after forwards fail.
        if (!helper) display.release.complete();
        if (!helper && !delayOffersUntilForwardsFail) offers.release.complete();
        harness = await pumpBeaconViewHarness(
          tester,
          size: phone
              ? const Size(375, 667)
              : tablet
              ? const Size(1024, 900)
              : const Size(1365, 900),
          locale: Locale(phone ? 'ru' : 'en'),
          beaconState: beaconViewHarnessAuthorState(
            beaconId: _request.id,
            authorId: _author.id,
          ).copyWith(beacon: _request, myProfile: viewer),
          beaconViewCubit: cubit,
          threadsState: beaconViewHarnessThreadsState(authorId: viewer.id),
          host: host,
          viewTab: 'now',
        );
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (cubit.state.beaconContentLoaded &&
              (helper || forwards.requested.isCompleted)) {
            break;
          }
        }
        expect(cubit.state.loadError, isNull);
        expect(cubit.state.beaconContentLoaded, isTrue);
        if (!phone) {
          expect(find.byKey(beaconSplitChatHeaderKey), findsOneWidget);
        }
        await tester.pump(const Duration(milliseconds: 200));
        expect(_gateSpinners(), 1);
        expect(find.byType(BeaconNowSurface), findsNothing);

        final header = phone
            ? find.byType(TenturaTopBar)
            : find.byKey(beaconSplitChatHeaderKey);
        Finder headerText(String text) => phone
            ? find.descendant(
                of: header,
                matching: find.textContaining(text, findRichText: true),
              )
            : _splitText(text);
        void expectHiddenChrome() {
          expect(_gateSpinners(), 1);
          expect(find.byType(BeaconNowSurface), findsNothing);
          // Check the helper cue first so this test diagnoses its own leak.
          if (helper) expect(headerText('Offer sent'), findsNothing);
          expect(headerText('no offers yet'), findsNothing);
          expect(headerText('declined'), findsNothing);
          expect(
            find.descendant(
              of: header,
              matching: find.byType(TenturaStatusLine),
            ),
            findsNothing,
          );
          expect(find.byType(BeaconInvolvedPeopleFacePile), findsNothing);
        }

        if (helper) {
          offers.release.complete();
          for (var i = 0; i < 40; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
            if (cubit.state.myActiveHelpOffer != null) break;
          }
          expect(
            cubit.state.myActiveHelpOffer,
            isNotNull,
            reason:
                'the pending offer must reach state through real Ferry mapping',
          );
          expect(_gateSpinners(), 1);
          expect(find.byType(BeaconNowSurface), findsNothing);
        }

        if (timeout) {
          expect(cubit.state.forwardsLoaded, isFalse);
          expectHiddenChrome();
          if (helper) {
            // The offer is known; the discussion alone delays reveal.
            display.release.complete();
          } else {
            expect(forwards.requested.isCompleted, isTrue);
            forwards.response.completeError(StateError('forwards unavailable'));
            if (!offers.release.isCompleted) offers.release.complete();
          }
          // Offers and display are released already. Drain real HTTP/Ferry
          // work without advancing the gate clock toward its timeout.
          for (var i = 0; i < 40; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
            expect(cubit.state.forwardsLoaded, isFalse);
            expectHiddenChrome();
            if (cubit.state.firstLoadDone) break;
          }
          expect(
            cubit.state.firstLoadDone,
            isTrue,
            reason: 'Request data must finish before the discussion times out',
          );
          expect(cubit.state.helpOffers, helper ? hasLength(1) : isEmpty);
          expect(
            sent.any((s) => s.operationName == 'HelpOffersWithCoordination'),
            isTrue,
          );
          var revealed = false;
          for (var i = 0; i < 170; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(cubit.state.forwardsLoaded, isFalse);
            expect(
              _splitText('no offers yet'),
              findsNothing,
              reason:
                  'unknown forwards must never claim empty offers, '
                  'before or after timeout',
            );
            if (find.byType(BeaconNowSurface).evaluate().isNotEmpty) {
              expect(_gateSpinners(), 0);
              expect(
                _splitText('no offers yet'),
                findsNothing,
                reason: 'known empty offers do not make failed forwards known',
              );
              if (helper) expect(_splitText('Offer sent'), findsOneWidget);
              revealed = true;
              break;
            }
            expectHiddenChrome();
          }
          expect(
            revealed,
            isTrue,
            reason: 'the discussion gate must reveal on timeout',
          );
          // Keep checking frames after timeout, too.
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(cubit.state.forwardsLoaded, isFalse);
            expect(_splitText('no offers yet'), findsNothing);
          }
          return;
        }

        // Exercise successive spinner frames while fetchEdges (author) or
        // display (helper with a mapped offer) stays pending.
        for (var i = 0; i < 12; i++) {
          if (!helper) expect(forwards.response.isCompleted, isFalse);
          expectHiddenChrome();
          await tester.pump(const Duration(milliseconds: 16));
        }
        expectHiddenChrome();

        if (helper) {
          display.release.complete();
        } else {
          expect(forwards.response.isCompleted, isFalse);
          forwards.release();
        }
        var revealed = false;
        final cue = helper
            ? 'Offer sent'
            : phone
            ? 'отказались: 2 из 2 — перешлите кому-то ещё'
            : '2 of 2 declined — forward to someone else';
        for (var i = 0; i < 60; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 16));
          final bodyVisible = find
              .byType(BeaconNowSurface)
              .evaluate()
              .isNotEmpty;
          final cueVisible = find
              .descendant(
                of: header,
                matching: find.textContaining(cue, findRichText: true),
              )
              .evaluate()
              .isNotEmpty;
          expect(
            cueVisible,
            bodyVisible,
            reason: 'status and Now must first appear in the same frame',
          );
          if (!bodyVisible) expectHiddenChrome();
          if (bodyVisible) {
            expect(_gateSpinners(), 0);
            if (!phone) {
              expect(find.byType(BeaconInvolvedPeopleFacePile), findsOneWidget);
            }
            revealed = true;
            break;
          }
        }
        expect(revealed, isTrue);
        expect(
          sent.any((s) => s.operationName == 'HelpOffersWithCoordination'),
          isTrue,
        );
        if (phone) {
          const fullRussianStatus =
              'Ищем помощь · отказались: 2 из 2 — перешлите кому-то ещё';
          final fullStatus = find.descendant(
            of: header,
            matching: find.text(fullRussianStatus, findRichText: true),
          );
          expect(
            fullStatus,
            findsOneWidget,
            reason: 'the full localized phase and declined cue are present',
          );
          final paragraphs = tester
              .renderObjectList<RenderParagraph>(
                find.descendant(of: header, matching: find.byType(RichText)),
              )
              .where((p) => p.text.toPlainText() == fullRussianStatus)
              .toList();
          expect(paragraphs, hasLength(1));
          expect(
            paragraphs.single.didExceedMaxLines,
            isFalse,
            reason: 'the full Russian status fits without truncation',
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '375x667 RU must not produce layout or overflow errors',
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        if (!offers.release.isCompleted) offers.release.complete();
        if (!display.release.isCompleted) display.release.complete();
        forwards.release();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(() async {
          await host.close();
          await cubit.close();
          await harness?.threadsCubit.close();
          await repository.dispose();
          await forwards.dispose();
        });
      }
    },
  );
}

void main() {
  testWidgets(
    'desktop split hides author status and faces until forwards reveal',
    _checkChromeReveal,
  );
  testWidgets(
    'desktop split shows Offer sent only when delayed offers reveal',
    (tester) => _checkChromeReveal(tester, helper: true),
  );
  testWidgets(
    'desktop timeout reveal keeps unknown forwards distinct from empty',
    (tester) => _checkChromeReveal(tester, timeout: true),
  );
  testWidgets(
    'desktop timeout with loaded offers keeps failed forwards unknown',
    (tester) => _checkChromeReveal(
      tester,
      timeout: true,
      delayOffersUntilForwardsFail: true,
    ),
  );
  testWidgets(
    'desktop helper timeout reveals Offer sent with the Request body',
    (tester) => _checkChromeReveal(tester, helper: true, timeout: true),
  );
  for (final helper in [false, true]) {
    for (final timeout in [false, true]) {
      testWidgets(
        'landscape tablet ${helper ? 'helper' : 'author'} '
        '${timeout ? 'timeout' : 'normal'} reveal hides partial Request chrome',
        (tester) => _checkChromeReveal(
          tester,
          tablet: true,
          helper: helper,
          timeout: timeout,
        ),
      );
    }
  }
  testWidgets(
    'Russian phone reveals declined status with the Request body',
    (tester) => _checkChromeReveal(tester, phone: true),
  );

  test(
    'author Request waits for forwards and reveals the everyone-declined HUD cue without an interim forward cue',
    () async {
      final forwards = _DelayedAuthorForwards();
      addTearDown(forwards.dispose);
      final repository = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => _request;
      addTearDown(repository.dispose);
      final cubit = BeaconViewCubit(
        id: _request.id,
        myProfile: _author,
        beaconViewCase: buildTestBeaconViewCase(
          beaconRepo: repository,
          forward: forwards,
        ),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      addTearDown(forwards.release);
      final states = <BeaconViewState>[cubit.state];
      final subscription = cubit.stream.listen(states.add);
      addTearDown(subscription.cancel);
      final en = lookupL10n(const Locale('en'));

      await forwards.requested.future.timeout(const Duration(seconds: 3));
      // Drain the completed primary/room reads while only forwards are held.
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.beaconContentLoaded, isTrue);
      expect(cubit.state.loadError, isNull);
      expect(cubit.state.forwardsLoaded, isFalse);
      expect(forwards.response.isCompleted, isFalse);
      final readyWhileForwardsPending = states.any((s) => s.firstLoadDone);

      forwards.release();
      await _until(
        () => cubit.state.forwardsLoaded && cubit.state.firstLoadDone,
        'Completed forwards must release first-load readiness',
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.myForwards, hasLength(2));
      expect(
        cubit.state.myForwards.every((edge) => edge.recipientRejected),
        isTrue,
      );
      expect(
        beaconHudYouLine(en, cubit.state),
        'Everyone declined — forward to someone else',
        reason: 'The loaded fixture must produce the actual declined cue',
      );

      final firstReveal = states.firstWhere((s) => s.firstLoadDone);
      expect(
        (
          readyWhileForwardsPending: readyWhileForwardsPending,
          firstRevealedYouLine: beaconHudYouLine(en, firstReveal),
          showedInterimForwardCue: states
              .where((s) => s.firstLoadDone)
              .any((s) => beaconHudYouLine(en, s) == en.beaconHudYouForward),
        ),
        (
          readyWhileForwardsPending: false,
          firstRevealedYouLine: 'Everyone declined — forward to someone else',
          showedInterimForwardCue: false,
        ),
        reason:
            'The Request gate must wait for the author forwards so its first '
            'revealed HUD already says everyone declined',
      );
    },
  );

  testWidgets(
    'Request screen keeps the gate visible during forwards loading and reveals the declined HUD cue in its first frame',
    (tester) async {
      final forwards = _DelayedAuthorForwards();
      final repository = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => _request;
      final cubit = BeaconViewCubit(
        id: _request.id,
        myProfile: _author,
        beaconViewCase: buildTestBeaconViewCase(
          beaconRepo: repository,
          forward: forwards,
        ),
        effects: FakeUiEffectPort(),
      );
      final host = beaconViewHarnessHost(beaconId: _request.id);
      BeaconViewHarness? harness;
      addTearDown(unregisterBeaconViewHarnessGetIt);

      // Default finders skip the gate's offstage content. Count only the
      // overlay spinner, excluding indicators in the hidden screen body.
      int gateSpinners() => find
          .descendant(
            of: find.byType(TenturaFirstLoadGate),
            matching: find.byType(CircularProgressIndicator),
          )
          .evaluate()
          .where((element) {
            var insideContent = false;
            element.visitAncestorElements((ancestor) {
              if (ancestor.widget is TenturaFirstLoadGate) return false;
              if (ancestor.widget is Visibility) insideContent = true;
              return true;
            });
            return !insideContent;
          })
          .length;

      ({int spinners, int bodies, int declinedCues, int interimCues}) frame() =>
          (
            spinners: gateSpinners(),
            bodies: find.byType(BeaconNowSurface).evaluate().length,
            declinedCues: find
                .text(
                  'Everyone declined — forward to someone else',
                  findRichText: true,
                )
                .evaluate()
                .length,
            interimCues: find
                .text('You can forward', findRichText: true)
                .evaluate()
                .length,
          );

      try {
        harness = await pumpBeaconViewHarness(
          tester,
          size: kBeaconViewHarnessExpanded,
          beaconState: beaconViewHarnessAuthorState(
            beaconId: _request.id,
            authorId: _author.id,
          ).copyWith(beacon: _request),
          beaconViewCubit: cubit,
          threadsState: beaconViewHarnessThreadsState(authorId: _author.id),
          host: host,
          viewTab: 'now',
        );
        for (var i = 0; i < 30 && !forwards.requested.isCompleted; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(forwards.requested.isCompleted, isTrue);
        expect(forwards.response.isCompleted, isFalse);
        expect(cubit.state.loadError, isNull);
        expect(find.byType(TenturaFirstLoadGate), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 200));
        final pendingFrame = frame();

        forwards.release();
        var revealed = false;
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          final visible = frame();
          if (visible.bodies == 0) continue;
          expect(
            visible,
            (spinners: 0, bodies: 1, declinedCues: 1, interimCues: 0),
            reason:
                'The first visible Request frame must already show the '
                'everyone-declined cue, with no generic forward cue',
          );
          revealed = true;
          break;
        }
        expect(
          revealed,
          isTrue,
          reason: 'Forwards completion must reveal the Request',
        );
        expect(
          pendingFrame,
          (spinners: 1, bodies: 0, declinedCues: 0, interimCues: 0),
          reason:
              'Only the gate spinner may be visible while forwards are pending',
        );
      } finally {
        forwards.release();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(() async {
          await host.close();
          await cubit.close();
          await harness?.threadsCubit.close();
          await repository.dispose();
          await forwards.dispose();
        });
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'phone bar shows no status until the first-load gate reveals the declined line',
    (tester) async {
      final forwards = _DelayedAuthorForwards();
      final repository = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => _request;
      final cubit = BeaconViewCubit(
        id: _request.id,
        myProfile: _author,
        beaconViewCase: buildTestBeaconViewCase(
          beaconRepo: repository,
          forward: forwards,
        ),
        effects: FakeUiEffectPort(),
      );
      final host = beaconViewHarnessHost(beaconId: _request.id);
      BeaconViewHarness? harness;
      addTearDown(unregisterBeaconViewHarnessGetIt);

      // The overlay spinner only. Indicators inside the hidden body do not
      // count: Visibility keeps that subtree mounted.
      int gateSpinners() => find
          .descendant(
            of: find.byType(TenturaFirstLoadGate),
            matching: find.byType(CircularProgressIndicator),
          )
          .evaluate()
          .where((element) {
            var insideContent = false;
            element.visitAncestorElements((ancestor) {
              if (ancestor.widget is TenturaFirstLoadGate) return false;
              if (ancestor.widget is Visibility) insideContent = true;
              return true;
            });
            return !insideContent;
          })
          .length;

      Finder barText(String text) => find.descendant(
        of: find.byType(TenturaTopBar),
        matching: find.textContaining(text, findRichText: true),
      );

      int barStatusLines() => find
          .descendant(
            of: find.byType(TenturaTopBar),
            matching: find.byType(TenturaStatusLine),
          )
          .evaluate()
          .length;

      try {
        harness = await pumpBeaconViewHarness(
          tester,
          size: const Size(375, 667),
          beaconState: beaconViewHarnessAuthorState(
            beaconId: _request.id,
            authorId: _author.id,
          ).copyWith(beacon: _request),
          beaconViewCubit: cubit,
          threadsState: beaconViewHarnessThreadsState(authorId: _author.id),
          host: host,
          viewTab: 'now',
        );
        for (var i = 0; i < 30 && !forwards.requested.isCompleted; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(forwards.requested.isCompleted, isTrue);
        expect(forwards.response.isCompleted, isFalse);
        expect(
          cubit.state.forwardsLoading || !cubit.state.forwardsLoaded,
          isTrue,
        );
        await tester.pump(const Duration(milliseconds: 200));

        expect(gateSpinners(), 1, reason: 'the gate spinner is up');
        expect(find.byType(BeaconNowSurface), findsNothing);
        expect(
          barStatusLines(),
          0,
          reason: 'no phase status in the bar while the gate is closed',
        );
        expect(barText('Looking for helpers'), findsNothing);
        expect(barText('no offers yet'), findsNothing);
        final titleShown =
            barText(_request.title).evaluate().isNotEmpty ||
            barText('Request').evaluate().isNotEmpty;
        expect(titleShown, isTrue, reason: 'the bar keeps its load-time title');

        forwards.release();
        var revealed = false;
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          final bodyVisible = find
              .byType(BeaconNowSurface)
              .evaluate()
              .isNotEmpty;
          final statusLines = barStatusLines();
          expect(barText('no offers yet'), findsNothing);
          if (!bodyVisible) {
            expect(
              statusLines,
              0,
              reason: 'the status must not appear before the body',
            );
            continue;
          }
          expect(gateSpinners(), 0);
          expect(statusLines, greaterThan(0));
          expect(barText('2 of 2 declined'), findsOneWidget);
          expect(barText('forward to someone else'), findsWidgets);
          revealed = true;
          break;
        }
        expect(
          revealed,
          isTrue,
          reason: 'forwards completion reveals the bar status with the body',
        );
        expect(cubit.state.firstLoadDone, isTrue);
        expect(cubit.state.forwardsLoaded, isTrue);
      } finally {
        forwards.release();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(() async {
          await host.close();
          await cubit.close();
          await harness?.threadsCubit.close();
          await repository.dispose();
          await forwards.dispose();
        });
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
