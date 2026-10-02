part of '_input_types.dart';

abstract class InputFieldUpload {
  static final field = GraphQLFieldInput(
    _fieldKey,
    type,
    defaultValue: <String, dynamic>{},
  );

  static final fieldNullable = GraphQLFieldInput(
    _fieldKey,
    type,
    defaultsToNull: true,
  );

  static final fieldImage = GraphQLFieldInput(
    _fieldImageKey,
    type,
    defaultValue: <String, dynamic>{},
  );

  static final type = _UploadInputType();

  static Stream<Uint8List>? fromArgs(Map<String, dynamic> args) =>
      args[kGlobalInputQueryFile] as Stream<Uint8List>?;

  /// Variable map entry for the multipart `file` input (`filename`, `type`).
  static Map<String, dynamic>? uploadVariablesFromArgs(
    Map<String, dynamic> args,
  ) {
    final v = args[_fieldKey];
    if (v is Map<String, dynamic>) {
      return v;
    }
    return null;
  }

  static const _fieldKey = 'file';

  static const _fieldImageKey = 'image';
}

/// `Upload` input; an unset variable (`null`) deserializes to an empty map.
final class _UploadInputType extends GraphQLInputObjectType {
  _UploadInputType()
    : super(
        'Upload',
        inputFields: [
          GraphQLInputObjectField('filename', graphQLString),
          GraphQLInputObjectField('type', graphQLString),
        ],
      );

  @override
  ValidationResult<Map<String, dynamic>> validate(String key, dynamic input) =>
      super.validate(
        key,
        input as Map<dynamic, dynamic>? ?? const <String, dynamic>{},
      );

  @override
  Map<String, dynamic> deserialize(Map<dynamic, dynamic>? serialized) =>
      super.deserialize(serialized ?? const <String, dynamic>{});
}
