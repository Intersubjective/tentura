// Issue #178 part 2: the offerer sees "Sent · not seen by the author yet" vs
// "Seen by the author · awaiting decision" on a pending help offer, and a
// `people_seen` realtime frame flips it in place, per offer (an offer counts
// as seen when the watermark is at/after its `createdAt`), without reloading
// the offers. Opening the People surface as the author or a steward marks it
// seen via `CoordinationRepository.markBeaconPeopleSeen` (mirrors
// `markThreadSeen`; V2 mutation `MarkBeaconPeopleSeen`). The initial-query
// `authorSeenAt` path is in `help_offer_author_seen_initial_query_test.dart`;
// the GraphQL document/routing wiring in `help_offer_author_seen_gql_test.dart`.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/profile.dart';

import 'help_offer_author_seen_test_support.dart';

void expectPeopleSurfaceMarkedCurrentOffersSeen(
  CountingCoordinationRepository coordination,
) {
  final calls = coordination.markPeopleSeenCalls;
  expect(calls, isNotEmpty);
  expect(calls.map((call) => call.beaconId).toSet(), {kAuthorSeenBeaconId});
  for (final call in calls) {
    final readThroughAt = call.readThroughAt;
    expect(
      readThroughAt == null || !readThroughAt.isBefore(kOfferCreatedAt),
      isTrue,
      reason: 'a supplied watermark must cover the pending offer',
    );
  }
}

void main() {
  group('offerer author-seen label', () {
    testWidgets('pending offer not yet seen shows the "not seen" label', (
      tester,
    ) async {
      final h = (await tester.runAsync(() async {
        final h = AuthorSeenHarness();
        await h.load();
        return h;
      }))!;
      await pumpPeople(tester, h.cubit.state);

      expect(find.text(kNotSeenLabel), findsOneWidget);
      expect(find.text(kSeenLabel), findsNothing);
      expect(find.text('author review required'), findsNothing);

      await tester.runAsync(h.dispose);
    });

    testWidgets('pending backup offer also shows the "not seen" label', (
      tester,
    ) async {
      final h = (await tester.runAsync(() async {
        final h = AuthorSeenHarness(offerKind: 1);
        await h.load();
        return h;
      }))!;
      await pumpPeople(tester, h.cubit.state);

      expect(find.text(kNotSeenLabel), findsOneWidget);

      await tester.runAsync(h.dispose);
    });

    testWidgets(
      'people_seen frame flips the visible label to "seen" in place, '
      'without reloading offers',
      (tester) async {
        final h = (await tester.runAsync(() async {
          final h = AuthorSeenHarness();
          await h.load();
          return h;
        }))!;
        // Mount the live People surface first: the offerer is looking at
        // the "not seen" label when the author opens People.
        await openPeopleSurface(tester, h);
        expect(find.text(kNotSeenLabel), findsOneWidget);
        expect(find.text(kSeenLabel), findsNothing);
        final offersFetchesBefore = h.coordination.fetchCalls;
        final beaconFetchesBefore = h.beaconRepo.fetchByIdCalls;

        await tester.runAsync(
          () => h.send(
            peopleSeenFrame(lastSeenAt: '2026-06-15T12:05:00.000Z'),
          ),
        );
        await tester.pump();

        expect(find.text(kSeenLabel), findsOneWidget);
        expect(find.text(kNotSeenLabel), findsNothing);
        expect(
          h.coordination.fetchCalls,
          offersFetchesBefore,
          reason: 'people_seen must patch in place, not refetch offers',
        );
        expect(
          h.beaconRepo.fetchByIdCalls,
          beaconFetchesBefore,
          reason: 'people_seen must not trigger a request-detail refresh',
        );

        await tester.runAsync(h.dispose);
      },
    );

    testWidgets('older people_seen cannot undo a newer seen watermark', (
      tester,
    ) async {
      final h = (await tester.runAsync(() async {
        final h = AuthorSeenHarness();
        await h.load();
        return h;
      }))!;
      await openPeopleSurface(tester, h);
      final offersFetchesBefore = h.coordination.fetchCalls;
      final beaconFetchesBefore = h.beaconRepo.fetchByIdCalls;

      await tester.runAsync(
        () => h.send(
          peopleSeenFrame(lastSeenAt: '2026-06-15T12:05:00.000Z'),
        ),
      );
      await tester.pump();
      expect(find.text(kSeenLabel), findsOneWidget);

      await tester.runAsync(
        () => h.send(
          peopleSeenFrame(lastSeenAt: '2026-06-15T11:55:00.000Z'),
        ),
      );
      await tester.pump();
      expect(find.text(kSeenLabel), findsOneWidget);
      expect(find.text(kNotSeenLabel), findsNothing);
      expect(h.coordination.fetchCalls, offersFetchesBefore);
      expect(h.beaconRepo.fetchByIdCalls, beaconFetchesBefore);

      await tester.runAsync(h.dispose);
    });

    testWidgets(
      'one people_seen watermark between two offers: earlier offer seen, '
      'later offer not (per-offer cutoff)',
      (tester) async {
        const earlier = kOfferer;
        const later = Profile(id: 'Uofferer00002', displayName: 'Late');
        // Watermark 12:05 falls between the 12:00 and 12:10 offers.
        List<FakeHelpOfferCoordinationRow> rows() => [
          pendingOfferRow(createdAt: kOfferCreatedAt),
          pendingOfferRow(
            offerer: later,
            createdAt: kOfferCreatedAt.add(const Duration(minutes: 10)),
          ),
        ];
        for (final (viewer, seen) in [(earlier, true), (later, false)]) {
          late AuthorSeenHarness h;
          await tester.runAsync(() async {
            h = AuthorSeenHarness(viewer: viewer, rows: rows());
            await h.load();
            await h.send(
              peopleSeenFrame(lastSeenAt: '2026-06-15T12:05:00.000Z'),
            );
          });
          await pumpPeople(tester, h.cubit.state, viewer: viewer);

          expect(
            find.text(kSeenLabel),
            seen ? findsOneWidget : findsNothing,
            reason: viewer.id,
          );
          expect(
            find.text(kNotSeenLabel),
            seen ? findsNothing : findsOneWidget,
            reason: viewer.id,
          );

          await tester.runAsync(h.dispose);
        }
      },
    );

    testWidgets(
      'people_seen exactly at the offer createdAt counts as seen (>=)',
      (tester) async {
        late AuthorSeenHarness h;
        await tester.runAsync(() async {
          h = AuthorSeenHarness();
          await h.load();
          // kOfferCreatedAt is 2026-06-15T12:00:00Z.
          await h.send(
            peopleSeenFrame(lastSeenAt: '2026-06-15T12:00:00.000Z'),
          );
        });
        await pumpPeople(tester, h.cubit.state);

        expect(find.text(kSeenLabel), findsOneWidget);
        expect(find.text(kNotSeenLabel), findsNothing);

        await tester.runAsync(h.dispose);
      },
    );

    testWidgets('people_seen older than the offer keeps "not seen"', (
      tester,
    ) async {
      late AuthorSeenHarness h;
      await tester.runAsync(() async {
        h = AuthorSeenHarness();
        await h.load();
        await h.send(peopleSeenFrame(lastSeenAt: '2026-06-15T11:00:00.000Z'));
      });
      await pumpPeople(tester, h.cubit.state);

      expect(find.text(kNotSeenLabel), findsOneWidget);
      expect(find.text(kSeenLabel), findsNothing);

      await tester.runAsync(h.dispose);
    });

    testWidgets(
      'author-seen label shows only on a pending offer, not on withdrawn, '
      'accepted or declined ones',
      (tester) async {
        // Non-pending offers must show neither label, whether the author has
        // seen them or no watermark has been recorded.
        final seenAt = kOfferCreatedAt.add(const Duration(minutes: 5));
        final cases = <(String, FakeHelpOfferCoordinationRow, bool)>[
          ('pending', offerRow(authorSeenAt: seenAt), true),
          ('withdrawn', offerRow(status: 1, authorSeenAt: seenAt), false),
          ('withdrawn without watermark', offerRow(status: 1), false),
          (
            'accepted',
            offerRow(
              roomAccess: RoomAccessBits.admitted,
              admissionAction: HelpOfferAdmissionAction.accept.smallintValue,
              authorSeenAt: seenAt,
            ),
            false,
          ),
          (
            'accepted without watermark',
            offerRow(
              roomAccess: RoomAccessBits.admitted,
              admissionAction: HelpOfferAdmissionAction.accept.smallintValue,
            ),
            false,
          ),
          (
            'declined',
            offerRow(
              admissionAction: HelpOfferAdmissionAction.decline.smallintValue,
              lastDeclineReason: 'Covered already',
              authorSeenAt: seenAt,
            ),
            false,
          ),
          (
            'declined without watermark',
            offerRow(
              admissionAction: HelpOfferAdmissionAction.decline.smallintValue,
              lastDeclineReason: 'Covered already',
            ),
            false,
          ),
        ];
        for (final (name, row, showsLabel) in cases) {
          final h = (await tester.runAsync(() async {
            final h = AuthorSeenHarness(rows: [row]);
            await h.load();
            return h;
          }))!;
          await pumpPeople(tester, h.cubit.state);

          expect(
            find.text(kSeenLabel),
            showsLabel ? findsOneWidget : findsNothing,
            reason: name,
          );
          expect(find.text(kNotSeenLabel), findsNothing, reason: name);

          await tester.runAsync(h.dispose);
        }
      },
    );

    testWidgets('people_seen for another request is ignored', (tester) async {
      late AuthorSeenHarness h;
      await tester.runAsync(() async {
        h = AuthorSeenHarness();
        await h.load();
        await h.send(
          peopleSeenFrame(
            beaconId: 'Bsomeotherone',
            lastSeenAt: '2026-06-15T12:05:00.000Z',
          ),
        );
      });
      await pumpPeople(tester, h.cubit.state);

      expect(find.text(kNotSeenLabel), findsOneWidget);
      expect(find.text(kSeenLabel), findsNothing);

      await tester.runAsync(h.dispose);
    });
  });

  group('opening the People surface marks it seen', () {
    testWidgets('author opening People calls MarkBeaconPeopleSeen', (
      tester,
    ) async {
      final h = (await tester.runAsync(() async {
        final h = AuthorSeenHarness(viewer: kAuthor);
        await h.load();
        return h;
      }))!;
      expect(h.coordination.markPeopleSeenCalls, isEmpty);

      await openPeopleSurface(tester, h);

      expectPeopleSurfaceMarkedCurrentOffersSeen(h.coordination);
      expect(find.text(kNotSeenLabel), findsNothing);
      expect(find.text(kSeenLabel), findsNothing);

      await tester.runAsync(h.dispose);
    });

    testWidgets('steward opening People calls MarkBeaconPeopleSeen', (
      tester,
    ) async {
      final h = (await tester.runAsync(() async {
        final h = AuthorSeenHarness(
          viewer: kSteward,
          participants: [stewardParticipant()],
        );
        await h.load();
        await waitFor(() => h.cubit.state.isSteward);
        return h;
      }))!;

      await openPeopleSurface(tester, h);

      expectPeopleSurfaceMarkedCurrentOffersSeen(h.coordination);
      expect(find.text(kNotSeenLabel), findsNothing);
      expect(find.text(kSeenLabel), findsNothing);

      await tester.runAsync(h.dispose);
    });

    testWidgets('offerer opening People does not mark it seen', (
      tester,
    ) async {
      final h = (await tester.runAsync(() async {
        final h = AuthorSeenHarness();
        await h.load();
        return h;
      }))!;

      await openPeopleSurface(tester, h);

      expect(h.coordination.markPeopleSeenCalls, isEmpty);

      await tester.runAsync(h.dispose);
    });
  });
}
