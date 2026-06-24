part of '_input_types.dart';

abstract class InputFieldBeaconDisplayTier {
  static final field = GraphQLFieldInput(
    _fieldKey,
    graphQLInt.nonNullable(),
  );

  /// 0 = coordination, 1 = public
  static int fromArgs(Map<String, dynamic> args) => args[_fieldKey]! as int;

  static const _fieldKey = 'tier';
}
