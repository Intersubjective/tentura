import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/offer_accepted_dismissal_repository_port.dart';

import '../database/tentura_db.dart';

/// B077b — `offer_accepted_dismissal` (m0252).
@Singleton(as: OfferAcceptedDismissalRepositoryPort)
class OfferAcceptedDismissalRepository
    implements OfferAcceptedDismissalRepositoryPort {
  const OfferAcceptedDismissalRepository(this._db);

  final TenturaDb _db;

  @override
  Future<bool> dismiss({required String userId, required String beaconId}) =>
      _db.withMutatingUser(userId, () async {
        // Only someone with an offer on the Request has a sub-card to dismiss.
        await _db.customStatement(
          r'''
INSERT INTO public.offer_accepted_dismissal (user_id, beacon_id)
SELECT $1, $2
WHERE EXISTS (
  SELECT 1 FROM public.beacon_help_offer ho
  WHERE ho.user_id = $1 AND ho.beacon_id = $2
)
ON CONFLICT (user_id, beacon_id) DO NOTHING
''',
          [userId, beaconId],
        );
        final row = await _db
            .customSelect(
              r'''
SELECT 1 FROM public.offer_accepted_dismissal
WHERE user_id = $1 AND beacon_id = $2
''',
              variables: [Variable<String>(userId), Variable<String>(beaconId)],
            )
            .getSingleOrNull();
        return row != null;
      });

  @override
  Future<List<String>> dismissedBeaconIds({required String userId}) async {
    final rows = await _db
        .customSelect(
          r'''
SELECT beacon_id FROM public.offer_accepted_dismissal
WHERE user_id = $1
ORDER BY dismissed_at, beacon_id
''',
          variables: [Variable<String>(userId)],
        )
        .get();
    return [for (final r in rows) r.read<String>('beacon_id')];
  }
}
