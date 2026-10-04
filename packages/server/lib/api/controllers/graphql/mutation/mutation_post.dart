import 'dart:convert' show json;

import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationPost extends GqlNodeBase {
  MutationPost({PostCase? postCase})
    : _injectedPostCase = postCase;

  final PostCase? _injectedPostCase;

  /// Resolved lazily: the case is created asynchronously by DI.
  PostCase get _postCase => _injectedPostCase ?? GetIt.I<PostCase>();

  final _beaconId = InputFieldString(fieldName: 'id');

  final _body = InputFieldString(fieldName: 'body');

  static final _mentionUserIds = _optionalList('mentionUserIds', graphQLString);

  static final _mentionOffsets = _optionalList('mentionOffsets', graphQLInt);

  static final _mentionLengths = _optionalList('mentionLengths', graphQLInt);

  static GraphQLFieldInput<List<T>?, List<T>?> _optionalList<T>(
    String name,
    GraphQLType<T, T> element,
  ) => GraphQLFieldInput(
    name,
    _NullTolerantListType<T>(element.nonNullable()),
    defaultsToNull: true,
  );

  static List<T> _listFromArgs<T>(
    GraphQLFieldInput<List<T>?, List<T>?> input,
    Map<String, dynamic> args,
  ) => List<T>.from(args[input.name] as List<dynamic>? ?? const <dynamic>[]);

  static final _notes = GraphQLFieldInput(
    'notes',
    _NullTolerantStringType(),
    defaultsToNull: true,
  );

  final _forwardPolicy = InputFieldInt(fieldName: 'forwardPolicy');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [postPublish, postLeave, postReturn];

  GraphQLObjectField<dynamic, dynamic> get postLeave => GraphQLObjectField(
    'postLeave',
    graphQLBoolean.nonNullable(),
    arguments: [_beaconId.field],
    resolve: (_, args) async {
      await _postCase.leave(
        userId: getCredentials(args).sub,
        beaconId: _beaconId.fromArgsNonNullable(args),
      );
      return true;
    },
  );

  GraphQLObjectField<dynamic, dynamic> get postReturn => GraphQLObjectField(
    'postReturn',
    graphQLBoolean.nonNullable(),
    arguments: [_beaconId.field],
    resolve: (_, args) async {
      await _postCase.returnTo(
        userId: getCredentials(args).sub,
        beaconId: _beaconId.fromArgsNonNullable(args),
      );
      return true;
    },
  );

  GraphQLObjectField<dynamic, dynamic> get postPublish => GraphQLObjectField(
    'postPublish',
    gqlTypePostPublishResult.nonNullable(),
    arguments: [
      _beaconId.field,
      _body.field,
      _mentionUserIds,
      _mentionOffsets,
      _mentionLengths,
      InputFieldRecipientIds.field,
      _notes,
      _forwardPolicy.fieldNonNullable,
      InputFieldUpload.fieldNullable,
    ],
    resolve: (_, args) async {
      final uploadMeta = InputFieldUpload.uploadVariablesFromArgs(args);
      final rawName = uploadMeta?['filename'];
      final rawType = uploadMeta?['type'];
      final result = await _postCase.publish(
        authorId: getCredentials(args).sub,
        beaconId: _beaconId.fromArgsNonNullable(args),
        body: _body.fromArgs(args) ?? '',
        mentionUserIds: _listFromArgs(_mentionUserIds, args),
        mentionOffsets: _listFromArgs(_mentionOffsets, args),
        mentionLengths: _listFromArgs(_mentionLengths, args),
        recipientIds: InputFieldRecipientIds.fromArgs(args),
        notes: switch (args[_notes.name] as String?) {
          final String s when s.isNotEmpty => Map<String, String>.from(
            (json.decode(s) as Map).map(
              (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
            ),
          ),
          _ => const {},
        },
        forwardPolicy: BeaconForwardPolicyValue.fromValue(
          _forwardPolicy.fromArgsNonNullable(args),
        ),
        attachmentBytes: InputFieldUpload.fromArgs(args),
        attachmentFilename: rawName is String && rawName.trim().isNotEmpty
            ? rawName
            : null,
        attachmentMimeType: rawType is String && rawType.trim().isNotEmpty
            ? rawType
            : null,
      );
      return {
        'beaconId': result.beaconId,
        'rootMessageId': result.rootMessageId,
      };
    },
  );
}

/// List input where an unset variable (`null`) deserializes to an empty list.
final class _NullTolerantListType<T> extends GraphQLListType<T, T> {
  _NullTolerantListType(super.ofType);

  @override
  ValidationResult<List<T>> validate(String key, dynamic input) =>
      super.validate(key, input as List<dynamic>? ?? const <dynamic>[]);

  @override
  List<T> deserialize(List<dynamic>? serialized) =>
      super.deserialize(serialized ?? const <dynamic>[]);

  @override
  GraphQLType<List<T>, List<T>> coerceToInputObject() => this;
}

/// String input where an unset variable (`null`) deserializes to `''`.
final class _NullTolerantStringType extends GraphQLStringType {
  @override
  ValidationResult<String> validate(String key, dynamic input) =>
      super.validate(key, input ?? '');

  @override
  String deserialize(String? serialized) => serialized ?? '';
}
