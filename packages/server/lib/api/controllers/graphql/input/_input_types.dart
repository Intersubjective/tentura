import 'dart:typed_data';
import 'package:graphql_schema2/graphql_schema2.dart';

import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/consts.dart';

part 'input_field_coordinates.dart';
part 'input_field_beacon_ids.dart';
part 'input_field_beacon_display_tier.dart';
part 'input_field_description.dart';
part 'input_field_drop_image.dart';
part 'input_field_context.dart';
part 'input_field_image_ids.dart';
part 'input_field_beacon_media.dart';
part 'input_field_upload.dart';
part 'input_field_title.dart';
part 'input_field_display_name.dart';
part 'input_field_beacon_title.dart';
part 'input_field_id.dart';
part 'input_field_recipient_ids.dart';
part 'input_field_forward_recipient_reason.dart';
part 'input_field_forward_recipient_band_provenance.dart';
part 'input_field_attribution_parent_edge_ids.dart';

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
    final String field when field.isNotEmpty => _parseAsUtc(field),
    _ => null,
  };

  DateTime fromArgsNonNullable(Map<String, dynamic> args) =>
      _forceUtc(DateTime.parse(args[field.name]! as String));

  /// An offset-less ISO string (no trailing `Z`/`+HH:MM`) has no defined
  /// timezone. Rather than let [DateTime.tryParse] silently interpret it as
  /// wall-clock time in whatever zone this server process happens to run in
  /// (issue #112), treat the digits themselves as already being UTC — the
  /// same effect as if the caller had appended `Z`. This only changes
  /// behavior for malformed/offset-less input; a correctly UTC-tagged string
  /// (the only kind any current caller sends, after the client-side fix in
  /// this same issue) parses identically to before.
  DateTime? _parseAsUtc(String value) {
    final parsed = DateTime.tryParse(value);
    return parsed == null ? null : _forceUtc(parsed);
  }

  DateTime _forceUtc(DateTime parsed) => parsed.isUtc
      ? parsed
      : DateTime.utc(
          parsed.year,
          parsed.month,
          parsed.day,
          parsed.hour,
          parsed.minute,
          parsed.second,
          parsed.millisecond,
          parsed.microsecond,
        );
}

class InputFieldInt {
  InputFieldInt({required String fieldName})
    : fieldNullable = GraphQLFieldInput(
        fieldName,
        graphQLInt,
        defaultsToNull: true,
      ),
      fieldNonNullable = GraphQLFieldInput(
        fieldName,
        graphQLInt.nonNullable(),
      );

  final GraphQLFieldInput<int?, int?> fieldNullable;

  final GraphQLFieldInput<int, int> fieldNonNullable;

  int? fromArgs(Map<String, dynamic> args) {
    final raw = args[fieldNullable.name];
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString());
  }

  /// Required parser for [fieldNonNullable]; throws if absent/non-numeric.
  int fromArgsNonNullable(Map<String, dynamic> args) {
    final raw = args[fieldNonNullable.name];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    final parsed = raw == null ? null : int.tryParse(raw.toString());
    if (parsed == null) {
      throw ArgumentError.value(
        raw,
        fieldNonNullable.name,
        'required integer argument is missing or invalid',
      );
    }
    return parsed;
  }
}
