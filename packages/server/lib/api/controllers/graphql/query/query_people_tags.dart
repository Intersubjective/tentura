import 'package:tentura_server/domain/use_case/people_tags_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';

final class QueryPeopleTags extends GqlNodeBase {
  QueryPeopleTags({PeopleTagsCase? useCase})
    : _case = useCase ?? GetIt.I<PeopleTagsCase>();

  final PeopleTagsCase _case;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [personTags];

  GraphQLObjectField<dynamic, dynamic> get personTags => GraphQLObjectField(
    'personTags',
    GraphQLListType(gqlTypePersonTag.nonNullable()).nonNullable(),
    resolve: (_, args) async => [
      for (final t in await _case.list(ownerId: getCredentials(args).sub))
        t.toJson(),
    ],
  );
}
