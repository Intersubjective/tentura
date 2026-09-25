// BeaconViewCubit.reportPeopleSurfaceViewed (plan §P4.1): the People surface
// reports "viewed" as the author or a steward; the cubit sends at most one
// MarkBeaconPeopleSeen at a time, stamps `authorSeenAt` locally on success,
// re-arms once for offers created after the returned `seenAt`, and swallows
// errors silently (like RoomCubit.markSeenNowIfNeeded).
//
// BeaconViewCase is a final class, so the "mocked case" is the real case over
// a recording coordination repository (`markBeaconPeopleSeen` is the only I/O
// `BeaconViewCase.markPeopleSeen` performs).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'help_offer_author_seen_test_support.dart';

const _otherOfferer = Profile(id: 'Uofferer00002', displayName: 'Late');
const _boundaryOfferer = Profile(id: 'Uofferer00003', displayName: 'Edge');
const _seenOfferer = Profile(id: 'Uofferer00004', displayName: 'Seen');
const _withdrawnOfferer = Profile(id: 'Uofferer00005', displayName: 'Gone');

/// Records every `markBeaconPeopleSeen` call. Each call answers with the next
/// entry of [responses] (a [DateTime] or an error to throw); the last entry
/// repeats. With [hold] set, calls wait for it before answering.
class _PeopleSeenCoordinationRepository
    extends FakeBeaconViewCoordinationRepository {
  _PeopleSeenCoordinationRepository({
    required super.rows,
    List<Object>? responses,
  }) : responses = responses ?? [DateTime.utc(2026, 6, 15, 12, 10)];

  List<Object> responses;
  Completer<void>? hold;
  final calls = <String>[];

  @override
  Future<DateTime> markBeaconPeopleSeen(String beaconId) async {
    final index = calls.length;
    calls.add(beaconId);
    final gate = hold;
    if (gate != null) await gate.future;
    final response = responses[index < responses.length
        ? index
        : responses.length - 1];
    if (response is DateTime) return response;
    throw response;
  }
}

class _Harness {
  _Harness({
    required List<FakeHelpOfferCoordinationRow> rows,
    List<Object>? responses,
    this.viewer = kAuthor,
    List<BeaconParticipant> participants = const [],
  }) {
    coordination = _PeopleSeenCoordinationRepository(
      rows: rows,
      responses: responses,
    );
    beaconRepo = TrackingBeaconRepository()
      ..fetchByIdHandler = (_) async => authorSeenBeacon();
    cubit = BeaconViewCubit(
      id: kAuthorSeenBeaconId,
      myProfile: viewer,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        coordinationRepo: coordination,
        roomRepo: FakeBeaconViewRoomRepository(participants: participants),
      ),
      effects: effects,
    );
  }

  final Profile viewer;
  final effects = FakeUiEffectPort();
  late final _PeopleSeenCoordinationRepository coordination;
  late final TrackingBeaconRepository beaconRepo;
  late final BeaconViewCubit cubit;

  Future<void> load() => waitFor(
    () =>
        cubit.state.beaconContextLoaded &&
        cubit.state.roomParticipantsLoaded &&
        cubit.state.helpOffers.isNotEmpty,
  );

  /// Lets the re-arm microtask and any follow-up call settle.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  Future<void> dispose() async {
    await cubit.close();
    await beaconRepo.dispose();
  }
}

void main() {
  final seenAt = DateTime.utc(2026, 6, 15, 12, 10);

  group('BeaconViewCubit.reportPeopleSurfaceViewed', () {
    test(
      'author with one unseen pending offer: one call, offer stamped',
      () async {
        final h = _Harness(rows: [pendingOfferRow()]);
        addTearDown(h.dispose);
        await h.load();

        await h.cubit.reportPeopleSurfaceViewed();
        await h.settle();

        expect(h.coordination.calls, [kAuthorSeenBeaconId]);
        expect(h.cubit.state.helpOffers.single.authorSeenAt, seenAt);
        expect(h.effects.emitted, isEmpty);
      },
    );

    test(
      'stamps every eligible offer (createdAt <= seenAt) and keeps an '
      'already-seen timestamp (withdrawn offers stamped too)',
      () async {
        final earlierSeen = DateTime.utc(2026, 6, 15, 11, 30);
        final h = _Harness(
          rows: [
            pendingOfferRow(),
            pendingOfferRow(offerer: _boundaryOfferer, createdAt: seenAt),
            pendingOfferRow(
              offerer: _seenOfferer,
              createdAt: DateTime.utc(2026, 6, 15, 11),
              authorSeenAt: earlierSeen,
            ),
            offerRow(
              offerer: _withdrawnOfferer,
              createdAt: DateTime.utc(2026, 6, 15, 11, 45),
              status: 1,
            ),
          ],
        );
        addTearDown(h.dispose);
        await waitFor(
          () =>
              h.cubit.state.beaconContextLoaded &&
              h.cubit.state.roomParticipantsLoaded &&
              h.cubit.state.helpOffers.length == 4,
        );
        expect(
          h.cubit.state.helpOffers
              .singleWhere((o) => o.user.id == _withdrawnOfferer.id)
              .isWithdrawn,
          isTrue,
        );

        await h.cubit.reportPeopleSurfaceViewed();
        await h.settle();

        expect(h.coordination.calls, hasLength(1));
        final byUser = {
          for (final o in h.cubit.state.helpOffers) o.user.id: o.authorSeenAt,
        };
        expect(byUser[kOfferer.id], seenAt);
        expect(byUser[_boundaryOfferer.id], seenAt);
        expect(byUser[_seenOfferer.id], earlierSeen);
        expect(byUser[_withdrawnOfferer.id], seenAt);
      },
    );

    test('no offers at all: no call', () async {
      final h = _Harness(rows: const []);
      addTearDown(h.dispose);
      await waitFor(
        () =>
            h.cubit.state.beaconContextLoaded &&
            h.cubit.state.roomParticipantsLoaded,
      );
      expect(h.cubit.state.isAuthorOrSteward, isTrue);
      expect(h.cubit.state.helpOffers, isEmpty);

      await h.cubit.reportPeopleSurfaceViewed();
      await h.settle();

      expect(h.coordination.calls, isEmpty);
    });

    test('closed cubit: no call', () async {
      final h = _Harness(rows: [pendingOfferRow()]);
      addTearDown(h.dispose);
      await h.load();
      await h.cubit.close();

      await h.cubit.reportPeopleSurfaceViewed();
      await h.settle();

      expect(h.coordination.calls, isEmpty);
    });

    test('steward counts as moderator', () async {
      final h = _Harness(
        rows: [pendingOfferRow()],
        viewer: kSteward,
        participants: [stewardParticipant()],
      );
      addTearDown(h.dispose);
      await h.load();
      expect(h.cubit.state.isAuthorOrSteward, isTrue);

      await h.cubit.reportPeopleSurfaceViewed();
      await h.settle();

      expect(h.coordination.calls, hasLength(1));
      expect(h.cubit.state.helpOffers.single.authorSeenAt, seenAt);
    });

    test('non-moderator viewer: no call', () async {
      final h = _Harness(
        rows: [pendingOfferRow(offerer: _otherOfferer)],
        viewer: kOfferer,
      );
      addTearDown(h.dispose);
      await h.load();
      expect(h.cubit.state.isAuthorOrSteward, isFalse);

      await h.cubit.reportPeopleSurfaceViewed();
      await h.settle();

      expect(h.coordination.calls, isEmpty);
      expect(h.cubit.state.helpOffers.single.authorSeenAt, isNull);
    });

    test('all offers already seen: no call', () async {
      final h = _Harness(
        rows: [
          pendingOfferRow(authorSeenAt: DateTime.utc(2026, 6, 15, 12, 5)),
        ],
      );
      addTearDown(h.dispose);
      await h.load();

      await h.cubit.reportPeopleSurfaceViewed();
      await h.settle();

      expect(h.coordination.calls, isEmpty);
    });

    test('only a withdrawn unseen offer: no call', () async {
      final h = _Harness(rows: [offerRow(status: 1)]);
      addTearDown(h.dispose);
      await h.load();
      expect(h.cubit.state.helpOffers.single.isWithdrawn, isTrue);
      expect(h.cubit.state.helpOffers.single.authorSeenAt, isNull);

      await h.cubit.reportPeopleSurfaceViewed();
      await h.settle();

      expect(h.coordination.calls, isEmpty);
    });

    test('two concurrent calls: one mutation', () async {
      final h = _Harness(rows: [pendingOfferRow()]);
      addTearDown(h.dispose);
      await h.load();
      h.coordination.hold = Completer<void>();

      final first = h.cubit.reportPeopleSurfaceViewed();
      final second = h.cubit.reportPeopleSurfaceViewed();
      await Future<void>.delayed(Duration.zero);
      expect(h.coordination.calls, hasLength(1));

      h.coordination.hold!.complete();
      await Future.wait([first, second]);
      await h.settle();

      expect(h.coordination.calls, hasLength(1));
      expect(h.cubit.state.helpOffers.single.authorSeenAt, seenAt);
    });

    test(
      'offer created after returned seenAt re-arms a second call',
      () async {
        final laterSeenAt = DateTime.utc(2026, 6, 15, 12, 30);
        final h = _Harness(
          rows: [
            pendingOfferRow(),
            pendingOfferRow(
              offerer: _otherOfferer,
              createdAt: DateTime.utc(2026, 6, 15, 12, 20),
            ),
          ],
          responses: [seenAt, laterSeenAt],
        );
        addTearDown(h.dispose);
        await h.load();
        h.coordination.hold = Completer<void>();

        final pending = h.cubit.reportPeopleSurfaceViewed();
        await Future<void>.delayed(Duration.zero);
        expect(h.coordination.calls, hasLength(1));

        h.coordination.hold!.complete();
        await pending;
        await waitFor(() => h.coordination.calls.length >= 2);
        await h.settle();

        expect(h.coordination.calls, hasLength(2));
        final byUser = {
          for (final o in h.cubit.state.helpOffers) o.user.id: o.authorSeenAt,
        };
        expect(byUser[kOfferer.id], seenAt);
        expect(byUser[_otherOfferer.id], laterSeenAt);
      },
    );

    test(
      'markPeopleSeen error: state unchanged, silent, later call retries',
      () async {
        final h = _Harness(
          rows: [pendingOfferRow()],
          responses: [StateError('boom'), seenAt],
        );
        addTearDown(h.dispose);
        await h.load();
        final before = h.cubit.state;

        await h.cubit.reportPeopleSurfaceViewed();
        await h.settle();

        expect(h.coordination.calls, hasLength(1));
        expect(h.cubit.state.helpOffers.single.authorSeenAt, isNull);
        expect(h.cubit.state, before);
        expect(h.effects.emitted, isEmpty);

        await h.cubit.reportPeopleSurfaceViewed();
        await h.settle();

        expect(h.coordination.calls, hasLength(2));
        expect(h.cubit.state.helpOffers.single.authorSeenAt, seenAt);
      },
    );
  });
}
