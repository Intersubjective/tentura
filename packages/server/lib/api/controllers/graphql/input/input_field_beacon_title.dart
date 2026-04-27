part of '_input_types.dart';

abstract class InputFieldBeaconTitle {
  static final field = GraphQLFieldInput(
    _fieldKey,
    graphQLStringRange(kTitleMinLength, kBeaconTitleMaxLength),
    defaultsToNull: true,
  );

  static final fieldNonNullable = GraphQLFieldInput(
    _fieldKey,
    graphQLStringRange(kTitleMinLength, kBeaconTitleMaxLength).nonNullable(),
  );

  static String? fromArgs(Map<String, dynamic> args) =>
      args[_fieldKey] as String?;

  static String fromArgsNonNullable(Map<String, dynamic> args) =>
      args[_fieldKey]! as String;

  static const _fieldKey = 'title';
}
