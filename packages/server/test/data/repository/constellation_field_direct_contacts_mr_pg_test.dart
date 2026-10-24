@Tags(['pg', 'mr'])
library;

import 'package:test/test.dart';

import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';

import '../../support/disposable_pg_target.dart';

/// #246 Q6 with MeritRank: the 400 peer cap ranks direct contacts ahead of
/// indirect peers (visible through MeritRank only, no explicit trust), so
/// every direct contact stays and indirect peers fill the rest.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_DIRECT_CONTACTS_MR_TEST_DB',
    defaultNamePrefix: 'tentura_test_dircontmr',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const viewer = 'Udcmviewer01';
  const indirectCount = kConstellationPeerCap + 20;
  const directCount = 40;
  final indirect = [
    for (var i = 0; i < indirectCount; i++)
      'Udcmind${i.toString().padLeft(4, '0')}',
  ];
  // Sorted after every indirect id, so an id-ordered cap would cut them off.
  final direct = [
    for (var i = 0; i < directCount; i++)
      'Udcmzdir${i.toString().padLeft(3, '0')}',
  ];

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late ConstellationFieldRepository repository;

  String sqlArray(Iterable<String> ids) =>
      'ARRAY[${ids.map((id) => "'$id'").join(',')}]::text[]';

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    db = openDisposablePgDatabase(target);
    repository = ConstellationFieldRepository(db, _PgProfileLookup(db));

    await db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key)
SELECT id, 'name-' || id, 'pk-' || id
FROM unnest(${sqlArray([viewer, ...indirect, ...direct])}) AS id
ON CONFLICT (id) DO NOTHING
''');
    await db.customStatement('''
INSERT INTO public.vote_user (subject, object, amount)
SELECT '$viewer', id, 1 FROM unnest(${sqlArray(direct)}) AS id
UNION ALL
SELECT id, '$viewer', 1 FROM unnest(${sqlArray(direct)}) AS id
ON CONFLICT (subject, object) DO NOTHING
''');
    // Indirect peers: MeritRank edges only, never explicit trust.
    await db.customStatement('''
SELECT mr_put_edge(e.src, e.dst, 0.75::double precision, ''::text, 0)
FROM (
  SELECT '$viewer' AS src, id AS dst FROM unnest(${sqlArray(indirect)}) AS id
  UNION ALL
  SELECT id, '$viewer' FROM unnest(${sqlArray(indirect)}) AS id
) e
''');
  });

  tearDownAll(() async {
    await db.customStatement('''
SELECT mr_delete_edge(e.src, e.dst)
FROM (
  SELECT '$viewer' AS src, id AS dst FROM unnest(${sqlArray(indirect)}) AS id
  UNION ALL
  SELECT id, '$viewer' FROM unnest(${sqlArray(indirect)}) AS id
) e
''');
    await tearDownDisposablePgWriter(session: session, drift: db);
  });

  test(
    'indirect peers stay capped and every direct contact is added',
    () async {
      final snapshot = await repository.readSnapshot(
        viewerId: viewer,
        context: '',
        params: (
          filters: ConstellationFieldMembershipFilters.defaults,
          projection: ConstellationProjection.full,
        ),
      );
      final peerIds = snapshot.peers.map((p) => p.id).toSet();

      expect(snapshot.peersCapped, isTrue);
      expect(snapshot.directContactIds, direct);
      expect(peerIds.containsAll(direct), isTrue);
      expect(
        peerIds.intersection(indirect.toSet()),
        hasLength(kConstellationPeerCap - directCount),
      );
      expect(peerIds, hasLength(kConstellationPeerCap));
      expect(snapshot.peers.where((p) => p.contactOnly), isEmpty);
    },
  );
}

/// Avoids GetIt-backed presence mapping in pg tests.
final class _PgProfileLookup implements UserProfileBatchLookup {
  _PgProfileLookup(this._database);

  final TenturaDb _database;

  @override
  Future<Map<String, ConstellationPeerRecord>> constellationProfilesByIds(
    Iterable<String> ids,
  ) async {
    final idList = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (idList.isEmpty) {
      return {};
    }
    final users = await _database.managers.users
        .filter((u) => u.id.isIn(idList))
        .get();
    return {
      for (final user in users)
        user.id: ConstellationPeerRecord(
          id: user.id,
          displayName: user.displayName,
        ),
    };
  }

  @override
  Future<Map<String, UserEntity>> userEntitiesByIds(
    Iterable<String> ids,
  ) async => const {};

  @override
  Future<Map<String, UserPublicRecord>> userPublicRecordsByIds({
    required Iterable<String> ids,
    required Set<String> reciprocalPeerIds,
    Set<String> trustsViewerPeerIds = const {},
    Set<String> viewerTrustsPeerIds = const {},
    Map<String, MutualScoreRecord> scoresByPeerId = const {},
  }) async => const {};
}
