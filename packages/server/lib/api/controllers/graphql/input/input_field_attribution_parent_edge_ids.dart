part of '_input_types.dart';

abstract class InputFieldAttributionParentEdgeIds {
  static final field = GraphQLFieldInput(
    _fieldKey,
    GraphQLListType(graphQLString.nonNullable()),
    defaultsToNull: true,
  );

  static List<String>? fromArgs(Map<String, dynamic> args) {
    final raw = args[_fieldKey];
    if (raw == null) return null;
    return List<String>.from(raw as List);
  }

  static const _fieldKey = 'attributionParentEdgeIds';
}
