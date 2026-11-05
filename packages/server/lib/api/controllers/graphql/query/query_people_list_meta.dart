import 'package:tentura_server/domain/use_case/people_list_meta_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';

/// Root query field [peopleListMeta]: sort keys for the JWT viewer's People
/// tab, one row per trusted person.
final class QueryPeopleListMeta extends GqlNodeBase {
  QueryPeopleListMeta({PeopleListMetaCase? peopleListMetaCase})
    : _case = peopleListMetaCase ?? GetIt.I<PeopleListMetaCase>();

  final PeopleListMetaCase _case;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [peopleListMeta];

  GraphQLObjectField<dynamic, dynamic> get peopleListMeta => GraphQLObjectField(
    'peopleListMeta',
    GraphQLListType(gqlTypePersonListMeta.nonNullable()).nonNullable(),
    resolve: (_, args) async {
      final rows = await _case.fetch(viewerId: getCredentials(args).sub);
      return [
        for (final row in rows)
          {
            'id': row.id,
            'newSince': row.newSince?.toUtc(),
            'newReason': row.newReason?.name,
            'lastInteractionAt': row.lastInteractionAt?.toUtc(),
          },
      ];
    },
  );
}
