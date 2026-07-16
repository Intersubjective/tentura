import 'package:tentura_server/domain/port/attention_ack_port.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationAttention extends GqlNodeBase {
  MutationAttention({AttentionAckPort? ack})
    : _ack = ack ?? GetIt.I<AttentionAckPort>();

  final AttentionAckPort _ack;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    attentionMarkSeen,
    attentionMarkAllSeen,
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
}
