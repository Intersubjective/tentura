part of '_input_types.dart';

abstract class InputFieldId {
  static final field = GraphQLFieldInput(
    _fieldKey,
    graphQLStringRange(kIdLength, kIdLength).nonNullable(),
  );

  static final fieldNullable = GraphQLFieldInput(
    _fieldKey,
    graphQLStringRange(kIdLength, kIdLength),
    defaultsToNull: true,
  );

  static String? fromArgs(Map<String, dynamic> args) =>
      args[_fieldKey] as String?;

  static String fromArgsNonNullable(Map<String, dynamic> args) =>
      args[_fieldKey] as String? ?? '';

  static const _fieldKey = 'id';
}
