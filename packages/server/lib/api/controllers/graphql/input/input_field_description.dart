part of '_input_types.dart';

abstract class InputFieldDescription {
  static final field = GraphQLFieldInput(
    _fieldKey,
    graphQLString,
    defaultsToNull: true,
  );

  static final fieldNonNullable = GraphQLFieldInput(
    _fieldKey,
    graphQLString.nonNullable(),
  );

  static String? fromArgs(Map<String, dynamic> args) =>
      args[_fieldKey] as String?;

  static String fromArgsNonNullable(Map<String, dynamic> args) =>
      args[_fieldKey]! as String;

  static const _fieldKey = 'description';
}
