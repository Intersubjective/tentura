import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart'
    show m0254;
import 'package:tentura_server/data/database/tentura_db.dart' show TenturaDb;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';

import 'constellation_anchor_batch_fixture.dart';
import 'disposable_pg_target.dart';
import 'pg_test_public_keys.dart';
import 'pg_wait.dart';

Future<List<Map<String, dynamic>>> readStoredConstellationAnchors(
  Session connection, {
  required String viewerId,
}) async {
  final result = await connection.execute(
    Sql.named('''
SELECT to_jsonb(a)::text FROM public.constellation_anchor a
WHERE viewer_id = @viewer ORDER BY id
'''),
    parameters: {'viewer': viewerId},
  );
  return [
    for (final row in result)
      jsonDecode(row.single! as String) as Map<String, dynamic>,
  ];
}

/// Tombstones store their identity separately from the nullable live-target FKs.
/// This is the storage contract expected from the additive tombstone migration.
void expectRetainedPinTombstone(
  Map<String, dynamic> tombstone,
  Map<String, dynamic> original,
  ConstellationAnchorTarget target,
) {
  for (final field in [
    'id',
    'viewer_id',
    'x_units',
    'y_units',
    'coordinate_space_version',
    'placed_at',
  ]) {
    expect(
      tombstone[field],
      original[field],
      reason: '$field survives target deletion',
    );
  }
  expect(tombstone, containsPair('beacon_id', null));
  expect(tombstone, containsPair('person_id', null));
  expect(tombstone, containsPair('target_id', target.id));
  expect(tombstone, containsPair('target_kind', target.kind.wireValue));
  expect(
    tombstone['tombstone_at'],
    isA<String>(),
    reason: 'A retained pin must be explicitly marked as a tombstone',
  );
  expect(DateTime.tryParse(tombstone['tombstone_at'] as String), isNotNull);
}

/// Real pin writes, target deletes, snapshot reads and LISTEN on one disposable
/// database. Notification barriers avoid guessing how long delivery takes.
final class ConstellationAnchorTombstoneFixture {
  ConstellationAnchorTombstoneFixture(this.target);

  static const viewer = 'Ucatombviewer';
  static const otherViewer = 'Ucatombviewer2';
  static const person = 'Ucatombperson';
  static const beacon = 'Bcatombrequest';
  static const position = ConstellationAnchorPosition(
    xUnits: -7.5,
    yUnits: 4.25,
    coordinateSpaceVersion: 1,
  );
  static const targets = <String, ConstellationAnchorTarget>{
    'Request': ConstellationAnchorBeaconTarget(beacon),
    'person': ConstellationAnchorPersonTarget(person),
  };

  final DisposablePgTarget target;
  late DisposablePgWriterSession _session;
  late TenturaDb db;
  late ConstellationAnchorRepository repository;
  late ConstellationFieldRepository _fields;
  Connection get writer => _session.writer;
  late Connection _listener;
  late StreamSubscription<String> _subscription;
  final _notifications = <Map<String, dynamic>>[];
  final _barriers = <String, Completer<void>>{};
  var _barrierId = 0;

  Future<void> open({String? throughVersion}) async {
    _session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
      lastInclusiveVersion: throughVersion,
    );
    if (throughVersion != null) {
      // Pins are seeded through today's repository, which reads the reset
      // watermark (m0254, #251); give the older schema that one column.
      await _session.writer.execute(
        m0254.statements.single,
      );
    }
    db = openDisposablePgDatabase(target);
    repository = constellationAnchorRepositoryFor(db);
    _fields = ConstellationFieldRepository(db, _PgTombstoneProfiles(db));
    _listener = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    _subscription = _listener.channels['entity_changes'].listen((payload) {
      final message = jsonDecode(payload) as Map<String, dynamic>;
      final barrier = message['_tombstone_test_barrier'];
      if (barrier is String) {
        _barriers[barrier]?.complete();
      } else {
        _notifications.add(message);
      }
    });
    await _listener.execute('LISTEN entity_changes');
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _listener.close();
    await tearDownDisposablePgWriter(session: _session, drift: db);
  }

  Future<void> reset({String beaconAuthorId = viewer}) async {
    await writer.execute('''
TRUNCATE public.constellation_anchor, public.constellation_anchor_cursor,
         public.constellation_anchor_target_watermark,
         public.constellation_anchor_op_log CASCADE
''');
    await writer.execute('DELETE FROM public.beacon');
    await writer.execute('DELETE FROM public."user"');
    for (final (index, id) in [viewer, otherViewer, person].indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @name, @key, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
'''),
        parameters: {
          'id': id,
          'name': 'Private profile $id',
          'key': pgTestPublicKey('catombstone', index + 1),
        },
      );
    }
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, created_at, updated_at, published_at)
VALUES (@id, @viewer, 'Private Request title', 'Private Request description', 0,
        '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
'''),
      parameters: {'id': beacon, 'viewer': beaconAuthorId},
    );
    await clearHints();
  }

  Future<ConstellationAnchor> pin(
    ConstellationAnchorTarget target, {
    String viewerId = viewer,
  }) async => (await repository.applyAnchorUpsert(
    viewerId: viewerId,
    context: kConstellationContext,
    target: target,
    position: position,
  )).anchor;

  Future<void> deleteTarget(
    ConstellationAnchorTarget target, {
    TxSession? transaction,
  }) async {
    final table = target.kind == ConstellationAnchorTargetKind.beacon
        ? 'public.beacon'
        : 'public."user"';
    await (transaction ?? writer).execute(
      Sql.named('DELETE FROM $table WHERE id = @id'),
      parameters: {'id': target.id},
    );
  }

  Future<List<Map<String, dynamic>>> rows({
    String viewerId = viewer,
    TxSession? transaction,
  }) async {
    final result = await (transaction ?? writer).execute(
      Sql.named('''
SELECT to_jsonb(a)::text FROM public.constellation_anchor a
WHERE viewer_id = @viewer ORDER BY id
'''),
      parameters: {'viewer': viewerId},
    );
    return [
      for (final row in result)
        jsonDecode(row.single! as String) as Map<String, dynamic>,
    ];
  }

  Future<BigInt> revision({
    String viewerId = viewer,
    TxSession? transaction,
  }) async {
    final result = await (transaction ?? writer).execute(
      Sql.named('''
SELECT revision::text FROM public.constellation_anchor_cursor
WHERE viewer_id = @viewer
'''),
      parameters: {'viewer': viewerId},
    );
    return result.isEmpty
        ? BigInt.zero
        : BigInt.parse(result.single.single! as String);
  }

  Future<ConstellationAnchorProjection> read(
    ConstellationProjection projection,
  ) async => (await _fields.readSnapshot(
    viewerId: viewer,
    context: kConstellationContext,
    params: (
      filters: ConstellationFieldMembershipFilters.defaults,
      projection: projection,
    ),
  )).anchorProjection;

  List<Map<String, dynamic>> hints([String viewerId = viewer]) => [
    for (final notification in _notifications)
      if (notification['entity'] == 'constellation_anchor' &&
          notification['id'] == viewerId)
        notification,
  ];

  Future<void> drainHints() async {
    final id = '${++_barrierId}';
    final arrived = Completer<void>();
    _barriers[id] = arrived;
    try {
      // Sent after the transaction: PG delivers earlier committed hints before
      // this sentinel on the same channel, including a transaction with none.
      await writer.execute(
        Sql.named("SELECT pg_notify('entity_changes', @payload)"),
        parameters: {
          'payload': jsonEncode({'_tombstone_test_barrier': id}),
        },
      );
      await arrived.future.timeout(kCompletionWait);
    } finally {
      _barriers.remove(id);
    }
  }

  Future<void> clearHints() async {
    await drainHints();
    _notifications.clear();
  }
}

final class _PgTombstoneProfiles implements UserProfileBatchLookup {
  _PgTombstoneProfiles(this.db);

  final TenturaDb db;

  @override
  Future<Map<String, ConstellationPeerRecord>> constellationProfilesByIds(
    Iterable<String> ids,
  ) async {
    final users = await db.managers.users
        .filter((user) => user.id.isIn(ids.toSet().toList()))
        .get();
    return {
      for (final user in users)
        user.id: ConstellationPeerRecord(
          id: user.id,
          displayName: user.displayName,
          handle: user.handle,
        ),
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected profile lookup: ${invocation.memberName}',
  );
}
