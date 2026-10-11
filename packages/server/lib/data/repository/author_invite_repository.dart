import 'package:drift_postgres/drift_postgres.dart' show PgDateTime;
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/author_invite.dart';
import 'package:tentura_server/domain/port/author_invite_port.dart';

import '../database/tentura_db.dart';
import 'beacon_hierarchy_repository.dart';
import 'post_lock_repository.dart';

/// `beacon_author_invite` through raw SQL (no Drift table class, plan §0).
@Injectable(as: AuthorInvitePort)
class AuthorInviteRepository implements AuthorInvitePort {
  const AuthorInviteRepository(this._database);

  final TenturaDb _database;

  static const _columns =
      'id, beacon_id, inviter_id, invitee_id, source_post_id, '
      'forward_edge_id, arrival_post_edge_id, warm, note, status';

  @override
  Future<AuthorInvite?> fetchById(String inviteId) => _one(
    'SELECT $_columns FROM public.beacon_author_invite '
    r'WHERE id = $1',
    [inviteId],
  );

  @override
  Future<AuthorInvite?> lockById(String inviteId) => _one(
    'SELECT $_columns FROM public.beacon_author_invite '
    r'WHERE id = $1 FOR UPDATE',
    [inviteId],
  );

  @override
  Future<AuthorInvite?> fetchPending({
    required String beaconId,
    required String inviteeId,
  }) => _one(
    'SELECT $_columns FROM public.beacon_author_invite '
    r'WHERE beacon_id = $1 AND invitee_id = $2 AND status = 0',
    [beaconId, inviteeId],
  );

  @override
  Future<AuthorInvite?> lockPendingUnblocked({
    required String beaconId,
    required String inviteeId,
  }) => _one(
    'SELECT $_columns FROM public.beacon_author_invite '
    r'WHERE beacon_id = $1 AND invitee_id = $2 AND status = 0 '
    '  AND NOT public.block_hides(inviter_id, invitee_id) '
    'FOR UPDATE',
    [beaconId, inviteeId],
  );

  @override
  Future<List<PendingAuthorInvite>> listPendingForInvitee(
    String inviteeId,
  ) async {
    final rows = await _database
        .customSelect(
          'SELECT i.id, i.beacon_id, b.title, i.inviter_id, i.source_post_id, '
          '       i.note, i.created_at '
          'FROM public.beacon_author_invite i '
          'JOIN public.beacon b ON b.id = i.beacon_id '
          r'WHERE i.invitee_id = $1 AND i.status = 0 '
          '  AND NOT public.block_hides(i.inviter_id, i.invitee_id) '
          r'  AND public.beacon_can_read_content(i.beacon_id, $1) '
          'ORDER BY i.created_at DESC, i.id DESC',
          variables: [Variable.withString(inviteeId)],
        )
        .get();
    return [
      for (final r in rows)
        PendingAuthorInvite(
          inviteId: r.read<String>('id'),
          beaconId: r.read<String>('beacon_id'),
          beaconTitle: r.read<String>('title'),
          inviterId: r.read<String>('inviter_id'),
          sourcePostId: r.readNullable<String>('source_post_id'),
          note: r.readNullable<String>('note'),
          createdAt: _timestamp(r)!,
        ),
    ];
  }

  @override
  Future<List<AuthorInvite>> listForAuthor({
    required String beaconId,
    required String authorId,
  }) async {
    final rows = await _database
        .customSelect(
          'SELECT $_columns, created_at FROM public.beacon_author_invite '
          r'WHERE beacon_id = $1 '
          '  AND EXISTS (SELECT 1 FROM public.beacon b '
          r'             WHERE b.id = $1 AND b.user_id = $2) '
          'ORDER BY created_at, id',
          variables: [
            Variable.withString(beaconId),
            Variable.withString(authorId),
          ],
        )
        .get();
    return [for (final r in rows) _map(r)];
  }

  @override
  Future<void> lockScope(String? sourcePostId) async {
    if (sourcePostId != null) {
      await PostLockRepository(_database).lockForPostMutation(sourcePostId);
      return;
    }
    await BeaconHierarchyRepository(_database).lockMutationScope();
  }

  @override
  Future<AuthorInvite?> resolve({
    required String inviteId,
    required AuthorInviteStatus status,
    required String? resolvedBy,
  }) => _one(
    'UPDATE public.beacon_author_invite '
    r'SET status = $2, resolved_at = now(), resolved_by = $3 '
    r'WHERE id = $1 AND status = 0 '
    'RETURNING $_columns',
    [inviteId, status.code, resolvedBy],
  );

  @override
  Future<List<AuthorInvite>> withdrawPendingBetween(String a, String b) async {
    final rows = await _database
        .customSelect(
          'UPDATE public.beacon_author_invite '
          'SET status = ${AuthorInviteStatus.withdrawn.code}, '
          r'    resolved_at = now(), resolved_by = $1 '
          'WHERE status = 0 '
          r'  AND ((inviter_id = $1 AND invitee_id = $2) '
          r'    OR (inviter_id = $2 AND invitee_id = $1)) '
          'RETURNING $_columns',
          variables: [Variable.withString(a), Variable.withString(b)],
        )
        .get();
    return [for (final r in rows) _map(r)];
  }

  @override
  Future<void> markEdgeSweepExempt(String edgeId) => _database.customStatement(
    'UPDATE public.beacon_forward_edge SET contact_sweep_exempt = true '
    r'WHERE id = $1 AND NOT contact_sweep_exempt',
    [edgeId],
  );

  @override
  Future<bool> resolveContactWithoutEvidence(String edgeId) async {
    final row = await _database
        .customSelect(
          r'SELECT public.contact_resolve_without_evidence($1) AS resolved',
          variables: [Variable.withString(edgeId)],
        )
        .getSingle();
    return row.read<bool>('resolved');
  }

  Future<AuthorInvite?> _one(String sql, List<Object?> args) async {
    final row = await _database
        .customSelect(
          sql,
          variables: [
            for (final a in args)
              switch (a) {
                final int v => Variable.withInt(v),
                final String v => Variable.withString(v),
                _ => const Variable<String>(null),
              },
          ],
        )
        .getSingleOrNull();
    return row == null ? null : _map(row);
  }

  /// `created_at` when the query selected it.
  static DateTime? _timestamp(QueryRow r) => switch (r.data['created_at']) {
    final DateTime v => v,
    final PgDateTime v => v.dateTime,
    _ => null,
  };

  static AuthorInvite _map(QueryRow r) => AuthorInvite(
    id: r.read<String>('id'),
    beaconId: r.read<String>('beacon_id'),
    inviterId: r.read<String>('inviter_id'),
    inviteeId: r.read<String>('invitee_id'),
    sourcePostId: r.readNullable<String>('source_post_id'),
    forwardEdgeId: r.readNullable<String>('forward_edge_id'),
    arrivalPostEdgeId: r.readNullable<String>('arrival_post_edge_id'),
    warm: r.read<bool>('warm'),
    note: r.readNullable<String>('note'),
    status: AuthorInviteStatus.fromCode(r.read<int>('status')),
    createdAt: _timestamp(r),
  );
}
