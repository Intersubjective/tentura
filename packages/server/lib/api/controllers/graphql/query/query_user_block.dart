import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_block_entity.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import '../mappers/gql_public_user_maps.dart';

/// User blocking queries — viewer id comes from JWT only.
final class QueryUserBlock extends GqlNodeBase {
  QueryUserBlock({
    UserBlockRepositoryPort? blockRepository,
    UserProfileBatchLookup? profileLookup,
  }) : _blocks = blockRepository ?? GetIt.I<UserBlockRepositoryPort>(),
       _profiles = profileLookup ?? GetIt.I<UserProfileBatchLookup>();

  final UserBlockRepositoryPort _blocks;
  final UserProfileBatchLookup _profiles;

  static final _objectId = InputFieldString(fieldName: 'objectId');
  static final _originId = InputFieldString(fieldName: 'originId');
  static final _cascadeMode = InputFieldInt(fieldName: 'cascadeMode');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    myBlocks,
    blockInherited,
    blockPreview,
  ];

  GraphQLObjectField<dynamic, dynamic> get myBlocks => GraphQLObjectField(
    'myBlocks',
    GraphQLListType(gqlTypeBlockIntent.nonNullable()),
    resolve: (_, args) async {
      final viewerId = getCredentials(args).sub;
      final intents = await _blocks.listIntents(viewerId);
      if (intents.isEmpty) {
        return <Map<String, dynamic>>[];
      }
      final blockedIds = intents.map((intent) => intent.blockedId);
      final profiles = await _profiles.userPublicRecordsByIds(
        ids: blockedIds,
        reciprocalPeerIds: const {},
      );
      final rows = <Map<String, dynamic>>[];
      for (final intent in intents) {
        final profile = profiles[intent.blockedId];
        if (profile == null) continue;
        rows.add(_blockIntentToGqlMap(intent: intent, profile: profile));
      }
      return rows;
    },
  );

  GraphQLObjectField<dynamic, dynamic> get blockInherited =>
      GraphQLObjectField(
        'blockInherited',
        GraphQLListType(gqlTypeUserPublic.nonNullable()),
        arguments: [_originId.field],
        resolve: (_, args) async {
          final viewerId = getCredentials(args).sub;
          final inherited = await _blocks.listInherited(
            blockerId: viewerId,
            originId: _originId.fromArgsNonNullable(args),
          );
          if (inherited.isEmpty) {
            return <Map<String, dynamic>>[];
          }
          final profiles = await _profiles.userPublicRecordsByIds(
            ids: inherited.map((row) => row.blockedId),
            reciprocalPeerIds: const {},
          );
          return [
            for (final row in inherited)
              if (profiles[row.blockedId] case final profile?)
                userPublicToGqlMap(profile),
          ];
        },
      );

  GraphQLObjectField<dynamic, dynamic> get blockPreview => GraphQLObjectField(
    'blockPreview',
    gqlTypeBlockPreview.nonNullable(),
    arguments: [_objectId.field, _cascadeMode.fieldNullable],
    resolve: (_, args) async {
      final viewerId = getCredentials(args).sub;
      final preview = await _blocks.preview(
        blockerId: viewerId,
        blockedId: _objectId.fromArgsNonNullable(args),
        cascadeMode: _cascadeMode.fromArgs(args) ?? 0,
      );
      return _blockPreviewToGqlMap(preview);
    },
  );
}

Map<String, dynamic> _blockIntentToGqlMap({
  required UserBlockIntentEntity intent,
  required UserPublicRecord profile,
}) =>
    {
      'blocked': userPublicToGqlMap(profile),
      'cascadeMode': intent.cascadeMode,
      'inheritedCount': intent.materializedCount,
      'cascadeCapped': intent.cascadeStatus == 3,
      'cascadePending': intent.cascadeStatus == 0 || intent.cascadeStatus == 1,
    };

Map<String, dynamic> _blockPreviewToGqlMap(BlockPreviewEntity preview) => {
  'cascadeCandidateCount': preview.cascadeCandidateCount,
  'cascadeCapped': preview.cascadeCapped,
  'openCommitmentCount': preview.openCommitmentCount,
  'willWithdrawEdge': preview.willWithdrawEdge,
};
