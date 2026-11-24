import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/owner_graph_transaction_port.dart';
import 'package:tentura_server/domain/port/phantom_repository_port.dart';

import '../database/tentura_db.dart';
import 'owner_graph_unit_of_work.dart';

@LazySingleton(as: PhantomRepositoryPort)
final class PhantomRepository implements PhantomRepositoryPort {
  const PhantomRepository(this._database);

  final TenturaDb _database;

  @override
  Future<int> countActive(OwnerGraphScope scope, String ownerId) async {
    requireOwnerGraphScope(_database, scope, ownerId);
    final row = await _database
        .customSelect(
          r'''
SELECT count(*)::int AS total
FROM public.phantom WHERE owner_id = $1 AND merged_at IS NULL
''',
          variables: [Variable.withString(ownerId)],
        )
        .getSingle();
    return row.read<int>('total');
  }

  @override
  Future<void> insert(
    OwnerGraphScope scope, {
    required String ownerId,
    required String id,
    required String name,
    required String? emoji,
  }) async {
    requireOwnerGraphScope(_database, scope, ownerId);
    await _database.customStatement(
      r'''
INSERT INTO public.phantom (id, owner_id, display_name, emoji)
VALUES ($1, $2, $3, $4)
''',
      [id, ownerId, name, emoji],
    );
    await _database.customStatement(
      r'''
INSERT INTO public.person_field_first_seen_init (viewer_id, backfill_pending)
VALUES ($1, true) ON CONFLICT (viewer_id) DO NOTHING
''',
      [ownerId],
    );
  }

  @override
  Future<bool> update(
    OwnerGraphScope scope, {
    required String ownerId,
    required String id,
    required String name,
    required String? emoji,
  }) async {
    requireOwnerGraphScope(_database, scope, ownerId);
    final rows = await _database.customWriteReturning(
      r'''
WITH owned AS (
  SELECT id FROM public.phantom WHERE id = $1 AND owner_id = $2 FOR UPDATE
), changed AS (
  UPDATE public.phantom
  SET display_name = $3, emoji = $4, updated_at = now(), revision = revision + 1
  WHERE id IN (SELECT id FROM owned)
    AND (display_name, emoji) IS DISTINCT FROM ($3, $4)
  RETURNING id
), renamed_invites AS (
  UPDATE public.invitation
  SET addressee_name = $3
  WHERE user_id = $2 AND phantom_id IN (SELECT id FROM changed)
    AND addressee_name IS DISTINCT FROM $3
)
SELECT id FROM owned
''',
      variables: [
        Variable.withString(id),
        Variable.withString(ownerId),
        Variable.withString(name),
        Variable<String>(emoji),
      ],
    );
    return rows.isNotEmpty;
  }

  @override
  Future<bool> delete(
    OwnerGraphScope scope, {
    required String ownerId,
    required String id,
  }) async {
    requireOwnerGraphScope(_database, scope, ownerId);
    final count = await _database.customUpdate(
      r'DELETE FROM public.phantom WHERE id = $1 AND owner_id = $2',
      variables: [Variable.withString(id), Variable.withString(ownerId)],
    );
    return count != 0;
  }
}
