@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_field_requests_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';

import '../../support/disposable_pg_target.dart';

/// #671: the targeted Request read of an open field returns, of the ids it
/// is given, only published, discoverable Requests (not Posts) of an allowed
/// status that are not the viewer's own, with no block either way, and that
/// the readability function lets the viewer read. Readability is stubbed here
/// (`description = 'denied'` is unreadable) so the test needs no MeritRank.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_FIELD_REQUESTS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_cfreqs',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const viewer = 'Ucfrqviewer01';
  const author = 'Ucfrqauthor01';
  const blocker = 'Ucfrqblocker1';

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb db;
  late ConstellationFieldRequestsRepository repository;

  Future<void> insertBeacon(
    String id, {
    String by = author,
    int kind = 0,
    int status = 0,
    bool discoverable = true,
    bool published = true,
    bool denied = false,
  }) => writer.execute('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, kind, is_discoverable,
  published_at, created_at, updated_at
) VALUES (
  '$id', '$by', 'title $id', '${denied ? 'denied' : 'desc'}', $status, $kind,
  $discoverable, ${published ? 'now()' : 'NULL'}, now(), now()
)
''');

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    db = openDisposablePgDatabase(target);
    repository = ConstellationFieldRequestsRepository(db);
    for (final id in [viewer, author, blocker]) {
      await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', now(), now())
''');
    }
    await writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$blocker', '$viewer', '$blocker')
''');
    await writer.execute(
      'ALTER FUNCTION public.beacon_readable_ids(text, text[]) '
      'RENAME TO beacon_readable_ids_unstubbed',
    );
    await writer.execute(r"""
CREATE FUNCTION public.beacon_readable_ids(p_viewer_id text, p_ids text[])
RETURNS SETOF text LANGUAGE sql STABLE AS $$
  SELECT b.id FROM public.beacon b
  WHERE b.id = ANY(p_ids) AND b.description <> 'denied'
$$
""");
    await insertBeacon('Bcfrq01');
    await insertBeacon('Bcfrq02', denied: true);
    await insertBeacon('Bcfrq03', discoverable: false);
    await insertBeacon('Bcfrq04', published: false);
    await insertBeacon('Bcfrq05', by: viewer);
    await insertBeacon('Bcfrq06', by: blocker);
    await insertBeacon('Bcfrq07', status: 1);
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: db);
  });

  test('returns only what a FULL read would list as discoverable and '
      'readable', () async {
    final rows = await repository.discoverableRequestsByIds(
      viewerId: viewer,
      beaconIds: {
        for (var i = 1; i <= 7; i++) 'Bcfrq0$i',
        'Bmissing',
      },
      filters: ConstellationFieldMembershipFilters.defaults,
    );

    expect(rows.map((r) => r.id), ['Bcfrq01']);
    expect(rows.single.authorId, author);
    expect(rows.single.title, 'title Bcfrq01');
    expect(rows.single.isMine, isFalse);
  });

  test('participatedOnly keeps a Request the viewer does not take part in '
      'off', () async {
    final rows = await repository.discoverableRequestsByIds(
      viewerId: viewer,
      beaconIds: {'Bcfrq01'},
      filters: const ConstellationFieldMembershipFilters(
        participatedOnly: true,
      ),
    );

    expect(rows, isEmpty);
  });

  test('no ids or no viewer reads nothing', () async {
    expect(
      await repository.discoverableRequestsByIds(
        viewerId: viewer,
        beaconIds: const {},
        filters: ConstellationFieldMembershipFilters.defaults,
      ),
      isEmpty,
    );
    expect(
      await repository.discoverableRequestsByIds(
        viewerId: '',
        beaconIds: {'Bcfrq01'},
        filters: ConstellationFieldMembershipFilters.defaults,
      ),
      isEmpty,
    );
  });
}
