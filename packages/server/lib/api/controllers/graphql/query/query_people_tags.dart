import 'package:tentura_server/domain/use_case/people_tags_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryPeopleTags extends GqlNodeBase {
  QueryPeopleTags({PeopleTagsCase? useCase})
    : _case = useCase ?? GetIt.I<PeopleTagsCase>();

  final PeopleTagsCase _case;

  static final _personId = InputFieldString(fieldName: 'personId');
  static final _kind = InputFieldInt(fieldName: 'kind');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    personTags,
    personTagsOf,
    personTagMemberships,
    personAutoTags,
    personAutoTagMembers,
    personTagSuggestionState,
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
    resolve: (_, args) async {
      final ownerId = getCredentials(args).sub;
      final personId = _personId.fromArgsNonNullable(args);
      return {
        'own': await _case.tagIdsOf(ownerId: ownerId, personId: personId),
        'auto': [
          for (final a in await _case.autoTagsOf(
            ownerId: ownerId,
            personId: personId,
          ))
            a.toJson(),
        ],
      };
    },
  );

  GraphQLObjectField<dynamic, dynamic> get personAutoTags =>
      GraphQLObjectField(
        'personAutoTags',
        GraphQLListType(gqlTypePersonAutoTag.nonNullable()).nonNullable(),
        resolve: (_, args) async => [
          for (final t in await _case.autoTags(
            ownerId: getCredentials(args).sub,
          ))
            t.toJson(),
        ],
      );

  GraphQLObjectField<dynamic, dynamic> get personAutoTagMembers =>
      GraphQLObjectField(
        'personAutoTagMembers',
        GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        arguments: [_kind.fieldNonNullable],
        resolve: (_, args) => _case.autoTagMembers(
          ownerId: getCredentials(args).sub,
          kind: _kind.fromArgsNonNullable(args),
        ),
      );

  GraphQLObjectField<dynamic, dynamic> get personTagSuggestionState =>
      GraphQLObjectField(
        'personTagSuggestionState',
        gqlTypePersonTagSuggestionState.nonNullable(),
        resolve: (_, args) async => (await _case.suggestionState(
          ownerId: getCredentials(args).sub,
        )).toGraphQL(),
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
