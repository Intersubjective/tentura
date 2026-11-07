import 'package:tentura_server/domain/use_case/field_visibility_case.dart';

import '../custom_types.dart';
import '../gql_node_base.dart';
import '../input/_input_types.dart';

final class QueryFieldHiddenItems extends GqlNodeBase {
  QueryFieldHiddenItems({FieldVisibilityCase? useCase})
    : _case = useCase ?? GetIt.I<FieldVisibilityCase>();

  final FieldVisibilityCase _case;
  static final _cursor = InputFieldDatetime(fieldName: 'cursor');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    GraphQLObjectField(
      'fieldHiddenItems',
      GraphQLListType(gqlTypeFieldHiddenItem.nonNullable()),
      arguments: [_cursor.fieldNullable],
      resolve: (_, args) async => [
        for (final item in await _case.hiddenItems(
          viewerId: getCredentials(args).sub,
          before: _cursor.fromArgs(args),
        ))
          {
            'targetKind': item.targetKind.value,
            'targetId': item.targetId,
            'title': item.title,
            'authorId': item.authorId,
            'hiddenAt': item.hiddenAt.toIso8601String(),
          },
      ],
    ),
  ];
}
