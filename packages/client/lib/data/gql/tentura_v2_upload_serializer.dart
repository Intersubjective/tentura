import 'package:built_value/serializer.dart';

import 'tentura_v2_upload.dart';

class TenturaV2UploadSerializer extends PrimitiveSerializer<TenturaV2Upload> {
  @override
  TenturaV2Upload deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => throw UnimplementedError('TenturaV2Upload is outbound-only');

  @override
  Object serialize(
    Serializers serializers,
    TenturaV2Upload upload, {
    FullType specifiedType = FullType.unspecified,
  }) => upload;

  @override
  Iterable<Type> get types => const [TenturaV2Upload];

  @override
  String get wireName => 'v2_Upload';
}
