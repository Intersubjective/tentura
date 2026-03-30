import 'package:built_value/serializer.dart';

/// Hasura may send `smallint` as a JSON number or a quoted string.
class SmallintSerializer implements PrimitiveSerializer<int> {
  @override
  int deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => switch (serialized) {
    final int n => n,
    final num n => n.toInt(),
    final String s => int.parse(s),
    _ => throw FormatException(
        'SmallintSerializer: unexpected ${serialized.runtimeType}'),
  };

  @override
  Object serialize(
    Serializers serializers,
    int value, {
    FullType specifiedType = FullType.unspecified,
  }) => value;

  @override
  Iterable<Type> get types => [int];

  @override
  String get wireName => 'smallint';
}
