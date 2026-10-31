import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_hud_derivation.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/first_load_gate.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_now_surface.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
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

void main() {
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
