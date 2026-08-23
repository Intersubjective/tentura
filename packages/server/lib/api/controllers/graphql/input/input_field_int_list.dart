part of '_input_types.dart';

/// `[Int!]` list; outer argument nullable when using [fieldNullable].
class InputFieldIntList {
  InputFieldIntList({required String fieldName})
    : field = GraphQLFieldInput(
        fieldName,
        GraphQLListType(graphQLInt.nonNullable()),
      ),
      fieldNullable = GraphQLFieldInput(
        fieldName,
        GraphQLListType(graphQLInt.nonNullable()),
        defaultsToNull: true,
      );

  final GraphQLFieldInput<List<int>, List<int>> field;
  final GraphQLFieldInput<List<int>?, List<int>?> fieldNullable;

  List<int>? fromArgs(Map<String, dynamic> args) {
    final raw = args[field.name];
    if (raw == null) return null;
    return List<int>.from(raw as List);
  }
}
