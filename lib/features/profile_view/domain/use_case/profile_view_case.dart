import 'package:injectable/injectable.dart';

import 'package:tentura/features/beacon/data/beacon_repository.dart';
import 'package:tentura/features/beacon/domain/entity/beacon.dart';

import '../../data/profile_view_repository.dart';

@lazySingleton
class ProfileViewCase {
  const ProfileViewCase(
    this._beaconRepository,
    this._profileViewRepository,
  );

  final BeaconRepository _beaconRepository;
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
}