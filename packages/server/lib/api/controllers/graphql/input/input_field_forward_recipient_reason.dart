part of '_input_types.dart';

abstract class InputFieldForwardRecipientReasons {
  static final field = GraphQLFieldInput(
    _fieldKey,
    GraphQLListType(type),
    defaultsToNull: true,
  );

  static final type = GraphQLInputObjectType(
    'ForwardRecipientReasonInput',
    inputFields: [
      GraphQLInputObjectField('recipientId', graphQLString.nonNullable()),
      GraphQLInputObjectField(
        'slugs',
        GraphQLListType(graphQLString.nonNullable()),
      ),
    ],
  );

  static List<({String recipientId, List<String> slugs})>? fromArgs(
    Map<String, dynamic> args,
  ) {
    final raw = args[_fieldKey];
    if (raw == null) return null;
    return (raw as List)
        .map(
          (e) {
            final m = e as Map<dynamic, dynamic>;
            return (
              recipientId: m['recipientId'] as String,
              slugs: List<String>.from(
                (m['slugs'] as List?) ?? <String>[],
              ),
            );
          },
        )
        .toList();
  }

  static const _fieldKey = 'recipientReasons';
}
