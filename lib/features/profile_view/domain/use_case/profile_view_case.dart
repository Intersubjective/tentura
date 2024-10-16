import 'package:injectable/injectable.dart';

import 'package:tentura/features/beacon/domain/entity/beacon.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/profile/domain/entity/profile.dart';

import '../../data/profile_view_repository.dart';

@lazySingleton
class ProfileViewCase {
  const ProfileViewCase(
    this._beaconRepository,
    this._likeRemoteRepository,
    this._profileViewRepository,
  );

  final BeaconRepository _beaconRepository;
  final LikeRemoteRepository _likeRemoteRepository;
  final ProfileViewRepository _profileViewRepository;

  Future<ProfileViewResult> fetchProfileWithBeaconsByUserId(
    String userId, {
    int limit = 3,
  }) =>
      _profileViewRepository.fetchByUserId(
        userId,
        limit: limit,
      );

  Future<Iterable<Beacon>> fetchBeaconsByUserId(String userId) =>
      _beaconRepository.fetchBeaconsByUserId(userId);

  Future<Profile> addFriend(Profile profile) =>
      _likeRemoteRepository.setLike<Profile>(profile, amount: 1);

  Future<Profile> removeFriend(Profile profile) =>
      _likeRemoteRepository.setLike<Profile>(profile, amount: 0);
}
