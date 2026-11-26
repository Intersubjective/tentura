import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura_server/domain/use_case/phantom_case.dart';
import 'package:tentura_server/domain/use_case/phantom_merge_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationPhantom extends GqlNodeBase {
  const MutationPhantom();

  PhantomCase get _case => GetIt.I<PhantomCase>();

  static final _id = InputFieldString(fieldName: 'id');
  static final _name = InputFieldString(fieldName: 'name');
  static final _emoji = InputFieldString(fieldName: 'emoji');
  static final _phantomId = InputFieldString(fieldName: 'phantomId');
  static final _beaconId = InputFieldString(fieldName: 'beaconId');
  static final _note = InputFieldString(fieldName: 'note');
  static final _mergeId = InputFieldString(fieldName: 'mergeId');
  static final _userId = InputFieldString(fieldName: 'userId');
  static final _position = GraphQLFieldInput(
    'position',
    gqlInputConstellationAnchorPosition,
  );

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    GraphQLObjectField(
      'phantomCreate',
      graphQLString.nonNullable(),
      arguments: [_name.field, _emoji.fieldNullable, _position],
      resolve: (_, args) async => _case.create(
        ownerId: getCredentials(args).sub,
        name: _name.fromArgsNonNullable(args),
        emoji: _emoji.fromArgs(args),
        position: _readPosition(args),
      ),
    ),
    GraphQLObjectField(
      'phantomUpdate',
      graphQLBoolean.nonNullable(),
      arguments: [_id.field, _name.field, _emoji.fieldNullable],
      resolve: (_, args) async => _case.update(
        ownerId: getCredentials(args).sub,
        id: _id.fromArgsNonNullable(args),
        name: _name.fromArgsNonNullable(args),
        emoji: _emoji.fromArgs(args),
      ),
    ),
    GraphQLObjectField(
      'phantomDelete',
      graphQLBoolean.nonNullable(),
      arguments: [_id.field],
      resolve: (_, args) => _case.delete(
        ownerId: getCredentials(args).sub,
        id: _id.fromArgsNonNullable(args),
      ),
    ),
    GraphQLObjectField(
      'phantomInviteEnsure',
      graphQLString.nonNullable(),
      arguments: [_id.field],
      resolve: (_, args) => _case.saveInvite(
        ownerId: getCredentials(args).sub,
        id: _id.fromArgsNonNullable(args),
        rotate: false,
      ),
    ),
    GraphQLObjectField(
      'phantomInviteRotate',
      graphQLString.nonNullable(),
      arguments: [_id.field],
      resolve: (_, args) => _case.saveInvite(
        ownerId: getCredentials(args).sub,
        id: _id.fromArgsNonNullable(args),
        rotate: true,
      ),
    ),
    GraphQLObjectField(
      'beaconForwardToPhantom',
      graphQLString.nonNullable(),
      arguments: [_beaconId.field, _phantomId.field, _note.fieldNullable],
      resolve: (_, args) async {
        final beaconId = _beaconId.fromArgsNonNullable(args);
        final code = await _case.forwardRequest(
          ownerId: getCredentials(args).sub,
          phantomId: _phantomId.fromArgsNonNullable(args),
          beaconId: beaconId,
          note: _note.fromArgs(args) ?? '',
        );
        return Uri(
          pathSegments: ['', 'invite', code],
          queryParameters: {'r': beaconId},
        ).toString();
      },
    ),
    GraphQLObjectField(
      'phantomLink',
      graphQLBoolean.nonNullable(),
      arguments: [_phantomId.field, _userId.field],
      resolve: (_, args) => GetIt.I<PhantomMergeCase>().link(
        ownerId: getCredentials(args).sub,
        phantomId: _phantomId.fromArgsNonNullable(args),
        userId: _userId.fromArgsNonNullable(args),
      ),
    ),
    GraphQLObjectField(
      'phantomUnmerge',
      graphQLBoolean.nonNullable(),
      arguments: [_phantomId.field, _mergeId.fieldNullable],
      resolve: (_, args) => GetIt.I<PhantomMergeCase>().unmerge(
        ownerId: getCredentials(args).sub,
        phantomId: _phantomId.fromArgsNonNullable(args),
        mergeId: _mergeId.fromArgs(args),
      ),
    ),
    GraphQLObjectField(
      'phantomHintDismiss',
      graphQLBoolean.nonNullable(),
      arguments: [_phantomId.field, _userId.field],
      resolve: (_, args) => _case.dismissLinkHint(
        ownerId: getCredentials(args).sub,
        phantomId: _phantomId.fromArgsNonNullable(args),
        userId: _userId.fromArgsNonNullable(args),
      ),
    ),
  ];

  static ConstellationAnchorPosition? _readPosition(
    Map<String, dynamic> args,
  ) => switch (args[_position.name]) {
    null => null,
    {
      'xUnits': final num x,
      'yUnits': final num y,
      'coordinateSpaceVersion': final int version,
    } =>
      ConstellationAnchorCase.parsePosition(
        xUnits: x.toDouble(),
        yUnits: y.toDouble(),
        coordinateSpaceVersion: version,
      ),
    _ => throw ConstellationException(
      constellationCode: ConstellationExceptionCode.invalidCoordinates,
    ),
  };
}
