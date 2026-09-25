// BeaconViewCubit people_seen patch (plan §P4.3): the offerer's view of a
// Request listens to `people_seen` frames (the author or a steward opened the
// People surface) and stamps `authorSeenAt` on the viewer's *own* pending
// offer only — `user.id == myProfile.id`, `authorSeenAt == null` and
// `!seenAt.isBefore(createdAt)` — emitting only when something changed and
// never refetching offers. Author/steward bulk stamping stays on
// `reportPeopleSurfaceViewed` (see beacon_view_cubit_people_seen_test.dart).
//
// Refetch race: an offers refetch merges by offer user id and keeps the later
// non-null `authorSeenAt` of (server, local); a null server value never
// clears a local stamp. A frame never touches an offer that is already seen,
// so a frame arriving after a refetch that returned a value leaves that value
// as it is, whether the frame is older or newer.
//
// Offers refetches are driven by a help-offer room invalidation. The cubit
// routes helpOffer/participant invalidations to the full request-detail
// refresh (`_onRoomInvalidation`), so the targeted `_refreshHelpOffers`
// branch of `_fetchForEntityTypes` cannot be reached through the cubit's
// inputs today; these tests cover the refetch path the cubit actually takes.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'help_offer_author_seen_test_support.dart';

const _otherHelper = Profile(id: 'Uofferer00002', displayName: 'Other');

const _markerHelper = Profile(id: 'Uofferer00009', displayName: 'Marker');

/// Serves [serverRows] for offers fetches. With [gate] set, a fetch waits for
/// it, so a test controls exactly when a refetch lands.
class _GatedCoordinationRepository extends CountingCoordinationRepository {
  _GatedCoordinationRepository(this.serverRows);

  List<FakeHelpOfferCoordinationRow> serverRows;
  Completer<void>? gate;

  @override
  Future<List<FakeHelpOfferCoordinationRow>> fetchHelpOffersWithCoordination({
    required String beaconId,
  }) async {
    fetchCalls++;
    final rowsAtCall = serverRows;
    final pending = gate;
    if (pending != null) await pending.future;
    return rowsAtCall;
  }
}

class _Harness {
  _Harness({
    required List<FakeHelpOfferCoordinationRow> rows,
    this.viewer = kOfferer,
  }) : rows = [...rows] {
    coordination = _GatedCoordinationRepository(this.rows);
    beaconRepo = TrackingBeaconRepository()
      ..fetchByIdHandler = (_) async => authorSeenBeacon();
    final realtime = buildTestRealtimeSync();
    port = realtime.port;
    cubit = BeaconViewCubit(
      id: kAuthorSeenBeaconId,
      myProfile: viewer,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        coordinationRepo: coordination,
        roomRepo: room,
        realtimeSyncCase: realtime.case_,
      ),
      effects: FakeUiEffectPort(),
    );
  }

  final Profile viewer;

  /// Server rows served by the initial load.
  final List<FakeHelpOfferCoordinationRow> rows;
  final room = FakeBeaconViewRoomRepository();
  late final _GatedCoordinationRepository coordination;
  late final TrackingBeaconRepository beaconRepo;
  late final TestRealtimeSyncPort port;
  late final BeaconViewCubit cubit;
  final emitted = <BeaconViewState>[];
  StreamSubscription<BeaconViewState>? _sub;

  /// Loads, lets trailing load emissions settle, then starts recording.
  Future<void> load() async {
    await waitFor(
      () =>
          cubit.state.beaconContextLoaded &&
          cubit.state.roomParticipantsLoaded &&
          cubit.state.helpOffers.length == rows.length,
    );
    await settle();
    _sub = cubit.stream.listen(emitted.add);
  }

  void sendPeopleSeen(
    DateTime seenAt, {
    String beaconId = kAuthorSeenBeaconId,
  }) => port.emitChange(
    RealtimeEntityChange(
      kind: RealtimeEntityKind.peopleSeen,
      aggregateId: beaconId,
      operation: RealtimeOperation.update,
      source: RealtimeChangeSource.serverInvalidation,
      actorUserId: kAuthor.id,
      peopleSeenAt: seenAt,
    ),
  );

  /// Server-side help-offer change → full request-detail refresh.
  void invalidateHelpOffers() => room.emitRoomInvalidation(
    const BeaconRoomInvalidation(
      beaconId: kAuthorSeenBeaconId,
      entityType: BeaconRoomEntityType.helpOffer,
    ),
  );

  DateTime? seenAtOf(Profile user) => cubit.state.helpOffers
      .singleWhere((o) => o.user.id == user.id)
      .authorSeenAt;

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  Future<void> dispose() async {
    await _sub?.cancel();
    await cubit.close();
    await port.dispose();
    await room.dispose();
    await beaconRepo.dispose();
  }
}

void main() {
  final seen1205 = DateTime.utc(2026, 6, 15, 12, 5);
  final seen1208 = DateTime.utc(2026, 6, 15, 12, 8);
  final seen1210 = DateTime.utc(2026, 6, 15, 12, 10);

  group('BeaconViewCubit people_seen patch', () {
    test(
      "frame for this Request stamps the viewer's own pending offer, "
      'emits once, never stamps other helpers, never refetches',
      () async {
        final h = _Harness(
          rows: [
            pendingOfferRow(),
            pendingOfferRow(offerer: _otherHelper),
          ],
        );
        addTearDown(h.dispose);
        await h.load();
        final fetchesBefore = h.coordination.fetchCalls;
        final beaconFetchesBefore = h.beaconRepo.fetchByIdCalls;

        h.sendPeopleSeen(seen1205);
        await h.settle();

        expect(h.seenAtOf(kOfferer), seen1205);
        expect(
          h.seenAtOf(_otherHelper),
          isNull,
          reason: "only the viewer's own offer is patched",
        );
        expect(h.emitted, hasLength(1));
        expect(h.coordination.fetchCalls, fetchesBefore);
        expect(h.beaconRepo.fetchByIdCalls, beaconFetchesBefore);
      },
    );

    test('frame for another Request emits nothing', () async {
      final h = _Harness(rows: [pendingOfferRow()]);
      addTearDown(h.dispose);
      await h.load();
      final fetchesBefore = h.coordination.fetchCalls;

      h.sendPeopleSeen(seen1205, beaconId: 'Botherbeacon1');
      await h.settle();

      expect(h.seenAtOf(kOfferer), isNull);
      expect(h.emitted, isEmpty);
      expect(h.coordination.fetchCalls, fetchesBefore);
    });

    test('seenAt before the offer createdAt emits nothing', () async {
      final h = _Harness(rows: [pendingOfferRow()]);
      addTearDown(h.dispose);
      await h.load();
      final fetchesBefore = h.coordination.fetchCalls;

      h.sendPeopleSeen(DateTime.utc(2026, 6, 15, 11));
      await h.settle();

      expect(h.seenAtOf(kOfferer), isNull);
      expect(h.emitted, isEmpty);
      expect(h.coordination.fetchCalls, fetchesBefore);
    });

    test('seenAt exactly at the offer createdAt stamps it', () async {
      final h = _Harness(rows: [pendingOfferRow()]);
      addTearDown(h.dispose);
      await h.load();

      h.sendPeopleSeen(kOfferCreatedAt);
      await h.settle();

      expect(h.seenAtOf(kOfferer), kOfferCreatedAt);
      expect(h.emitted, hasLength(1));
    });

    test(
      'own offer already seen: a later frame emits nothing and keeps the '
      'existing timestamp',
      () async {
        final h = _Harness(rows: [pendingOfferRow(authorSeenAt: seen1205)]);
        addTearDown(h.dispose);
        await h.load();
        final fetchesBefore = h.coordination.fetchCalls;

        h.sendPeopleSeen(seen1210);
        await h.settle();

        expect(h.seenAtOf(kOfferer), seen1205);
        expect(h.emitted, isEmpty);
        expect(h.coordination.fetchCalls, fetchesBefore);
      },
    );

    test(
      "viewer without an own offer: other helpers' offers are never "
      'stamped and nothing is emitted',
      () async {
        final h = _Harness(rows: [pendingOfferRow(offerer: _otherHelper)]);
        addTearDown(h.dispose);
        await h.load();
        final fetchesBefore = h.coordination.fetchCalls;

        h.sendPeopleSeen(seen1205);
        await h.settle();

        expect(h.seenAtOf(_otherHelper), isNull);
        expect(h.emitted, isEmpty);
        expect(h.coordination.fetchCalls, fetchesBefore);
      },
    );

    test(
      "author viewer: a frame does not stamp helpers' offers (bulk stamping "
      'belongs to reportPeopleSurfaceViewed)',
      () async {
        final h = _Harness(
          rows: [
            pendingOfferRow(),
            pendingOfferRow(offerer: _otherHelper),
          ],
          viewer: kAuthor,
        );
        addTearDown(h.dispose);
        await h.load();
        final fetchesBefore = h.coordination.fetchCalls;

        h.sendPeopleSeen(seen1205);
        await h.settle();

        expect(h.seenAtOf(kOfferer), isNull);
        expect(h.seenAtOf(_otherHelper), isNull);
        expect(h.emitted, isEmpty);
        expect(h.coordination.fetchCalls, fetchesBefore);
      },
    );
  });

  group('BeaconViewCubit offers refetch vs local authorSeenAt', () {
    FakeHelpOfferCoordinationRow markerRow() => pendingOfferRow(
      offerer: _markerHelper,
      createdAt: DateTime.utc(2026, 6, 15, 12, 6),
    );

    /// Starts an offers refetch (help-offer invalidation → request-detail
    /// refresh) that will return exactly [serverRows]; it is held in flight
    /// until [completeRefetch]. Include [markerRow] so completion is visible.
    Future<void> startRefetch(
      _Harness h,
      List<FakeHelpOfferCoordinationRow> serverRows,
    ) async {
      final before = h.coordination.fetchCalls;
      h.coordination
        ..gate = Completer<void>()
        ..serverRows = serverRows;
      h.invalidateHelpOffers();
      await waitFor(() => h.coordination.fetchCalls > before);
    }

    /// Releases the held refetch and waits until the cubit has applied it
    /// (the marker offer only exists in the refetch result).
    Future<void> completeRefetch(_Harness h) async {
      final gate = h.coordination.gate!;
      h.coordination.gate = null;
      gate.complete();
      await waitFor(
        () => h.cubit.state.helpOffers.any(
          (o) => o.user.id == _markerHelper.id,
        ),
      );
      await h.settle();
    }

    test(
      'refetch returning null that completes after the frame keeps the '
      'local authorSeenAt',
      () async {
        final h = _Harness(rows: [pendingOfferRow()]);
        addTearDown(h.dispose);
        await h.load();

        await startRefetch(h, [pendingOfferRow(), markerRow()]);
        h.sendPeopleSeen(seen1205);
        await h.settle();
        expect(h.seenAtOf(kOfferer), seen1205);

        await completeRefetch(h);

        expect(
          h.seenAtOf(kOfferer),
          seen1205,
          reason: 'a null server authorSeenAt must not clear the local stamp',
        );
        expect(h.seenAtOf(_markerHelper), isNull);
      },
    );

    test(
      'refetch returning an earlier value that completes after the frame '
      'keeps the later local value',
      () async {
        final h = _Harness(rows: [pendingOfferRow()]);
        addTearDown(h.dispose);
        await h.load();

        await startRefetch(h, [
          pendingOfferRow(authorSeenAt: seen1205),
          markerRow(),
        ]);
        h.sendPeopleSeen(seen1208);
        await h.settle();
        expect(h.seenAtOf(kOfferer), seen1208);

        await completeRefetch(h);

        expect(h.seenAtOf(kOfferer), seen1208);
      },
    );

    test(
      'refetch returning a later value that completes after the frame '
      'takes the server value',
      () async {
        final h = _Harness(rows: [pendingOfferRow()]);
        addTearDown(h.dispose);
        await h.load();

        await startRefetch(h, [
          pendingOfferRow(authorSeenAt: seen1208),
          markerRow(),
        ]);
        h.sendPeopleSeen(seen1205);
        await h.settle();
        expect(h.seenAtOf(kOfferer), seen1205);

        await completeRefetch(h);

        expect(h.seenAtOf(kOfferer), seen1208);
      },
    );

    for (final (label, frameAt) in [
      ('older', DateTime.utc(2026, 6, 15, 12, 5)),
      ('newer', DateTime.utc(2026, 6, 15, 12, 10)),
    ]) {
      test(
        'a $label frame arriving after a refetch that returned a value '
        'leaves the server value, emits nothing and does not refetch',
        () async {
          final h = _Harness(rows: [pendingOfferRow()]);
          addTearDown(h.dispose);
          await h.load();

          await startRefetch(h, [
            pendingOfferRow(authorSeenAt: seen1208),
            markerRow(),
          ]);
          await completeRefetch(h);
          expect(h.seenAtOf(kOfferer), seen1208);
          final fetchesBefore = h.coordination.fetchCalls;
          final emittedBefore = h.emitted.length;

          h.sendPeopleSeen(frameAt);
          await h.settle();

          expect(
            h.seenAtOf(kOfferer),
            seen1208,
            reason: 'a frame only stamps an offer whose authorSeenAt is null',
          );
          expect(h.emitted, hasLength(emittedBefore));
          expect(h.coordination.fetchCalls, fetchesBefore);
        },
      );
    }

    test(
      'refetch that reorders offers and adds one merges authorSeenAt by '
      'offer user id: null server keeps the local own stamp',
      () async {
        final otherSeen = DateTime.utc(2026, 6, 15, 12, 3);
        final h = _Harness(
          rows: [
            pendingOfferRow(),
            pendingOfferRow(offerer: _otherHelper, authorSeenAt: otherSeen),
          ],
        );
        addTearDown(h.dispose);
        await h.load();
        h.sendPeopleSeen(seen1208);
        await h.settle();
        expect(h.seenAtOf(kOfferer), seen1208);
        expect(h.seenAtOf(_otherHelper), otherSeen);

        // New offer first, then the two known offers in swapped order: an
        // index-based merge would put the own stamp on the marker offer.
        await startRefetch(h, [
          markerRow(),
          pendingOfferRow(offerer: _otherHelper, authorSeenAt: otherSeen),
          pendingOfferRow(),
        ]);
        await completeRefetch(h);

        expect(
          h.cubit.state.helpOffers.map((o) => o.user.id),
          [_markerHelper.id, _otherHelper.id, kOfferer.id],
          reason: 'the merged list keeps the server order',
        );
        expect(h.seenAtOf(kOfferer), seen1208);
        expect(h.seenAtOf(_otherHelper), otherSeen);
        expect(h.seenAtOf(_markerHelper), isNull);
      },
    );

    test(
      'refetch that reorders offers with distinct timestamps keeps the '
      'later value per offer user id',
      () async {
        final otherLocal = DateTime.utc(2026, 6, 15, 12, 3);
        final otherServer = DateTime.utc(2026, 6, 15, 12, 4);
        final h = _Harness(
          rows: [
            pendingOfferRow(),
            pendingOfferRow(offerer: _otherHelper, authorSeenAt: otherLocal),
          ],
        );
        addTearDown(h.dispose);
        await h.load();

        await startRefetch(h, [
          markerRow(),
          pendingOfferRow(offerer: _otherHelper, authorSeenAt: otherServer),
          pendingOfferRow(authorSeenAt: seen1205),
        ]);
        h.sendPeopleSeen(seen1208);
        await h.settle();
        expect(h.seenAtOf(kOfferer), seen1208);

        await completeRefetch(h);

        expect(h.seenAtOf(kOfferer), seen1208, reason: 'local 12:08 > 12:05');
        expect(
          h.seenAtOf(_otherHelper),
          otherServer,
          reason: 'server 12:04 > local 12:03',
        );
        expect(h.seenAtOf(_markerHelper), isNull);
      },
    );

    test(
      'refetch returning null keeps a local stamp from an earlier frame '
      'for the own offer and leaves other helpers unseen',
      () async {
        final h = _Harness(
          rows: [
            pendingOfferRow(),
            pendingOfferRow(offerer: _otherHelper),
          ],
        );
        addTearDown(h.dispose);
        await h.load();

        h.sendPeopleSeen(seen1205);
        await h.settle();
        await startRefetch(h, [
          pendingOfferRow(),
          pendingOfferRow(offerer: _otherHelper),
          markerRow(),
        ]);
        await completeRefetch(h);

        expect(h.seenAtOf(kOfferer), seen1205);
        expect(h.seenAtOf(_otherHelper), isNull);
      },
    );
  });
}
