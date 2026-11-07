import 'dart:convert';

import 'package:tentura_server/domain/entity/person_field_items_page.dart';
import 'package:tentura_server/domain/use_case/field_visibility_case.dart';

import '../custom_types.dart';
import '../gql_node_base.dart';
import '../input/_input_types.dart';

final class QueryPersonFieldItems extends GqlNodeBase {
  QueryPersonFieldItems({FieldVisibilityCase? useCase})
    : _case = useCase ?? GetIt.I<FieldVisibilityCase>();

  final FieldVisibilityCase _case;
  static final _personId = InputFieldString(fieldName: 'personId');
  static final _bucket = InputFieldString(fieldName: 'bucket');
  static final _query = InputFieldString(fieldName: 'query');
  static final _cursor = InputFieldString(fieldName: 'cursor');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    GraphQLObjectField(
      'personFieldItems',
      gqlTypePersonFieldItemsPage.nonNullable(),
      arguments: [
        _personId.field,
        _bucket.field,
        _query.fieldNullable,
        _cursor.fieldNullable,
      ],
      resolve: (_, args) async {
        final bucket = _bucket.fromArgsNonNullable(args);
        final result = await _case.personItems(
          viewerId: getCredentials(args).sub,
          personId: _personId.fromArgsNonNullable(args),
          bucket: switch (bucket) {
            'active' => PersonFieldBucket.active,
            'closed' => PersonFieldBucket.closed,
            'hidden' => PersonFieldBucket.hidden,
            _ => throw ArgumentError.value(bucket, 'bucket', 'Unknown bucket'),
          },
          query: _query.fromArgs(args) ?? '',
          cursor: _decodeCursor(_cursor.fromArgs(args)),
        );
        return {
          'items': [
            for (final item in result.items)
              {
                'id': item.id,
                'kind': item.kind.value,
                'authorId': item.authorId,
                'title': item.title,
                'rootExcerpt': item.rootExcerpt,
                'status': item.status,
                'hidden': item.hidden,
                'lastActivityAt': item.lastActivityAt.toIso8601String(),
                'expiresAt': item.expiresAt?.toIso8601String(),
              },
          ],
          'nextCursor': switch (result.nextCursor) {
            final cursor? => base64Url.encode(
              utf8.encode(
                jsonEncode([
                  cursor.activityAt.toIso8601String(),
                  cursor.id,
                ]),
              ),
            ),
            null => null,
          },
          'counts': {
            'active': result.counts.active,
            'closed': result.counts.closed,
            'hidden': result.counts.hidden,
          },
        };
      },
    ),
  ];

  static PersonFieldCursor? _decodeCursor(String? value) {
    if (value == null) return null;
    final decoded = jsonDecode(utf8.decode(base64Url.decode(value)));
    if (decoded case [
      final String at,
      final String id,
    ] when id.isNotEmpty && id.length <= 256) {
      final activityAt = DateTime.tryParse(at);
      if (activityAt != null) return (activityAt: activityAt.toUtc(), id: id);
    }
    throw ArgumentError.value(value, 'cursor', 'Invalid person Field cursor');
  }
}
