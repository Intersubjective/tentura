import 'package:drift/drift.dart' show Variable;
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/capability/capability_consts.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/port/witness_window_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: WitnessWindowPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class WitnessWindowRepository implements WitnessWindowPort {
  const WitnessWindowRepository(this._database);

  final TenturaDb _database;

  @override
  Future<RawWindowFacts> rawWindowFacts({
    required String egoId,
    required String normalizedContext,
    required int topK,
  }) async {
    final peerRows = await _database
        .customSelect(
          r'''
SELECT peer_id, forward_mr, viewer_explicitly_trusts_subject
FROM public.person_visibility_peers($1, $2)
WHERE forward_mr > 0
ORDER BY forward_mr DESC, peer_id ASC
LIMIT $3
''',
          variables: [
            Variable<String>(egoId),
            Variable<String>(normalizedContext),
            Variable<int>(topK),
          ],
          readsFrom: {},
        )
        .get();

    final trustedRows = await _database
        .customSelect(
          r'''
SELECT forward_mr
FROM public.person_visibility_peers($1, $2)
WHERE viewer_explicitly_trusts_subject
  AND forward_mr > 0
''',
          variables: [
            Variable<String>(egoId),
            Variable<String>(normalizedContext),
          ],
          readsFrom: {},
        )
        .get();

    return RawWindowFacts(
      topPeers: [
        for (final row in peerRows)
          RawPeerFact(
            peerId: row.read<String>('peer_id'),
            forwardMr: row.read<double>('forward_mr'),
            explicitlyTrusted: row.read<bool>('viewer_explicitly_trusts_subject'),
          ),
      ],
      trustedScores: [
        for (final row in trustedRows)
          row.read<double>('forward_mr'),
      ],
    );
  }

  @override
  Future<void> storeWindow({
    required String egoId,
    required String normalizedContext,
    required List<WitnessWeight> weights,
  }) => _database.transaction(() async {
    final epoch = await _currentEpoch();

    await _database.customStatement(
      r'''
DELETE FROM public.ego_witness_window
WHERE ego_user_id = $1
  AND context = $2
''',
      [egoId, normalizedContext],
    );

    for (final weight in weights) {
      await _database.customStatement(
        r'''
INSERT INTO public.ego_witness_window (
  ego_user_id, context, witness_user_id, m, admitted, computed_at, mr_epoch
) VALUES ($1, $2, $3, $4, $5, now(), $6)
''',
        [
          egoId,
          normalizedContext,
          weight.witnessUserId,
          weight.m,
          weight.admitted,
          epoch.toInt(),
        ],
      );
    }
  });

  @override
  Future<List<WitnessWeight>> cachedWindow({
    required String egoId,
    required String normalizedContext,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT w.witness_user_id, w.m, w.admitted
FROM public.ego_witness_window w
INNER JOIN public.mr_publish_epoch e ON e.id = true
WHERE w.ego_user_id = $1
  AND w.context = $2
  AND w.mr_epoch = e.epoch
  AND w.computed_at > now() - make_interval(mins => $3::integer)
ORDER BY w.witness_user_id
''',
          variables: [
            Variable<String>(egoId),
            Variable<String>(normalizedContext),
            Variable<int>(kCapWindowTtlMinutes),
          ],
          readsFrom: {},
        )
        .get();

    return [
      for (final row in rows)
        WitnessWeight(
          witnessUserId: row.read<String>('witness_user_id'),
          m: row.read<double>('m'),
          admitted: row.read<bool>('admitted'),
        ),
    ];
  }

  @override
  Future<void> invalidateFor({required String userId}) => _database.customStatement(
    r'''
DELETE FROM public.ego_witness_window
WHERE ego_user_id = $1
   OR witness_user_id = $1
''',
    [userId],
  );

  @override
  Future<void> bumpMrEpoch() => _database.customStatement(
    r'''
UPDATE public.mr_publish_epoch
SET epoch = epoch + 1
WHERE id = true
''',
  );

  @override
  Future<int> gcStaleWindows() => _database.customUpdate(
    r'''
DELETE FROM public.ego_witness_window
WHERE computed_at < now() - make_interval(mins => $1::integer)
''',
    variables: [Variable<int>(kCapWindowTtlMinutes)],
    updateKind: UpdateKind.delete,
  );

  Future<BigInt> _currentEpoch() async {
    final row = await _database
        .customSelect(
          r'''
SELECT epoch
FROM public.mr_publish_epoch
WHERE id = true
''',
          readsFrom: {},
        )
        .getSingle();
    return row.read<BigInt>('epoch');
  }
}
