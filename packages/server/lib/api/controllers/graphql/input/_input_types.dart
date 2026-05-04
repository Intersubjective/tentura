import 'dart:typed_data';
import 'package:graphql_schema2/graphql_schema2.dart';

import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/consts.dart';

part 'input_field_coordinates.dart';
part 'input_field_beacon_ids.dart';
part 'input_field_description.dart';
part 'input_field_drop_image.dart';
part 'input_field_context.dart';
part 'input_field_image_ids.dart';
part 'input_field_upload.dart';
part 'input_field_title.dart';
part 'input_field_beacon_title.dart';
part 'input_field_id.dart';
part 'input_field_recipient_ids.dart';
part 'input_field_forward_recipient_reason.dart';

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

/// `[String!]` list; outer argument nullable when using [fieldNullable].
class InputFieldStringList {
  InputFieldStringList({required String fieldName})
    : field = GraphQLFieldInput(
        fieldName,
        GraphQLListType(graphQLString.nonNullable()),
      ),
      fieldNullable = GraphQLFieldInput(
        fieldName,
        GraphQLListType(graphQLString.nonNullable()),
        defaultsToNull: true,
      );

  final GraphQLFieldInput<List<String>, List<String>> field;

  final GraphQLFieldInput<List<String>?, List<String>?> fieldNullable;

  List<String>? fromArgs(Map<String, dynamic> args) {
    final raw = args[field.name];
    if (raw == null) return null;
    return List<String>.from(raw as List);
  }

  List<String> fromArgsNonNullable(Map<String, dynamic> args) =>
      List<String>.from(args[field.name]! as List);
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

class InputFieldInt {
  InputFieldInt({required String fieldName})
    : fieldNullable = GraphQLFieldInput(
        fieldName,
        graphQLInt,
        defaultsToNull: true,
      );

  final GraphQLFieldInput<int?, int?> fieldNullable;

  int? fromArgs(Map<String, dynamic> args) {
    final raw = args[fieldNullable.name];
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString());
  }
}
