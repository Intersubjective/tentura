import 'package:tentura_server/domain/port/attention_ack_port.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/use_case/attention_clear_case.dart';
import 'package:tentura_server/domain/use_case/attention_settlement_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import '../query/query_attention.dart';

final class MutationAttention extends GqlNodeBase {
  MutationAttention({
    AttentionAckPort? ack,
    AttentionSettlementCase? settlement,
    AttentionClearCase? clear,
  }) : _ack = ack ?? GetIt.I<AttentionAckPort>(),
       _settlementOverride = settlement,
       _clearOverride = clear;

  final AttentionAckPort _ack;
  final AttentionSettlementCase? _settlementOverride;
  final AttentionClearCase? _clearOverride;

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
  ];

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
