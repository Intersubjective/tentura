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
  Future<String?> lockInvitesAndFindJoiningName(
    OwnerGraphScope scope, {
    required String ownerId,
    required String id,
  }) async {
    requireOwnerGraphScope(_database, scope, ownerId);
    final variables = [Variable.withString(id), Variable.withString(ownerId)];
    final invites = await _database.customSelect(
      r'''
SELECT i.id
FROM public.invitation i
JOIN public.phantom p ON p.id = i.phantom_id
WHERE p.id = $1 AND p.owner_id = $2
ORDER BY i.id
FOR UPDATE OF i
''',
      variables: variables,
    ).get();
    if (invites.isEmpty) return null;

    // Take a fresh snapshot after any wait on the accept transaction so we
    // can see the job that committed with the claim.
    final joining = await _database.customSelect(
      r'''
SELECT p.display_name
FROM public.phantom p
WHERE p.id = $1 AND p.owner_id = $2 AND EXISTS (
  SELECT 1 FROM public.invitation i
  JOIN public.phantom_merge_job j ON j.invitation_id = i.id
  WHERE i.phantom_id = p.id AND i.invited_id IS NOT NULL AND j.state = 'queued'
)
''',
      variables: variables,
    ).getSingleOrNull();
    return joining?.read<String>('display_name');
  }

  @override
  Future<String?> saveInvite(
    OwnerGraphScope scope, {
    required String ownerId,
    required String id,
    required bool rotate,
  }) async {
    requireOwnerGraphScope(_database, scope, ownerId);
    final person = await _database
        .customSelect(
          r'''
SELECT p.display_name, i.id AS invitation_id
FROM public.phantom p
LEFT JOIN public.invitation i
  ON i.phantom_id = p.id AND i.user_id = p.owner_id AND i.invited_id IS NULL
WHERE p.id = $1 AND p.owner_id = $2 AND p.merged_at IS NULL
''',
          variables: [Variable.withString(id), Variable.withString(ownerId)],
        )
        .getSingleOrNull();
    if (person == null) return null;

    final invitationId = person.readNullable<String>('invitation_id');
    if (rotate) {
      if (invitationId == null) return null;
      final deleted =
          await (_database.delete(_database.invitations)..where(
                (row) => row.id.equals(invitationId) & row.invitedId.isNull(),
              ))
              .go();
      if (deleted == 0) return null;
    } else if (invitationId != null) {
      return invitationId;
    }

    final invitation = await _database.managers.invitations.createReturning(
      (insert) => insert(
        userId: ownerId,
        phantomId: Value(id),
        addresseeName: Value(person.read<String>('display_name')),
      ),
    );
    return invitation.id;
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

  @override
  Future<bool> dismissLinkHint(
    OwnerGraphScope scope, {
    required String ownerId,
    required String phantomId,
    required String userId,
  }) async {
    requireOwnerGraphScope(_database, scope, ownerId);
    final rows = await _database.customWriteReturning(
      r'''
WITH owned AS (
  SELECT id FROM public.phantom WHERE id = $1 AND owner_id = $2
), dismissed AS (
  INSERT INTO public.phantom_link_hint_dismissal (phantom_id, user_id)
  SELECT owned.id, u.id FROM owned JOIN public."user" u ON u.id = $3
  ON CONFLICT (phantom_id, user_id) DO NOTHING
)
SELECT id FROM owned
''',
      variables: [
        Variable.withString(phantomId),
        Variable.withString(ownerId),
        Variable.withString(userId),
      ],
    );
    return rows.isNotEmpty;
  }
}
