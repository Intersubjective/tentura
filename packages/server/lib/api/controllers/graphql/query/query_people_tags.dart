import 'package:tentura_server/domain/use_case/people_tags_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryPeopleTags extends GqlNodeBase {
  QueryPeopleTags({PeopleTagsCase? useCase})
    : _case = useCase ?? GetIt.I<PeopleTagsCase>();

  final PeopleTagsCase _case;

  static final _personId = InputFieldString(fieldName: 'personId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    personTags,
    personTagsOf,
    personTagMemberships,
  ];

  GraphQLObjectField<dynamic, dynamic> get personTags => GraphQLObjectField(
    'personTags',
    GraphQLListType(gqlTypePersonTag.nonNullable()).nonNullable(),
    resolve: (_, args) async => [
      for (final t in await _case.list(ownerId: getCredentials(args).sub))
        t.toGraphQL(),
    ],
  );

  GraphQLObjectField<dynamic, dynamic> get personTagsOf => GraphQLObjectField(
    'personTagsOf',
    gqlTypePersonTagsOf.nonNullable(),
    arguments: [_personId.field],
    resolve: (_, args) async => {
      'own': await _case.tagIdsOf(
        ownerId: getCredentials(args).sub,
        personId: _personId.fromArgsNonNullable(args),
      ),
    },
  );

  GraphQLObjectField<dynamic, dynamic> get personTagMemberships =>
      GraphQLObjectField(
        'personTagMemberships',
        GraphQLListType(gqlTypePersonTagMembers.nonNullable()).nonNullable(),
        resolve: (_, args) async => [
          for (final m in await _case.memberships(
            ownerId: getCredentials(args).sub,
          ))
            m.toJson(),
        ],
      );
}
