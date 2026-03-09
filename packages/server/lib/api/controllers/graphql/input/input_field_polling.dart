part of '_input_types.dart';

abstract class InputFieldPolling {
  static final field = GraphQLFieldInput(
    _fieldKey,
    type,
    defaultsToNull: true,
  );

  static final type = GraphQLInputObjectType(
    'PollingInput',
    inputFields: [
      GraphQLInputObjectField(_questionKey, graphQLString),
      GraphQLInputObjectField(
        _variantsKey,
        GraphQLListType(graphQLString),
      ),
    ],
  );

  static ({String? question, List<String>? variants})? fromArgs(
    Map<String, dynamic> args,
  ) => switch (args[_fieldKey]) {
    final Map<dynamic, dynamic> p when p.isNotEmpty => (
      question: p[_questionKey] as String?,
      variants: p[_variantsKey] as List<String>?,
    ),
    _ => null,
  };

  static const _fieldKey = 'polling';

  static const _questionKey = 'question';

  static const _variantsKey = 'variants';
}
