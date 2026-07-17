import 'package:tentura_server/domain/port/attention_ack_port.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/use_case/attention_settlement_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationAttention extends GqlNodeBase {
  MutationAttention({
    AttentionAckPort? ack,
    AttentionSettlementCase? settlement,
  }) : _ack = ack ?? GetIt.I<AttentionAckPort>(),
       _settlementOverride = settlement;

  final AttentionAckPort _ack;
  final AttentionSettlementCase? _settlementOverride;

  AttentionSettlementCase get _settlement =>
      _settlementOverride ?? GetIt.I<AttentionSettlementCase>();

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    attentionMarkSeen,
    attentionMarkAllSeen,
    attentionSettle,
  ];

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

  GraphQLObjectField<dynamic, dynamic> get attentionMarkAllSeen =>
      GraphQLObjectField(
        'attentionMarkAllSeen',
        graphQLInt.nonNullable(),
        resolve: (_, args) => _ack.markAllSeen(getCredentials(args).sub),
      );

  static final _ids = InputFieldStringList(fieldName: 'ids');
  static final _receiptId = InputFieldString(fieldName: 'receiptId');
  static final _settlementKind = InputFieldString(fieldName: 'kind');

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
