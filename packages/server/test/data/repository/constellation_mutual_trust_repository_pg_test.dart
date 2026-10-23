@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_mutual_trust_repository.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';

import '../../support/disposable_pg_target.dart';

/// The selected person's explicit trust edges on the viewer's field follow
/// the field's own edge rules (`constellation_trust_edges`): only people the
/// viewer may see (or the viewer), no block either way with the viewer or
/// between the two ends, and only partners trusted both ways are asked for.
///
/// Visibility is stubbed (`person_visible_peers_symmetric` returns a fixed
/// list), so the test needs no MeritRank.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_MUTUAL_TRUST_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_cmtr',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const ctx = '';
  const viewer = 'Ucmtviewer001';
  const person = 'Ucmtperson001';
  // Trusts the person both ways and is visible.
  const mutual = 'Ucmtmutual001';
  // Trusts the person both ways but is outside the viewer's visible set.
  const hidden = 'Ucmthidden001';
  // Only the person trusts them / only they trust the person.
  const outOnly = 'Ucmtoutonly01';
  const inOnly = 'Ucmtinonly001';
  // Trusts the person both ways but blocked the viewer.
  const blocksViewer = 'Ucmtblockv001';
  // Trusts the person both ways but the two block each other.
  const blocksPerson = 'Ucmtblockp001';
  // Visible, not the selected person: nothing of theirs is asked for.
  const other = 'Ucmtother0001';
  const visible = [
    person,
    mutual,
    outOnly,
    inOnly,
    blocksViewer,
    blocksPerson,
    other,
  ];

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb db;
  late ConstellationMutualTrustRepository repository;

  Future<Set<(String, String)>> edgesOf(String personId) async {
    final edges = await repository.explicitTrustEdgesOf(
      viewerId: viewer,
      context: ctx,
      personId: personId,
    );
    expect(edges.every((e) => e.tier == 1), isTrue);
    return {for (final ConstellationEdgeRecord e in edges) (e.src, e.dst)};
  }

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    db = openDisposablePgDatabase(target);
    repository = ConstellationMutualTrustRepository(db);

    final everyone = [viewer, hidden, ...visible];
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
SELECT id, id, 'pk-' || id, now(), now()
FROM unnest(ARRAY[${everyone.map((id) => "'$id'").join(',')}]) AS id
''');
    final votes = [
      (person, viewer),
      (viewer, person),
      (person, mutual),
      (mutual, person),
      (person, hidden),
      (hidden, person),
      (person, outOnly),
      (inOnly, person),
      (person, blocksViewer),
      (blocksViewer, person),
      (person, blocksPerson),
      (blocksPerson, person),
      (mutual, other),
      (other, mutual),
    ];
    await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ${votes.map((v) => "('${v.$1}', '${v.$2}', 1, now(), now())").join(',')}
''');
    await writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$blocksViewer', '$viewer', '$blocksViewer'),
       ('$blocksPerson', '$person', '$blocksPerson')
''');

    await writer.execute(
      'CREATE TABLE public._cmt_visible (peer_id text PRIMARY KEY)',
    );
    await writer.execute('''
INSERT INTO public._cmt_visible
SELECT unnest(ARRAY[${visible.map((id) => "'$id'").join(',')}])
''');
    await writer.execute('''
ALTER FUNCTION public.person_visible_peers_symmetric(text, text)
  RENAME TO _cmt_symmetric_impl
''');
    await writer.execute(r'''
CREATE FUNCTION public.person_visible_peers_symmetric(viewer_id text, ctx text)
RETURNS TABLE(peer_id text) LANGUAGE sql STABLE AS $$
  SELECT v.peer_id FROM public._cmt_visible v
$$
''');
  });

  setUp(() => writer.execute('DELETE FROM public.person_visible_set_cache'));

  tearDownAll(() => tearDownDisposablePgWriter(session: session, drift: db));

  test('returns the edges both ways with visible, unblocked partners and the '
      'viewer', () async {
    expect(await edgesOf(person), {
      (person, viewer),
      (viewer, person),
      (person, mutual),
      (mutual, person),
    });
  });

  test('a person outside the visible set has no edges', () async {
    expect(await edgesOf(hidden), isEmpty);
  });

  test('a blank viewer or person reads nothing', () async {
    expect(
      await repository.explicitTrustEdgesOf(
        viewerId: ' ',
        context: ctx,
        personId: person,
      ),
      isEmpty,
    );
    expect(await edgesOf(''), isEmpty);
  });
}
