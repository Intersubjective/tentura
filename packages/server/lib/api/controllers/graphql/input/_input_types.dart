import 'dart:typed_data';
import 'package:graphql_schema2/graphql_schema2.dart';

import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/consts.dart';

part 'input_field_coordinates.dart';
part 'input_field_description.dart';
part 'input_field_drop_image.dart';
part 'input_field_context.dart';
part 'input_field_image_ids.dart';
part 'input_field_polling.dart';
part 'input_field_upload.dart';
part 'input_field_title.dart';
part 'input_field_id.dart';
part 'input_field_recipient_ids.dart';

const kGlobalInputQueryContext = 'queryContext';
const kGlobalInputQueryFile = 'queryFile';
const kGlobalInputQueryJwt = kContextJwtKey;

final fieldId = InputFieldString(fieldName: 'id');

class InputFieldBool {
  InputFieldBool({required String fieldName})
    : field = GraphQLFieldInput(fieldName, graphQLBoolean.nonNullable()),
      fieldNullable = GraphQLFieldInput(
        fieldName,
        graphQLBoolean,
        defaultsToNull: true,
      );

  final GraphQLFieldInput<bool, bool> field;

  final GraphQLFieldInput<bool?, bool?> fieldNullable;

  bool? fromArgs(Map<String, dynamic> args) => args[field.name] as bool?;

  bool fromArgsNonNullable(Map<String, dynamic> args) =>
      args[field.name] == true;
}

class InputFieldString {
  InputFieldString({required String fieldName})
    : field = GraphQLFieldInput(fieldName, graphQLString.nonNullable()),
      fieldNullable = GraphQLFieldInput(
        fieldName,
        graphQLString,
        defaultsToNull: true,
      );

  final GraphQLFieldInput<String, String> field;

  final GraphQLFieldInput<String?, String?> fieldNullable;

  String? fromArgs(Map<String, dynamic> args) => args[field.name] as String?;

  String fromArgsNonNullable(Map<String, dynamic> args) =>
      args[field.name]! as String;
}

class InputFieldDatetime {
  InputFieldDatetime({required String fieldName})
    : field = GraphQLFieldInput(fieldName, graphQLString.nonNullable()),
      fieldNullable = GraphQLFieldInput(
        fieldName,
        graphQLString,
        defaultsToNull: true,
      );

  final GraphQLFieldInput<String, String> field;

  final GraphQLFieldInput<String?, String?> fieldNullable;

  DateTime? fromArgs(Map<String, dynamic> args) => switch (args[field.name]) {
    final String field when field.isNotEmpty => DateTime.tryParse(field),
    _ => null,
  };

  DateTime fromArgsNonNullable(Map<String, dynamic> args) =>
      DateTime.parse(args[field.name]! as String);
}
