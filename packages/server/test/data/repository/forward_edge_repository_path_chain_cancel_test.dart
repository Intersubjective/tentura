@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

/// Postgres integration — recursive CTE path chain and cancel on forward edges.
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  final skipReason =
      postgresReachable ? false : 'local Postgres not reachable';

  late TenturaDb db;
  late ForwardEdgeRepository repo;

  if (skipReason == false) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());
      repo = ForwardEdgeRepository(db);
    });

    tearDownAll(() async {
      await db.close();
    });

    tearDown(() async {
      await db.customStatement(
        "DELETE FROM public.beacon_forward_edge WHERE beacon_id = 'Bfwdchain01'",
      );
      await db.customStatement(
        "DELETE FROM public.beacon WHERE id = 'Bfwdchain01'",
      );
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id LIKE 'Ufwdchain%' ''',
      );
    });
  }

  const beaconId = 'Bfwdchain01';
  const authorId = 'Ufwdchainauth';
  const hopId = 'Ufwdchainhop1';
  const helpOffererId = 'Ufwdchainhelp';
  const edgeAuthorToHop = 'Ffwdchain0001';
  const edgeHopToHelp = 'Ffwdchain0002';
  const edgeAuthorDirect = 'Ffwdchain0003';

  Future<void> seedFixture() async {
    final keyA = pgTestPublicKey('fwdchain', 1);
    final keyB = pgTestPublicKey('fwdchain', 2);
    final keyC = pgTestPublicKey('fwdchain', 3);
    final keyD = pgTestPublicKey('fwdchain', 4);
    await db.customStatement(
      r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES
  ($1, 'Author', $2, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ($3, 'Hop', $4, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ($5, 'Help offerer', $6, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ufwdchainstrn', 'Stranger', $7, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  public_key = EXCLUDED.public_key
''',
      [
        authorId,
        keyA,
        hopId,
        keyB,
        helpOffererId,
        keyC,
        keyD,
      ],
    );
    await db.customStatement(
      '''
INSERT INTO public.beacon (id, user_id, title, description, created_at, updated_at)
VALUES ('$beaconId', '$authorId', 'Forward path chain test', '', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
    );
    await db.customStatement(
      '''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, parent_edge_id, created_at
) VALUES
  ('$edgeAuthorToHop', '$beaconId', '$authorId', '$hopId', NULL,
   '2026-01-01T00:00:01Z'),
  ('$edgeHopToHelp', '$beaconId', '$hopId', '$helpOffererId', '$edgeAuthorToHop',
   '2026-01-01T00:00:02Z'),
  ('$edgeAuthorDirect', '$beaconId', '$authorId', '$helpOffererId', NULL,
   '2026-01-01T00:00:03Z')
ON CONFLICT (id) DO NOTHING
''',
    );
  }

  Future<bool> isCancelled(String edgeId) async {
    final row = await db.customSelect(
      r'''
SELECT cancelled_at IS NOT NULL AS cancelled
FROM public.beacon_forward_edge
WHERE id = $1
''',
      variables: [Variable.withString(edgeId)],
    ).getSingle();
    return row.read<bool>('cancelled');
  }

  group('fetchHelpOffererPathChain', () {
    test(
      'viewer = author returns help-offerer ancestor closure (multi-route)',
      () async {
        await seedFixture();
        final chain = await repo.fetchHelpOffererPathChain(
          beaconId: beaconId,
          helpOffererId: helpOffererId,
          viewerId: authorId,
        );
        expect(chain.map((e) => e.id).toList(), [
          edgeAuthorToHop,
          edgeHopToHelp,
          edgeAuthorDirect,
        ]);
        final byId = {for (final e in chain) e.id: e};
        expect(byId[edgeHopToHelp]!.parentEdgeId, edgeAuthorToHop);
        expect(byId[edgeAuthorDirect]!.parentEdgeId, isNull);
      },
      skip: skipReason,
    );

    test(
      'viewer = involved hop includes viewer edges and ancestors',
      () async {
        await seedFixture();
        final chain = await repo.fetchHelpOffererPathChain(
          beaconId: beaconId,
          helpOffererId: helpOffererId,
          viewerId: hopId,
        );
        expect(chain.map((e) => e.id).toSet(), {
          edgeAuthorToHop,
          edgeHopToHelp,
          edgeAuthorDirect,
        });
      },
      skip: skipReason,
    );

    test(
      'viewer = help offerer matches recipient seed and walks parents',
      () async {
        await seedFixture();
        final chain = await repo.fetchHelpOffererPathChain(
          beaconId: beaconId,
          helpOffererId: helpOffererId,
          viewerId: helpOffererId,
        );
        expect(chain.map((e) => e.id).toList(), [
          edgeAuthorToHop,
          edgeHopToHelp,
          edgeAuthorDirect,
        ]);
      },
      skip: skipReason,
    );

    test(
      'stranger viewer still receives help-offerer closure (auth is use-case layer)',
      () async {
        await seedFixture();
        final chain = await repo.fetchHelpOffererPathChain(
          beaconId: beaconId,
          helpOffererId: helpOffererId,
          viewerId: 'Ufwdchainstrn',
        );
        expect(chain.map((e) => e.id).toList(), [
          edgeAuthorToHop,
          edgeHopToHelp,
          edgeAuthorDirect,
        ]);
      },
      skip: skipReason,
    );

    test(
      'returns empty when help offerer has no inbound edges and viewer is uninvolved',
      () async {
        await seedFixture();
        await db.customStatement(
          '''
DELETE FROM public.beacon_forward_edge
WHERE id IN ('$edgeHopToHelp', '$edgeAuthorDirect')
''',
        );
        final chain = await repo.fetchHelpOffererPathChain(
          beaconId: beaconId,
          helpOffererId: helpOffererId,
          viewerId: 'Ufwdchainstrn',
        );
        expect(chain, isEmpty);
      },
      skip: skipReason,
    );

    test(
      'cancelled edges are excluded from recursive CTE',
      () async {
        await seedFixture();
        await repo.cancel(edgeHopToHelp, hopId);
        expect(await isCancelled(edgeHopToHelp), isTrue);

        final chain = await repo.fetchHelpOffererPathChain(
          beaconId: beaconId,
          helpOffererId: helpOffererId,
          viewerId: helpOffererId,
        );
        expect(chain.map((e) => e.id).toList(), [edgeAuthorDirect]);
      },
      skip: skipReason,
    );
  });

  group('cancel', () {
    test(
      'sets cancelled_at for matching sender and hides edge from active queries',
      () async {
        await seedFixture();
        expect(await isCancelled(edgeHopToHelp), isFalse);

        await repo.cancel(edgeHopToHelp, hopId);

        expect(await isCancelled(edgeHopToHelp), isTrue);
        expect(
          await repo.findActiveEdge(
            beaconId: beaconId,
            senderId: hopId,
            recipientId: helpOffererId,
          ),
          isNull,
        );
        final active = await repo.fetchByBeaconId(beaconId);
        expect(active.map((e) => e.id), containsAll([edgeAuthorToHop, edgeAuthorDirect]));
        expect(active.map((e) => e.id), isNot(contains(edgeHopToHelp)));
      },
      skip: skipReason,
    );

    test(
      'wrong sender leaves edge active',
      () async {
        await seedFixture();
        await repo.cancel(edgeHopToHelp, authorId);

        expect(await isCancelled(edgeHopToHelp), isFalse);
        expect(
          await repo.findActiveEdge(
            beaconId: beaconId,
            senderId: hopId,
            recipientId: helpOffererId,
          ),
          isNotNull,
        );
      },
      skip: skipReason,
    );
  });
}

Env _testEnv() => Env(
      environment: Environment.test,
      pgHost: Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1',
      pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
      pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
      printEnv: false,
      isDebugModeOn: false,
    );

Future<bool> _canConnectPostgres() async {
  try {
    final db = TenturaDb(_testEnv());
    await db.customSelect('SELECT 1').getSingle();
    await db.close();
    return true;
  } on Object {
    return false;
  }
}
