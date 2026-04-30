import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_update_case.dart';
import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import '../mappers/beacon_author_update_maps.dart';
import '../mappers/gql_public_user_maps.dart';

final class MutationBeaconUpdate extends GqlNodeBase {
  MutationBeaconUpdate({
    BeaconUpdateCase? beaconUpdateCase,
    UserRepositoryPort? userRepository,
    VoteUserFriendshipLookup? voteUserFriendshipLookup,
  }) : _beaconUpdateCase = beaconUpdateCase ?? GetIt.I<BeaconUpdateCase>(),
       _userRepository = userRepository ?? GetIt.I<UserRepositoryPort>(),
       _voteUserFriendshipLookup =
           voteUserFriendshipLookup ?? GetIt.I<VoteUserFriendshipLookup>();

  final BeaconUpdateCase _beaconUpdateCase;

  final UserRepositoryPort _userRepository;

  final VoteUserFriendshipLookup _voteUserFriendshipLookup;

  final _beaconId = InputFieldString(fieldName: 'beaconId');
  final _content = InputFieldString(fieldName: 'content');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [updatePost, updateEdit];

  GraphQLObjectField<dynamic, dynamic> get updatePost => GraphQLObjectField(
    'beaconUpdatePost',
    gqlTypeBeaconAuthorUpdate.nonNullable(),
    arguments: [
      _beaconId.field,
      _content.field,
    ],
    resolve: (_, args) async {
      final userId = getCredentials(args).sub;
      final beaconId = _beaconId.fromArgsNonNullable(args);
      final content = _content.fromArgsNonNullable(args);
      final entity = await _beaconUpdateCase.post(
        userId: userId,
        beaconId: beaconId,
        content: content,
      );
      final author = await _userRepository.getById(entity.authorId);
      final friendship = userId == entity.authorId
          ? false
          : await _voteUserFriendshipLookup.isReciprocalSubscribe(
              viewerId: userId,
              peerId: entity.authorId,
            );
      return beaconAuthorUpdateToGqlMap(
        entity,
        userPublicToGqlMap(
          userEntityToPublicRecord(author, isMutualFriend: friendship),
        ),
      );
    },
  );

  GraphQLObjectField<dynamic, dynamic> get updateEdit => GraphQLObjectField(
    'beaconUpdateEdit',
    gqlTypeBeaconAuthorUpdate.nonNullable(),
    arguments: [
      InputFieldId.field,
      _content.field,
    ],
    resolve: (_, args) async {
      final userId = getCredentials(args).sub;
      final id = InputFieldId.fromArgsNonNullable(args);
      final content = _content.fromArgsNonNullable(args);
      final entity = await _beaconUpdateCase.edit(
        userId: userId,
        id: id,
        content: content,
      );
      final author = await _userRepository.getById(entity.authorId);
      final friendship = userId == entity.authorId
          ? false
          : await _voteUserFriendshipLookup.isReciprocalSubscribe(
              viewerId: userId,
              peerId: entity.authorId,
            );
      return beaconAuthorUpdateToGqlMap(
        entity,
        userPublicToGqlMap(
          userEntityToPublicRecord(author, isMutualFriend: friendship),
        ),
      );
    },
  );
}
