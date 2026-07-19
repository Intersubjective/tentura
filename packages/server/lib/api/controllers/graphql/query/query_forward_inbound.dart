import 'package:tentura_server/domain/use_case/forward_inbound_query_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryForwardInbound extends GqlNodeBase {
  QueryForwardInbound({ForwardInboundQueryCase? case_})
    : _case = case_ ?? GetIt.I<ForwardInboundQueryCase>();

  final ForwardInboundQueryCase _case;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [beaconEligibleInboundForwards];

  GraphQLObjectField<dynamic, dynamic> get beaconEligibleInboundForwards =>
      GraphQLObjectField(
        'beaconEligibleInboundForwards',
        GraphQLListType(_inboundType.nonNullable()),
        arguments: [InputFieldId.field],
        resolve: (_, args) async {
          final rows = await _case.listEligible(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            viewerId: getCredentials(args).sub,
          );
          return rows
              .map(
                (r) => {
                  'edgeId': r.edgeId,
                  'senderId': r.senderId,
                  'senderName': r.senderName,
                  'createdAt': r.createdAt.toIso8601String(),
                  'isSuggestedSource': r.isSuggestedSource,
                },
              )
              .toList();
        },
      );

  static final _inboundType = GraphQLObjectType(
    'ForwardInboundEdge',
    fields: [
      GraphQLField('edgeId', graphQLString.nonNullable()),
      GraphQLField('senderId', graphQLString.nonNullable()),
      GraphQLField('senderName', graphQLString.nonNullable()),
      GraphQLField('createdAt', graphQLString.nonNullable()),
      GraphQLField('isSuggestedSource', graphQLBoolean.nonNullable()),
    ],
  );
}
