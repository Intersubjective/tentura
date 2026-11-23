@Tags(['pg'])
library;

import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:tentura_server/consts/people_tag_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    show TenturaDb, driftRuntimeOptions;
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/data/repository/owner_graph_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/owner_graph_contention.dart';
import '../../support/pg_test_public_keys.dart';

const _viewer = 'Ufsviewer001';
const _otherViewer = 'Ufsviewer002';
const _firstPeer = 'Ufspeer00001';
const _secondPeer = 'Ufspeer00002';
const _newcomer = 'Ufspeer00003';
const _tag = 'Tfscontacts1';
const _backfillRows = {_firstPeer: '-infinity', _secondPeer: '-infinity'};

typedef _FirstSeen = ({
  String value,
  DateTime? finiteAt,
  DateTime? acknowledgedAt,
});

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FIELD_FIRST_SEEN_OWNER_SCOPE_TEST_DB',
    defaultNamePrefix: 'tentura_test_field_seen_scope',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb db;
  late OwnerGraphUnitOfWork ownerGraph;

  setUpAll(() async {
    final previous = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(
      () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous,
    );
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    addTearDown(() => tearDownDisposablePgWriter(session: session));
    writer = session.writer;
    final holder = openDisposablePgDatabase(target);
    addTearDown(holder.close);
    ownerGraph = OwnerGraphUnitOfWork(holder);
  });

  setUp(() async {
    await writer.execute('TRUNCATE public."user" CASCADE');
    for (final (index, id) in [
      _viewer,
      _otherViewer,
      _firstPeer,
      _secondPeer,
      _newcomer,
    ].indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key, created_at)
VALUES (@id, @id, @key, timestamptz '2026-01-01' + make_interval(days => @day))
'''),
        parameters: {
          'id': id,
          'key': pgTestPublicKey('fscope', index + 1),
          'day': index,
        },
      );
    }
    db = openDisposablePgDatabase(target);
    addTearDown(db.close);
  });

  Future<void> showPeer(String peer) => writer.execute(
    Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@viewer, @peer, 1), (@peer, @viewer, 1)
'''),
    parameters: {'viewer': _viewer, 'peer': peer},
  );

  Future<ConstellationFieldSnapshot> readField({
    TenturaDb? database,
  }) {
    final readDb = database ?? db;
    return ConstellationFieldRepository(
      readDb,
      DriftUserProfileBatchLookup(readDb, UserAvailabilityRepository(readDb)),
    ).readSnapshot(
      viewerId: _viewer,
      context: '',
      params: (
        filters: ConstellationFieldMembershipFilters.defaults,
        projection: ConstellationProjection.full,
      ),
    );
  }

  Future<Map<String, _FirstSeen>> firstSeenRows() async {
    final rows = await writer.execute(
      Sql.named('''
SELECT peer_id, first_seen_at::text,
       CASE WHEN isfinite(first_seen_at) THEN first_seen_at END,
       acknowledged_at
FROM public.person_field_first_seen WHERE viewer_id = @viewer
'''),
      parameters: {'viewer': _viewer},
    );
    return {
      for (final row in rows)
        row[0]! as String: (
          value: row[1]! as String,
          finiteAt: row[2] as DateTime?,
          acknowledgedAt: row[3] as DateTime?,
        ),
    };
  }

  Future<Map<String, _FirstSeen>> waitForFirstSeen(
    Set<String> peers,
  ) async {
    final clock = Stopwatch()..start();
    do {
      final rows = await firstSeenRows().timeout(
        ownerGraphWriteLimit - clock.elapsed,
      );
      if (rows.keys.toSet().containsAll(peers)) return rows;
      await Future<void>.delayed(const Duration(milliseconds: 15));
    } while (clock.elapsed < ownerGraphWriteLimit);
    fail('First-seen rows for $peers did not commit for $_viewer.');
  }

  Future<DateTime> databaseTime() async {
    final result = await writer.execute('SELECT clock_timestamp()');
    return result.single.single! as DateTime;
  }

  ConstellationPeerRecord peerIn(
    ConstellationFieldSnapshot snapshot,
    String id,
  ) {
    final matches = snapshot.peers.where((peer) => peer.id == id);
    expect(matches, hasLength(1), reason: '$id should be on the Field');
    return matches.single;
  }

  void expectBackfillPeer(ConstellationFieldSnapshot snapshot, String id) {
    final peer = peerIn(snapshot, id);
    expect(peer.isNew, isFalse, reason: id);
    expect(peer.firstSeenAt, isNull, reason: id);
  }

  void expectNewcomer(ConstellationFieldSnapshot snapshot) {
    final peer = peerIn(snapshot, _newcomer);
    expect(peer.isNew, isTrue);
    expect(peer.firstSeenAt, isNotNull);
  }

  Future<void> backfill() async {
    await showPeer(_firstPeer);
    await showPeer(_secondPeer);
    final snapshot = await readField().timeout(ownerGraphWriteLimit);
    expectBackfillPeer(snapshot, _firstPeer);
    expectBackfillPeer(snapshot, _secondPeer);
    final rows = await waitForFirstSeen(_backfillRows.keys.toSet());
    expect(rows.map((id, row) => MapEntry(id, row.value)), _backfillRows);
  }

  group('Field first-seen writes under owner scope contention', () {
    test(
      'shows a new peer while their first-seen write waits for the viewer',
      () async {
        await backfill();
        await showPeer(_newcomer);
        expect(await firstSeenRows(), isNot(contains(_newcomer)));

        late DateTime releasingAt;
        final rowsWhileHeld = await whileOwnerGraphScopeHeld(
          ownerGraph,
          _viewer,
          () async {
            expectNewcomer(await readField());
            return firstSeenRows();
          },
          // Sample the database clock at the holder's commit barrier so a
          // write transaction started before release cannot pass on now().
          beforeCommit: () async => releasingAt = await databaseTime(),
        );

        final stored = (await waitForFirstSeen({_newcomer}))[_newcomer]!;
        expect(
          rowsWhileHeld,
          isNot(contains(_newcomer)),
          reason: 'The newcomer row committed while the viewer scope was held.',
        );
        expect(stored.finiteAt, isNotNull);
        expect(stored.finiteAt!.isBefore(releasingAt), isFalse);
        expect(stored.finiteAt!.isAfter(await databaseTime()), isFalse);
        expect(stored.acknowledgedAt, isNull);
      },
    );

    test(
      'the first write waits for the viewer and proceeds under another scope',
      () async {
        await showPeer(_firstPeer);

        Future<bool> firstWriteWaits(String scopeOwner) async {
          expect(await firstSeenRows(), isEmpty);
          late Future<Map<String, _FirstSeen>> pendingWrite;
          final waited = await whileOwnerGraphScopeHeld(
            ownerGraph,
            scopeOwner,
            () async {
              expectBackfillPeer(await readField(), _firstPeer);
              // The repository returns the snapshot. Committed rows signal that
              // its write finished, including when it never waited for this lock.
              pendingWrite = waitForFirstSeen({_firstPeer})..ignore();
              return waitsForOwnerGraphScope(writer, scopeOwner, pendingWrite);
            },
          );
          expect((await pendingWrite)[_firstPeer]?.value, '-infinity');
          return waited;
        }

        expect(
          await firstWriteWaits(_otherViewer),
          isFalse,
          reason: 'The viewer write waited for another viewer’s scope.',
        );
        // Reset the first-read fixture so both phases write for the same viewer.
        await writer.execute(
          Sql.named(
            'DELETE FROM public.person_field_first_seen '
            'WHERE viewer_id = @viewer',
          ),
          parameters: {'viewer': _viewer},
        );
        expect(
          await firstWriteWaits(_viewer),
          isTrue,
          reason: 'The initial first-seen write bypassed the viewer scope.',
        );
      },
    );

    test(
      'deferred backfill stays unmarked and later reads preserve its rows',
      () async {
        await showPeer(_firstPeer);
        await showPeer(_secondPeer);

        final duringBackfill = await whileOwnerGraphScopeHeld(
          ownerGraph,
          _viewer,
          () async {
            final snapshot = await readField();
            expectBackfillPeer(snapshot, _firstPeer);
            expectBackfillPeer(snapshot, _secondPeer);
            return firstSeenRows();
          },
        );
        final initial = await waitForFirstSeen(_backfillRows.keys.toSet());
        expect(
          initial.map((id, row) => MapEntry(id, row.value)),
          _backfillRows,
        );

        await showPeer(_newcomer);
        final duringLaterRead = await whileOwnerGraphScopeHeld(
          ownerGraph,
          _viewer,
          () async {
            final snapshot = await readField();
            expectBackfillPeer(snapshot, _firstPeer);
            expectBackfillPeer(snapshot, _secondPeer);
            expectNewcomer(snapshot);
            return firstSeenRows();
          },
        );
        final later = await waitForFirstSeen({_newcomer});
        expect(later[_newcomer]?.finiteAt, isNotNull);
        expect(later[_firstPeer], initial[_firstPeer]);
        expect(later[_secondPeer], initial[_secondPeer]);
        expect(
          duringBackfill,
          isEmpty,
          reason: 'The backfill ran under a held scope.',
        );
        expect(
          duringLaterRead,
          initial,
          reason: 'A later sighting ran under a held scope.',
        );
      },
    );

    test(
      'returns the newcomer before their inherited tag membership commits',
      () async {
        await backfill();
        await writer.executeWithOwnerScopes(
          [_viewer],
          '''
INSERT INTO public.person_tag (id, owner_id, name, glyph, color, ord)
VALUES ('$_tag', '$_viewer', 'Contacts', 'C', 0, 0)
''',
        );
        await writer.executeWithOwnerScopes(
          [_viewer],
          '''
INSERT INTO public.person_tag_member (tag_id, owner_id, person_id, source)
VALUES ('$_tag', '$_viewer', '$_firstPeer', $kPersonTagSourceManual)
''',
        );
        await writer.execute('''
INSERT INTO public.invite_genealogy (
  descendant_node_key, ancestor_node_key, descendant_user_id, ancestor_user_id,
  ancestor_user_created_at, descendant_user_created_at)
SELECT 'nk-' || d.id, 'nk-' || a.id, d.id, a.id, a.created_at, d.created_at
FROM public."user" a, public."user" d WHERE a.id = '$_firstPeer' AND d.id = '$_newcomer'
''');
        await showPeer(_newcomer);

        Future<List<int>> membershipSources() async => [
          for (final row in await writer.execute('''
SELECT source::int FROM public.person_tag_member
WHERE owner_id = '$_viewer' AND tag_id = '$_tag' AND person_id = '$_newcomer'
'''))
            row.single! as int,
        ];

        Future<ConstellationFieldSnapshot>? pendingRead;
        List<int>? membershipsWhileHeld;
        try {
          membershipsWhileHeld = await whileOwnerGraphScopeHeld(
            ownerGraph,
            _viewer,
            () async {
              final read = readField()..ignore();
              pendingRead = read;
              expectNewcomer(await read);
              return membershipSources();
            },
          );
        } on TimeoutException {
          final read = pendingRead;
          if (read == null) rethrow;
          // Check whether the read and inheritance finish once the scope
          // is released, even on the synchronous baseline.
          expectNewcomer(await read.timeout(ownerGraphWriteLimit));
        }

        expect(
          (await waitForFirstSeen({_newcomer}))[_newcomer]?.finiteAt,
          isNotNull,
        );
        expect(await membershipSources(), [kPersonTagSourceInherited]);
        expect(
          membershipsWhileHeld,
          isNotNull,
          reason:
              'The Field snapshot waited for the newcomer’s tag inheritance.',
        );
        expect(membershipsWhileHeld, isEmpty);
      },
    );
  });

  group('Field first-seen writes with owner scope enforcement', () {
    for (final initialRead in [true, false]) {
      test(
        initialRead
            ? 'commits initial backfill with the owner scope trigger enabled'
            : 'commits a later first sighting with the owner scope trigger enabled',
        () async {
          if (initialRead) {
            await showPeer(_firstPeer);
            await showPeer(_secondPeer);
          } else {
            await backfill();
            await showPeer(_newcomer);
          }
          await enforceOwnerScope(session);
          final enforcedDb = openDisposablePgDatabase(target);
          addTearDown(enforcedDb.close);

          final snapshot = await readField(
            database: enforcedDb,
          ).timeout(ownerGraphWriteLimit);
          if (initialRead) {
            expectBackfillPeer(snapshot, _firstPeer);
            expectBackfillPeer(snapshot, _secondPeer);
            final rows = await waitForFirstSeen(_backfillRows.keys.toSet());
            expect(
              rows.map((id, row) => MapEntry(id, row.value)),
              _backfillRows,
            );
          } else {
            expectNewcomer(snapshot);
            final rows = await waitForFirstSeen({_newcomer});
            expect(rows[_newcomer]?.finiteAt, isNotNull);
            expect(rows[_firstPeer]?.value, '-infinity');
            expect(rows[_secondPeer]?.value, '-infinity');
          }
        },
      );
    }
  });
}
