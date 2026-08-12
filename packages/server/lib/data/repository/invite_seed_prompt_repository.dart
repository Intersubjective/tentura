import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/port/invite_seed_prompt_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: InviteSeedPromptPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class InviteSeedPromptRepository implements InviteSeedPromptPort {
  const InviteSeedPromptRepository(this._database);

  final TenturaDb _database;

  static const _pending = 0;
  static const _answered = 1;
  static const _skipped = 2;

  @override
  Future<PromptState?> stateFor({
    required String inviterId,
    required String inviteeId,
  }) async {
    final row = await (_database.select(_database.inviteSeedPromptStates)
          ..where((t) => t.inviteeUserId.equals(inviteeId)))
        .getSingleOrNull();
    if (row == null || row.inviterUserId != inviterId) {
      return null;
    }
    return PromptState(
      inviterUserId: row.inviterUserId,
      inviteeUserId: row.inviteeUserId,
      state: _toValue(row.state),
    );
  }

  @override
  Future<void> insertPending({
    required String inviterId,
    required String inviteeId,
  }) async {
    await _database
        .into(_database.inviteSeedPromptStates)
        .insert(
          InviteSeedPromptStatesCompanion.insert(
            inviterUserId: inviterId,
            inviteeUserId: inviteeId,
            state: const Value(_pending),
          ),
          onConflict: DoNothing(
            target: [_database.inviteSeedPromptStates.inviteeUserId],
          ),
        );
  }

  @override
  Future<void> markAnswered({
    required String inviterId,
    required String inviteeId,
  }) async {
    final updated = await (_database.update(_database.inviteSeedPromptStates)
          ..where(
            (t) =>
                t.inviteeUserId.equals(inviteeId) &
                t.inviterUserId.equals(inviterId),
          ))
        .write(
          InviteSeedPromptStatesCompanion(
            state: const Value(_answered),
            updatedAt: Value(PgDateTime(DateTime.timestamp())),
          ),
        );
    if (updated == 0) {
      throw StateError(
        'invite_seed_prompt_state row missing for inviter=$inviterId '
        'invitee=$inviteeId',
      );
    }
  }

  @override
  Future<void> markSkipped({
    required String inviterId,
    required String inviteeId,
  }) async {
    final updated = await (_database.update(_database.inviteSeedPromptStates)
          ..where(
            (t) =>
                t.inviteeUserId.equals(inviteeId) &
                t.inviterUserId.equals(inviterId),
          ))
        .write(
          InviteSeedPromptStatesCompanion(
            state: const Value(_skipped),
            updatedAt: Value(PgDateTime(DateTime.timestamp())),
          ),
        );
    if (updated == 0) {
      throw StateError(
        'invite_seed_prompt_state row missing for inviter=$inviterId '
        'invitee=$inviteeId',
      );
    }
  }

  PromptStateValue _toValue(int state) => switch (state) {
    _pending => PromptStateValue.pending,
    _answered => PromptStateValue.answered,
    _skipped => PromptStateValue.skipped,
    _ => throw StateError('Unknown invite_seed_prompt_state: $state'),
  };
}
