import 'package:tentura_server/domain/use_case/person_context_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryPersonSharedContexts extends GqlNodeBase {
  QueryPersonSharedContexts({PersonContextCase? personContextCase})
    : _personContextCase = personContextCase ?? GetIt.I<PersonContextCase>();

  final PersonContextCase _personContextCase;

  final _userId = InputFieldString(fieldName: 'userId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [personSharedContexts];

  GraphQLObjectField<dynamic, dynamic> get personSharedContexts =>
      GraphQLObjectField(
        'personSharedContexts',
        GraphQLListType(
          gqlTypePersonSharedContext.nonNullable(),
        ).nonNullable(),
        arguments: [_userId.field],
        resolve: (_, args) async {
          final viewerId = getCredentials(args).sub;
          final peerId = _userId.fromArgsNonNullable(args);
          if (viewerId == peerId) return const <Map<String, String>>[];
          final rows = await _personContextCase.sharedContexts(
            viewerId: viewerId,
            peerId: peerId,
          );
          return [
            for (final r in rows) {'beaconId': r.beaconId, 'title': r.title},
          ];
        },
      );
}
