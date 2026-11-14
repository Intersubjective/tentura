import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/saved_fact_repository_port.dart';

import '../database/tentura_db.dart';

@LazySingleton(as: SavedFactRepositoryPort)
class SavedFactRepository implements SavedFactRepositoryPort {
  const SavedFactRepository(this._db);

  final TenturaDb _db;

  /// One transaction under a per-user advisory lock, so two concurrent saves
  /// cannot both pass the cap count.
  @override
  Future<bool> save({
    required String userId,
    required String factCardId,
    required int cap,
  }) => _db.withMutatingUser(userId, () async {
    await _db.customStatement(
      r"SELECT pg_advisory_xact_lock(hashtext('user_saved_fact:' || $1))",
      [userId],
    );
    final row = await _db
        .customSelect(
          r'''
WITH ins AS (
  INSERT INTO public.user_saved_fact (user_id, fact_card_id)
  SELECT $1::text, $2::text
  WHERE (
    SELECT count(*) FROM public.user_saved_fact WHERE user_id = $1::text
  ) < $3::integer
  ON CONFLICT (user_id, fact_card_id) DO NOTHING
  RETURNING 1
)
SELECT EXISTS (SELECT 1 FROM ins) OR EXISTS (
  SELECT 1 FROM public.user_saved_fact
  WHERE user_id = $1::text AND fact_card_id = $2::text
) AS saved
''',
          variables: [
            Variable<String>(userId),
            Variable<String>(factCardId),
            Variable<int>(cap),
          ],
        )
        .getSingle();
    return row.read<bool>('saved');
  });

  @override
  Future<void> unsave({
    required String userId,
    required String factCardId,
  }) async {
    await (_db.delete(_db.userSavedFacts)..where(
          (t) => t.userId.equals(userId) & t.factCardId.equals(factCardId),
        ))
        .go();
  }
}
