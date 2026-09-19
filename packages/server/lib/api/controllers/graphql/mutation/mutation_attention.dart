import 'package:tentura_server/domain/port/attention_ack_port.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/attention/attention_sweep_models.dart';
import 'package:tentura_server/domain/attention/attention_undo_models.dart';
import 'package:tentura_server/domain/use_case/attention_clear_case.dart';
import 'package:tentura_server/domain/use_case/attention_settlement_case.dart';
import 'package:tentura_server/domain/use_case/attention_sweep_case.dart';
import 'package:tentura_server/domain/use_case/obligation_reconciliation_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import '../query/query_attention.dart';

final class MutationAttention extends GqlNodeBase {
  MutationAttention({
    AttentionAckPort? ack,
    AttentionSettlementCase? settlement,
    AttentionClearCase? clear,
    AttentionSweepCase? sweep,
    ObligationReconciliationRunner? reconciliation,
  }) : _ack = ack ?? GetIt.I<AttentionAckPort>(),
       _settlementOverride = settlement,
       _clearOverride = clear,
       _sweepOverride = sweep,
       _reconciliationOverride = reconciliation;

  final AttentionAckPort _ack;
  final AttentionSettlementCase? _settlementOverride;
  final AttentionClearCase? _clearOverride;
  final AttentionSweepCase? _sweepOverride;
  final ObligationReconciliationRunner? _reconciliationOverride;

  ObligationReconciliationRunner get _reconciliation =>
      _reconciliationOverride ?? GetIt.I<ObligationReconciliationCase>();

  AttentionSweepCase get _sweep =>
      _sweepOverride ?? GetIt.I<AttentionSweepCase>();

  AttentionClearCase get _clear =>
      _clearOverride ?? GetIt.I<AttentionClearCase>();

  AttentionSettlementCase get _settlement =>
      _settlementOverride ?? GetIt.I<AttentionSettlementCase>();

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    attentionMarkSeen,
    attentionMarkAllSeen,
    attentionMarkSeenForBeacon,
    attentionMarkUnseen,
    attentionSettle,
    attentionClear,
    attentionDismissAll,
    attentionUndo,
    attentionReconcile,
  ];

  /// *Reset counters* — E21 / D15, as an API.
  ///
  /// Invalidation and repair, never erasure. It recomputes obligation state
  /// from the source of truth and returns the authoritative summary, which may
  /// legitimately be non-zero: the answer is what the account actually owes,
  /// not a promise of an empty desk.
  ///
  /// It takes **no arguments at all**, deliberately. The account is the `sub`
  /// of the caller's credentials, so there is no place to put a foreign
  /// account id — the request cannot express one, rather than being refused
  /// after the fact.
  GraphQLObjectField<dynamic, dynamic> get attentionReconcile =>
      GraphQLObjectField(
        'attentionReconcile',
        gqlTypeAttentionReconcileResult.nonNullable(),
        resolve: (_, args) async {
          final accountId = getCredentials(args).sub;
          final result = await _reconciliation.reconcileAccount(
            accountId: accountId,
          );
          return {
            'createdObligationCount': result.createdObligationCount,
            'settledObligationCount': result.settledObligationCount,
            'unrepairableObligationCount': result.unrepairableObligationCount,
            'summary': {
              'activityUnreadTotal': result.summary.activityUnreadTotal,
              'myWorkUnreadTotal': result.summary.myWorkUnreadTotal,
              'needsYouTotal': result.summary.needsYouTotal,
              'myDeskDot': result.summary.myDeskDot,
              'myDeskCount': result.summary.myDeskCount,
              'forYouDot': result.summary.forYouDot,
            },
          };
        },
      );

  /// *Dismiss all* — owner decision A, as an API.
  ///
  /// Takes no membership, deliberately: the surface is captured server-side,
  /// including the pages the caller has never loaded, because a sweep that
  /// only covered what was on screen would leave the dot on and the ritual
  /// meaningless. It clears only the rows that carry their own ×, never an
  /// obligation and never anything awaiting a decision — sweeping an
  /// unanswered forward would answer a person by not answering them.
  ///
  /// Resumable and idempotent by `operationId`. `maxBatches` bounds one call;
  /// the caller resumes by sending the same id again. The result says
  /// `partial` — not `complete` — whenever anything was refused or is still
  /// pending, and every refusal carries its reason.
  GraphQLObjectField<dynamic, dynamic> get attentionDismissAll =>
      GraphQLObjectField(
        'attentionDismissAll',
        gqlTypeAttentionDismissAllResult.nonNullable(),
        arguments: [_operationId.field, _maxBatches.fieldNullable],
        resolve: (_, args) async {
          final accountId = getCredentials(args).sub;
          final result = await _sweep.dismissAll(
            accountId: accountId,
            operationId: _operationId.fromArgsNonNullable(args),
            maxBatches: _maxBatches.fromArgs(args),
          );
          Map<String, dynamic> member(AttentionSweepMember member) => {
            'kind': member.kind.wireName,
            'id': member.id,
            'reason': member.reason?.wireName,
          };
          return {
            'operationId': result.operationId,
            'appliedReceiptIds': result.appliedReceiptIds,
            'appliedOutcomeBeaconIds': result.appliedOutcomeBeaconIds,
            'appliedCount': result.appliedCount,
            'skipped': [for (final each in result.skipped) member(each)],
            'failed': [for (final each in result.failed) member(each)],
            'pendingCount': result.pending.length,
            'status': result.status.name,
            'undoToken': result.undoToken,
            'undoDeadline': result.undoDeadline?.toUtc().toIso8601String(),
          };
        },
      );

  /// Undo — bounded, conservative, and explicit about what it would not do.
  ///
  /// It takes the operation and the token the server issued for it, and
  /// nothing else: a caller cannot name which members come back, because undo
  /// reverses what that operation did or it refuses. The window is enforced
  /// against the server's clock, and an expired one arrives as `refusal:
  /// "expired"` rather than as an error — it is a thing a person is told.
  ///
  /// Members whose object moved since the sweep are refused individually and
  /// reported with a reason: later intent wins, so undo never puts the old
  /// state back on top of the new one.
  GraphQLObjectField<dynamic, dynamic> get attentionUndo => GraphQLObjectField(
    'attentionUndo',
    gqlTypeAttentionUndoResult.nonNullable(),
    arguments: [_operationId.field, _undoToken.field],
    resolve: (_, args) async {
      final accountId = getCredentials(args).sub;
      final result = await _sweep.undo(
        accountId: accountId,
        operationId: _operationId.fromArgsNonNullable(args),
        undoToken: _undoToken.fromArgsNonNullable(args),
      );
      Map<String, dynamic> member(AttentionUndoMember member) => {
        'kind': member.kind,
        'id': member.id,
        'reason': member.reason?.wireName,
      };
      return {
        'operationId': result.operationId,
        'restoredReceiptIds': result.restoredReceiptIds,
        'restoredOutcomeBeaconIds': result.restoredOutcomeBeaconIds,
        'restoredCount': result.restoredCount,
        'skipped': [for (final each in result.skipped) member(each)],
        'failed': [for (final each in result.failed) member(each)],
        'status': result.status.name,
        'refusal': result.refusal?.wireName,
      };
    },
  );

  /// Clears exactly the membership captured by `snapshotToken` — never more.
  ///
  /// Idempotent by `operationId`: a replay, concurrent or not, returns the
  /// first apply's answer instead of clearing anything further. Obligations
  /// and any receipt the caller may no longer read are skipped, and an id that
  /// is not the caller's is denied without saying whether it exists.
  GraphQLObjectField<dynamic, dynamic> get attentionClear => GraphQLObjectField(
    'attentionClear',
    gqlTypeAttentionClearResult.nonNullable(),
    arguments: [_snapshotToken.field, _operationId.field],
    resolve: (_, args) async {
      final accountId = getCredentials(args).sub;
      final result = await _clear.clear(
        accountId: accountId,
        operationId: _operationId.fromArgsNonNullable(args),
        snapshotToken: _snapshotToken.fromArgsNonNullable(args),
      );
      return {
        'operationId': result.operationId,
        'appliedReceiptIds': result.appliedReceiptIds,
        'skippedReceiptIds': result.skippedReceiptIds,
        'deniedReceiptIds': result.deniedReceiptIds,
        'status': result.status.name,
        'undoToken': result.undoToken,
        'undoDeadline': result.undoDeadline?.toUtc().toIso8601String(),
      };
    },
  );

  GraphQLObjectField<dynamic, dynamic> get attentionMarkSeen =>
      GraphQLObjectField(
        'attentionMarkSeen',
        graphQLInt.nonNullable(),
        arguments: [_ids.field],
        resolve: (_, args) {
          final ids = _ids.fromArgsNonNullable(args);
          if (ids.length > 200) {
            throw ArgumentError.value(
              ids.length,
              'ids',
              'must contain at most 200 ids',
            );
          }
          return _ack.markSeen(accountId: getCredentials(args).sub, ids: ids);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get attentionMarkUnseen =>
      GraphQLObjectField(
        'attentionMarkUnseen',
        graphQLInt.nonNullable(),
        arguments: [_ids.field],
        resolve: (_, args) {
          final ids = _ids.fromArgsNonNullable(args);
          if (ids.length > 200) {
            throw ArgumentError.value(
              ids.length,
              'ids',
              'must contain at most 200 ids',
            );
          }
          return _ack.markUnseen(
            accountId: getCredentials(args).sub,
            ids: ids,
          );
        },
      );

  GraphQLObjectField<dynamic, dynamic> get attentionMarkAllSeen =>
      GraphQLObjectField(
        'attentionMarkAllSeen',
        graphQLInt.nonNullable(),
        arguments: [_surface.fieldNullable],
        resolve: (_, args) => _ack.markAllSeen(
          getCredentials(args).sub,
          surface: QueryAttention.parseSurfaceArgument(_surface.fromArgs(args)),
        ),
      );

  GraphQLObjectField<dynamic, dynamic> get attentionMarkSeenForBeacon =>
      GraphQLObjectField(
        'attentionMarkSeenForBeacon',
        graphQLInt.nonNullable(),
        arguments: [_beaconId.field],
        resolve: (_, args) => _ack.markSeenForBeacon(
          accountId: getCredentials(args).sub,
          beaconId: _beaconId.fromArgsNonNullable(args),
        ),
      );

  static final _ids = InputFieldStringList(fieldName: 'ids');
  static final _beaconId = InputFieldString(fieldName: 'beaconId');
  static final _receiptId = InputFieldString(fieldName: 'receiptId');
  static final _settlementKind = InputFieldString(fieldName: 'kind');
  static final _surface = InputFieldString(fieldName: 'surface');
  static final _snapshotToken = InputFieldString(fieldName: 'snapshotToken');
  static final _operationId = InputFieldString(fieldName: 'operationId');
  static final _maxBatches = InputFieldInt(fieldName: 'maxBatches');
  static final _undoToken = InputFieldString(fieldName: 'undoToken');

  GraphQLObjectField<dynamic, dynamic> get attentionSettle =>
      GraphQLObjectField(
        'attentionSettle',
        graphQLInt.nonNullable(),
        arguments: [_receiptId.field, _settlementKind.field],
        resolve: (_, args) {
          final accountId = getCredentials(args).sub;
          return _settlement.settle(
            accountId: accountId,
            receiptId: _receiptId.fromArgsNonNullable(args),
            kind: attentionSettlementKindFromWireName(
              _settlementKind.fromArgsNonNullable(args),
            ),
          );
        },
      );
}
