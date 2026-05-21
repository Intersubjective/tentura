part of '_input_types.dart';

abstract class InputFieldDisplayName {
  static final field = GraphQLFieldInput(
    _fieldKey,
    graphQLStringRange(kTitleMinLength, kTitleMaxLength),
    defaultsToNull: true,
  );

  static final fieldNonNullable = GraphQLFieldInput(
    _fieldKey,
    graphQLStringRange(kTitleMinLength, kTitleMaxLength).nonNullable(),
  );

  static String? fromArgs(Map<String, dynamic> args) =>
      args[_fieldKey] as String?;

  static String fromArgsNonNullable(Map<String, dynamic> args) =>
      args[_fieldKey]! as String;

  static const _fieldKey = 'displayName';
}
