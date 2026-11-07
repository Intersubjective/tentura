import 'package:tentura_server/domain/use_case/constellation_new_people_case.dart';

import '../gql_node_base.dart';
import '../input/_input_types.dart';

final class MutationConstellationNewPeople extends GqlNodeBase {
  MutationConstellationNewPeople({ConstellationNewPeopleCase? useCase})
    : _case = useCase ?? GetIt.I<ConstellationNewPeopleCase>();

  final ConstellationNewPeopleCase _case;
  final _peerIds = InputFieldStringList(fieldName: 'peerIds');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    constellationAcknowledgeNew,
  ];

  GraphQLObjectField<dynamic, dynamic> get constellationAcknowledgeNew =>
      GraphQLObjectField(
        'constellationAcknowledgeNew',
        graphQLBoolean.nonNullable(),
        arguments: [_peerIds.field],
        resolve: (_, args) async {
          final viewerId = getCredentials(args).sub;
          final peerIds = _peerIds.fromArgs(args);
          // graphql_schema2 cannot wrap a list in nonNullable; require it here.
          if (peerIds == null) {
            throw GraphQLException([
              GraphQLExceptionError('peerIds is required'),
            ]);
          }
          await _case.acknowledge(viewerId: viewerId, peerIds: peerIds);
          return true;
        },
      );
}
