import 'package:built_value/serializer.dart';

/// Hasura sends `float8` as a JSON number or a quoted string depending on
/// context (e.g. computed scores arrive as `"95"` instead of `95`).
class Float8Serializer implements PrimitiveSerializer<double> {
  @override
  double deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => switch (serialized) {
    final num n => n.toDouble(),
    final String s => double.parse(s),
    _ => throw FormatException(
        'Float8Serializer: unexpected ${serialized.runtimeType}'),
  };

  @override
  Object serialize(
    Serializers serializers,
    double value, {
    FullType specifiedType = FullType.unspecified,
  }) => value;

  @override
  Iterable<Type> get types => [double];

  @override
  String get wireName => 'float8';
}
