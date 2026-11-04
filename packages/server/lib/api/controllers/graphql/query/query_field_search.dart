import 'package:tentura_server/domain/use_case/field_visibility_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryFieldSearch extends GqlNodeBase {
  QueryFieldSearch({FieldVisibilityCase? useCase})
    : _case = useCase ?? GetIt.I<FieldVisibilityCase>();

  final FieldVisibilityCase _case;
  static final _query = InputFieldString(fieldName: 'query');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    GraphQLObjectField(
      'fieldSearch',
      gqlTypeFieldSearchResult.nonNullable(),
      arguments: [_query.field, InputFieldContext.fieldNonNullable],
      resolve: (_, args) async {
        final result = await _case.search(
          viewerId: getCredentials(args).sub,
          query: _query.fromArgsNonNullable(args),
          context: InputFieldContext.fromArgsNonNullable(args),
        );
        return {
          'people': [
            for (final person in result.people)
              {
                'id': person.id,
                'displayName': person.displayName,
                'handle': person.handle,
              },
          ],
          'requests': [
            for (final item in result.requests)
              {
                'id': item.id,
                'authorId': item.authorId,
                'title': item.title,
                'status': item.status,
                'hidden': item.hidden,
                'lastActivityAt': item.lastActivityAt.toIso8601String(),
              },
          ],
          'posts': [
            for (final item in result.posts)
              {
                'id': item.id,
                'authorId': item.authorId,
                'rootExcerpt': item.rootExcerpt,
                'status': item.status,
                'hidden': item.hidden,
                'lastActivityAt': item.lastActivityAt.toIso8601String(),
                'expiresAt': item.expiresAt?.toIso8601String(),
              },
          ],
        };
      },
    ),
  ];
}
