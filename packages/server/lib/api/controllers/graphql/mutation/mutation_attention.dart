import 'package:tentura_server/domain/port/attention_ack_port.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/attention/attention_sweep_models.dart';
import 'package:tentura_server/domain/use_case/attention_clear_case.dart';
import 'package:tentura_server/domain/use_case/attention_settlement_case.dart';
import 'package:tentura_server/domain/use_case/attention_sweep_case.dart';

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
  }) : _ack = ack ?? GetIt.I<AttentionAckPort>(),
       _settlementOverride = settlement,
       _clearOverride = clear,
       _sweepOverride = sweep;

  final AttentionAckPort _ack;
  final AttentionSettlementCase? _settlementOverride;
  final AttentionClearCase? _clearOverride;
  final AttentionSweepCase? _sweepOverride;

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
  ];

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
