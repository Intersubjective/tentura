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

  static final type = GraphQLInputObjectType(
    'Upload',
    inputFields: [
      GraphQLInputObjectField('filename', graphQLString),
      GraphQLInputObjectField('type', graphQLString),
    ],
  );

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
