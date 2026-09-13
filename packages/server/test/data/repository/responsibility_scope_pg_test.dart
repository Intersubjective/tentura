@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_RESPONSIBILITY_SCOPE_TEST_DB',
    defaultNamePrefix: 'tentura_test_resp_scope',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('responsibility_scope_base_beacons', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE TABLE
  public.beacon_help_offer,
  public.beacon_forward_edge,
  public.beacon_archived,
  public.beacon,
  public."user"
CASCADE
''');
      for (final id in [_viewerId, _authorId]) {
        await writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('authored open beacon is in scope', () async {
      await _insertBeacon(writer, id: 'Brespopen', authorId: _viewerId);
      expect(await _scopeIds(writer, _viewerId), {'Brespopen'});
    });

    test('authored archived beacon is in scope', () async {
      await _insertBeacon(writer, id: 'Bresparch', authorId: _viewerId);
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_archived (user_id, beacon_id, archived_at)
VALUES (@userId, @beaconId, now())
'''),
        parameters: {'userId': _viewerId, 'beaconId': 'Bresparch'},
      );
      expect(await _scopeIds(writer, _viewerId), {'Bresparch'});
    });

    test('authored deleted beacon is out of scope', () async {
      await _insertBeacon(
        writer,
        id: 'Brespdel',
        authorId: _viewerId,
        status: 2,
      );
      expect(await _scopeIds(writer, _viewerId), isEmpty);
    });

    test('active help offer is in scope', () async {
      await _insertBeacon(writer, id: 'Bresphelp', authorId: _authorId);
      await _insertHelpOffer(
        writer,
        beaconId: 'Bresphelp',
        userId: _viewerId,
        status: 0,
      );
      expect(await _scopeIds(writer, _viewerId), {'Bresphelp'});
    });

    test('withdrawn help offer is out of scope', () async {
      await _insertBeacon(writer, id: 'Brespwith', authorId: _authorId);
      await _insertHelpOffer(
        writer,
        beaconId: 'Brespwith',
        userId: _viewerId,
        status: 1,
      );
      expect(await _scopeIds(writer, _viewerId), isEmpty);
    });

    test('help offer on deleted beacon is out of scope', () async {
      await _insertBeacon(
        writer,
        id: 'Brespdelho',
        authorId: _authorId,
        status: 2,
      );
      await _insertHelpOffer(
        writer,
        beaconId: 'Brespdelho',
        userId: _viewerId,
        status: 0,
      );
      expect(await _scopeIds(writer, _viewerId), isEmpty);
    });

    test('forward-only recipient is out of scope', () async {
      await _insertBeacon(writer, id: 'Brespfwd', authorId: _authorId);
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at, cancelled_at
) VALUES (
  'FEresp01', @beaconId, @authorId, @viewerId, now(), NULL
)
'''),
        parameters: {
          'beaconId': 'Brespfwd',
          'authorId': _authorId,
          'viewerId': _viewerId,
        },
      );
      expect(await _scopeIds(writer, _viewerId), isEmpty);
    });

    test('authored and help-offered on same beacon yields one row', () async {
      await _insertBeacon(writer, id: 'Brespboth', authorId: _viewerId);
      await _insertHelpOffer(
        writer,
        beaconId: 'Brespboth',
        userId: _viewerId,
        status: 0,
      );
      final rows = await writer.execute(
        Sql.named('''
SELECT beacon_id
FROM public.responsibility_scope_base_beacons(@viewerId)
WHERE beacon_id = @beaconId
'''),
        parameters: {'viewerId': _viewerId, 'beaconId': 'Brespboth'},
      );
      expect(rows.length, 1);
      expect(await _scopeIds(writer, _viewerId), {'Brespboth'});
    });
  }, skip: skipReason);
}

const _viewerId = 'Urespviewer';
const _authorId = 'Urespauthor';

Future<void> _insertBeacon(
  Connection writer, {
  required String id,
  required String authorId,
  int status = 0,
}) =>
    writer.execute(
      Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @authorId, @title, @description, @status)
'''),
      parameters: {
        'id': id,
        'authorId': authorId,
        'title': 'title-$id',
        'description': 'desc',
        'status': status,
      },
    );

Future<void> _insertHelpOffer(
  Connection writer, {
  required String beaconId,
  required String userId,
  required int status,
}) =>
    writer.execute(
      Sql.named('''
INSERT INTO public.beacon_help_offer (
  beacon_id, user_id, message, status, created_at, updated_at
) VALUES (
  @beaconId, @userId, 'offer', @status, now(), now()
)
'''),
      parameters: {
        'beaconId': beaconId,
        'userId': userId,
        'status': status,
      },
    );

Future<Set<String>> _scopeIds(Connection writer, String accountId) async {
  final result = await writer.execute(
    Sql.named('''
SELECT beacon_id
FROM public.responsibility_scope_base_beacons(@accountId)
'''),
    parameters: {'accountId': accountId},
  );
  return result.map((row) => row[0]! as String).toSet();
}
