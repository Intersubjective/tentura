import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/meritrank_repository.dart';

/// G3a integration setUp teardown SQL exercised by pg acceptance (tentura-6koo).
const forwardBandG3aAlice = 'Ucapg3alice1';
const forwardBandG3aBob = 'Ucapg3bob001';
const forwardBandG3aCarol = 'Ucapg3carol1';
const forwardBandG3aEve = 'Ucapg3eve001';
const forwardBandG3aBeaconId = 'Bcapg3bcn001';

const forwardBandG3aAllIds = [
  forwardBandG3aAlice,
  forwardBandG3aBob,
  forwardBandG3aCarol,
  forwardBandG3aEve,
];

Future<void> forwardBandWitnessG3aIntegrationCleanup(
  TenturaDb db,
  MeritrankRepository meritRank,
) async {
  for (final ego in [forwardBandG3aAlice, forwardBandG3aEve]) {
    for (final peer in [
      forwardBandG3aBob,
      forwardBandG3aCarol,
      forwardBandG3aAlice,
      forwardBandG3aEve,
    ]) {
      if (ego == peer) continue;
      await _clearMrEdge(db, ego, peer);
      await _clearMrEdge(db, peer, ego);
    }
  }
  await _clearMrEdge(db, forwardBandG3aAlice, forwardBandG3aBob);
  await _clearMrEdge(db, forwardBandG3aBob, forwardBandG3aAlice);

  final idList = forwardBandG3aAllIds.map((id) => "'$id'").join(', ');
  await db.customStatement(
    'DELETE FROM public.capability_routing_mute WHERE user_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.ego_witness_window '
    'WHERE ego_user_id IN ($idList) OR witness_user_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.person_capability_event '
    'WHERE observer_user_id IN ($idList) OR subject_user_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.capability_evidence_edge '
    'WHERE observer_user_id IN ($idList) OR subject_user_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.capability_evidence_generation '
    'WHERE observer_user_id IN ($idList) OR subject_user_id IN ($idList)',
  );
  await db.customStatement(
    "DELETE FROM public.beacon WHERE id = '$forwardBandG3aBeaconId'",
  );
  await db.customStatement(
    'DELETE FROM public.vote_user '
    'WHERE subject IN ($idList) OR object IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public."user" WHERE id IN ($idList)',
  );
}

Future<void> forwardBandG3aInsertUser(TenturaDb db, String id) =>
    db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');

Future<void> forwardBandG3aSeedTrustGraph(
  TenturaDb db,
  MeritrankRepository meritRank,
) async {
  await _trustBothWays(db, forwardBandG3aAlice, forwardBandG3aCarol);
  await _trustBothWays(db, forwardBandG3aEve, forwardBandG3aCarol);
  await meritRank.putEdge(
    nodeA: forwardBandG3aAlice,
    nodeB: forwardBandG3aCarol,
    weight: 0.7,
  );
  await meritRank.putEdge(
    nodeA: forwardBandG3aCarol,
    nodeB: forwardBandG3aAlice,
    weight: 0.65,
  );
  await meritRank.putEdge(
    nodeA: forwardBandG3aEve,
    nodeB: forwardBandG3aCarol,
    weight: 0.7,
  );
  await meritRank.putEdge(
    nodeA: forwardBandG3aCarol,
    nodeB: forwardBandG3aEve,
    weight: 0.65,
  );
  await _trustEdge(db, forwardBandG3aAlice, forwardBandG3aBob);
  await meritRank.putEdge(
    nodeA: forwardBandG3aAlice,
    nodeB: forwardBandG3aBob,
    weight: 0.85,
  );
}

/// Rows left over from a prior case — same shape integration setUp clears first.
Future<void> forwardBandG3aInsertBeaconRow(TenturaDb db) => db.customStatement('''
INSERT INTO public.beacon (
  id, user_id, title, description, needs, primary_need_slug, status
) VALUES (
  '$forwardBandG3aBeaconId',
  '$forwardBandG3aBob',
  'G3a witness admission beacon',
  'd',
  'transport',
  'transport',
  ${BeaconStatus.reviewOpen.smallintValue}
)
ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status
''');

Future<void> forwardBandG3aSeedPopulatedPreCleanupFixture(
  TenturaDb db,
  MeritrankRepository meritRank,
) async {
  for (final id in forwardBandG3aAllIds) {
    await forwardBandG3aInsertUser(db, id);
  }
  await forwardBandG3aSeedTrustGraph(db, meritRank);
  await forwardBandG3aInsertBeaconRow(db);
}

Future<int> forwardBandG3aFixtureUserCount(TenturaDb db) async {
  final idList = forwardBandG3aAllIds.map((id) => "'$id'").join(', ');
  final row = await db.customSelect(
    'SELECT count(*)::int AS c FROM public."user" WHERE id IN ($idList)',
  ).getSingle();
  return row.read<int>('c');
}

Future<int> forwardBandG3aFixtureBeaconCount(TenturaDb db) async {
  final row = await db.customSelect(
    "SELECT count(*)::int AS c FROM public.beacon WHERE id = '$forwardBandG3aBeaconId'",
  ).getSingle();
  return row.read<int>('c');
}

Future<void> _trustBothWays(TenturaDb db, String a, String b) async {
  await _trustEdge(db, a, b);
  await _trustEdge(db, b, a);
}

Future<void> _trustEdge(TenturaDb db, String subject, String object) =>
    db.customStatement('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$subject', '$object', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');

Future<void> _clearMrEdge(
  TenturaDb db,
  String subject,
  String object,
) =>
    db.customStatement(
      "SELECT mr_put_edge('$subject', '$object', 0::double precision, ''::text, 0)",
    );
