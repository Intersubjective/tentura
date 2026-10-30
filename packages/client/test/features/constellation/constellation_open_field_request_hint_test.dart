import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/repository/constellation_targeted_read_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_account_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_targeted_read_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_freshness_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/like/domain/port/person_trust_writes_port.dart';

import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _viewer = Profile(id: 'kai', displayName: 'Kai');
const _authorId = 'max';
const _published = ConstellationRequest(
  id: 'published',
  authorId: _authorId,
  title: 'Published without sending',
  status: 0,
);

void main() {
  group('An open Field follows contact Request hints', () {
    test(
      'a discoverable Request increases the count and author overflow without '
      'a reload',
      () async {
        final h = _FieldHarness();
        addTearDown(h.dispose);
        await _flush();
        await h.cubit.load();
        await _flush();

        expect(h.cubit.state.field!.requests, hasLength(5));
        expect(h.cubit.visibilityCounts!.requests, 5);
        final hiddenBefore = h.cubit.overflowHiddenCountByAuthor[_authorId]!;
        expect(hiddenBefore, greaterThan(0));
        final fullReads = h.repository.fullReads;
        final clusterBefore = Set<String>.of(
          h
              .cubit
              .state
              .composition!
              .labelPlan
              .layoutRequestsByAuthor[_authorId]!,
        );
        expect(clusterBefore, hasLength(5));

        h.repository.publications.add((
          request: _published,
          discoverable: true,
        ));
        final responseGate = h.repository.responseGate = Completer<void>();
        h.hint(_published.id);
        await _flush();
        h.advance();
        await _flush();

        expect(h.repository.requestReads.last, {_published.id});
        expect(h.cubit.state.field!.requests, hasLength(5));
        responseGate.complete();
        await _flush();
        expect(h.repository.returnedRequests.last, [_published]);
        expect(h.repository.fullReads, fullReads);
        expect(h.cubit.state.field!.requests, hasLength(6));
        expect(h.cubit.requestById(_published.id), _published);
        expect(h.cubit.visibilityCounts!.requests, 6);
        expect(
          h
              .cubit
              .state
              .composition!
              .labelPlan
              .layoutRequestsByAuthor[_authorId],
          unorderedEquals([...clusterBefore, _published.id]),
        );
        expect(
          h.cubit.discoverableRequestsForPerson(_authorId),
          contains(_published),
        );
        expect(
          h.cubit.overflowHiddenCountByAuthor[_authorId],
          hiddenBefore + 1,
        );

        // Keep the same Field open past the reported stale interval. A late
        // state emission must not restore the five-Request snapshot.
        h.advance(const Duration(seconds: 112));
        await _flush();
        expect(h.cubit.state.field!.requests, hasLength(6));
        expect(h.cubit.visibilityCounts!.requests, 6);
        expect(
          h.cubit.overflowHiddenCountByAuthor[_authorId],
          hiddenBefore + 1,
        );
        expect(h.repository.fullReads, fullReads);

        // Opening the updated author's overflow must actually draw the new
        // member, not merely increment a counter over a stale cluster.
        h.cubit.toggleSatelliteOverflow(_authorId);
        await _flush();
        expect(
          h.cubit.layoutVisibleRequestsByAuthor[_authorId],
          unorderedEquals([...clusterBefore, _published.id]),
        );
        expect(h.cubit.displayedRequestIds, contains(_published.id));
        expect(
          h.cubit.state.composition!.eligibleRequestIds,
          contains(_published.id),
        );
        expect(h.repository.fullReads, fullReads);
      },
    );

    test('a hint for a published non-discoverable Request leaves the five '
        'Requests and author overflow unchanged', () async {
      final h = _FieldHarness();
      addTearDown(h.dispose);
      await _flush();
      await h.cubit.load();
      await _flush();
      expect(h.cubit.state.field!.requests, hasLength(5));
      expect(h.cubit.visibilityCounts!.requests, 5);
      final hiddenBefore = h.cubit.overflowHiddenCountByAuthor[_authorId]!;
      expect(hiddenBefore, greaterThan(0));
      final fullReads = h.repository.fullReads;

      final request = _published.copyWith(id: 'not-discoverable');
      h.repository.publications.add((request: request, discoverable: false));
      h.hint(request.id);
      await _flush();
      h.advance();
      await _flush();

      // The fake models the authorized port's response distinction. This
      // verifies the cubit's empty-result control; the PG test independently
      // verifies that production filtering excludes discoverability-off rows.
      expect(h.repository.requestReads, [
        {request.id},
      ]);
      expect(h.repository.returnedRequests, [<ConstellationRequest>[]]);
      expect(h.cubit.state.field!.requests, hasLength(5));
      expect(h.cubit.visibilityCounts!.requests, 5);
      expect(h.cubit.requestById(request.id), isNull);
      expect(h.cubit.overflowHiddenCountByAuthor[_authorId], hiddenBefore);
      expect(h.repository.fullReads, fullReads);
    });

    test('the real targeted repository preserves five open-Field Requests '
        'when its authorized response excludes the hinted Request', () async {
      final sent = <WireSent>[];
      await withRemoteWire(
        {
          'ConstellationFieldRequestsFetch': {
            '__typename': 'query_root',
            'constellationFieldRequests': <Map<String, dynamic>>[],
          },
        },
        sent,
        (remote) async {
          final h = _FieldHarness(
            targetedReads: ConstellationTargetedReadRepository(remote),
          );
          try {
            await _flush();
            await h.cubit.load();
            await _flush();
            expect(h.cubit.state.field!.requests, hasLength(5));
            expect(h.cubit.visibilityCounts!.requests, 5);
            final clusterBefore = Set<String>.of(
              h
                  .cubit
                  .state
                  .composition!
                  .labelPlan
                  .layoutRequestsByAuthor[_authorId]!,
            );
            expect(clusterBefore, hasLength(5));
            final hiddenBefore =
                h.cubit.overflowHiddenCountByAuthor[_authorId]!;
            final fullReads = h.repository.fullReads;

            // ConstellationTargetedReadPort.fetchRequests promises only
            // published, discoverable, readable rows. Its Request DTO carries
            // no discoverability flag: policy belongs to the server. Exercise
            // the actual client repository's handling of that empty response.
            h.hint('not-discoverable');
            await _flush();
            h.advance();
            await _flush();

            expect(sent, hasLength(1));
            expect(
              sent.single.operationName,
              'ConstellationFieldRequestsFetch',
            );
            expect(sent.single.variables, {
              'ids': ['not-discoverable'],
              'showClosed': false,
              'participatedOnly': false,
            });
            expect(h.cubit.state.field!.requests, hasLength(5));
            expect(h.cubit.visibilityCounts!.requests, 5);
            expect(h.cubit.requestById('not-discoverable'), isNull);
            expect(
              h
                  .cubit
                  .state
                  .composition!
                  .labelPlan
                  .layoutRequestsByAuthor[_authorId],
              unorderedEquals(clusterBefore),
            );
            expect(
              h.cubit.overflowHiddenCountByAuthor[_authorId],
              hiddenBefore,
            );
            expect(h.repository.fullReads, fullReads);
          } finally {
            await h.dispose();
          }
        },
      );
    });

    testWidgets(
      'the mounted Field Requests chip changes from 5 to 6 after a contact '
      'publishes a discoverable Request',
      (tester) async {
        final h = _FieldHarness();
        addTearDown(h.dispose);
        // Deliver the seeded account, then finish the explicit load before
        // mounting the Field. The mounting helper need not initiate a load.
        await tester.pump();
        await h.cubit.load();
        await tester.pump();
        expect(h.cubit.state.field!.requests, hasLength(5));
        expect(h.cubit.visibilityCounts!.requests, 5);
        expect(h.repository.fullReads, 1);
        final fullReads = h.repository.fullReads;
        await pumpConstellationBody(
          tester,
          h.cubit,
          locale: const Locale('en'),
          size: const Size(1280, 900),
        );

        final chip = find.byKey(const Key('constellation.show.requests'));
        Finder count(String value) => find.descendant(
          of: chip,
          matching: find.text(value),
        );
        expect(
          find.descendant(of: chip, matching: find.text('Requests')),
          findsOneWidget,
        );
        expect(count('5'), findsOneWidget);
        final mountedChip = tester.element(chip);
        expect(h.repository.fullReads, fullReads);

        h.repository.publications.add((
          request: _published,
          discoverable: true,
        ));
        final responseGate = h.repository.responseGate = Completer<void>();
        h.hint(_published.id);
        await tester.pump();
        h.advance();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();

        expect(h.repository.requestReads, [
          {_published.id},
        ]);
        expect(count('5'), findsOneWidget);
        responseGate.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(h.repository.returnedRequests, [
          [_published],
        ]);
        expect(h.repository.fullReads, fullReads);
        expect(tester.element(chip), same(mountedChip));
        expect(count('6'), findsOneWidget);
        expect(count('5'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}

Future<void> _flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _FieldRepository
    implements ConstellationRepositoryPort, ConstellationTargetedReadPort {
  int fullReads = 0;
  final requestReads = <Set<String>>[];
  final returnedRequests = <List<ConstellationRequest>>[];
  final publications = <({ConstellationRequest request, bool discoverable})>[];
  Completer<void>? responseGate;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    fullReads++;
    return ConstellationField(
      loadedAt: DateTime.utc(2026, 10, 30),
      context: '',
      peers: const [ConstellationPerson(id: _authorId, displayName: 'Max')],
      directContactIds: const [_authorId],
      edges: const [
        ConstellationTrustEdgeEntity(src: 'kai', dst: _authorId, tier: 1),
        ConstellationTrustEdgeEntity(src: _authorId, dst: 'kai', tier: 1),
      ],
      requests: [
        for (var i = 0; i < 5; i++)
          ConstellationRequest(
            id: 'existing-$i',
            authorId: _authorId,
            title: 'Existing Request $i',
            status: 0,
          ),
      ],
    );
  }

  @override
  Future<List<ConstellationRequest>> fetchRequests(
    Set<String> beaconIds, {
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
  }) async {
    requestReads.add(Set.of(beaconIds));
    final result = [
      for (final publication in publications)
        if (publication.discoverable &&
            beaconIds.contains(publication.request.id))
          publication.request,
    ];
    await responseGate?.future;
    returnedRequests.add(result);
    return result;
  }

  @override
  Future<List<ConstellationViewerRelation>> readViewerRelations(
    Set<String> personIds,
  ) async => const [];
}

final class _Account implements ConstellationAccountPort {
  const _Account(this.currentAccountChanges);

  @override
  final Stream<String> currentAccountChanges;
}

final class _TrustWrites implements PersonTrustWritesPort {
  @override
  Stream<PersonTrustWrite> get personTrustWrites => const Stream.empty();
}

final class _FieldHarness {
  _FieldHarness({ConstellationTargetedReadPort? targetedReads}) {
    store = ConstellationFieldStoreCase(
      repository,
      _Account(account.stream),
      clock,
      wakeUp,
      realtime.case_,
      env: const Env.fromEnvironment(),
      logger: Logger('OpenFieldRequestHintTest'),
    );
    freshness = ConstellationFieldFreshnessCase(
      store,
      targetedReads ?? repository,
      _TrustWrites(),
      realtime.case_,
      wakeUp,
      clock,
      env: const Env.fromEnvironment(),
      logger: Logger('OpenFieldRequestHintTest'),
    );
    cubit = ConstellationCubit(
      case_: store,
      viewer: _viewer,
      loadOnCreate: false,
    );
  }

  final repository = _FieldRepository();
  final account = BehaviorSubject<String>.seeded(_viewer.id);
  final clock = FakeClockPort(DateTime.utc(2026, 10, 30));
  final wakeUp = FakeWakeUpPort();
  final realtime = buildTestRealtimeSync();
  late final ConstellationFieldStoreCase store;
  late final ConstellationFieldFreshnessCase freshness;
  late final ConstellationCubit cubit;

  void hint(String id) => realtime.port.emitChange(
    RealtimeEntityChange(
      kind: RealtimeEntityKind.constellationItem,
      aggregateId: id,
      actorUserId: _authorId,
      operation: RealtimeOperation.insert,
      source: RealtimeChangeSource.serverInvalidation,
    ),
  );

  void advance([Duration by = const Duration(milliseconds: 1500)]) {
    clock.advance(by);
    wakeUp.elapse(by);
  }

  Future<void> dispose() async {
    await freshness.dispose();
    await cubit.close();
    await store.dispose();
    await account.close();
    await realtime.port.dispose();
  }
}
