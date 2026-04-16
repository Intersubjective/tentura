import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';

import '../../data/repository/my_work_repository.dart';

@singleton
final class MyWorkCase extends UseCaseBase {
  MyWorkCase(
    this._repository,
    this._forwardRepository,
    this._beaconRepository, {
    required super.env,
    required super.logger,
  });

  final MyWorkRepository _repository;

  final ForwardRepository _forwardRepository;

  final BeaconRepository _beaconRepository;

  Stream<RepositoryEvent<Beacon>> get beaconChanges => _beaconRepository.changes;

  Future<MyWorkInitResult> fetchInit({required String userId}) =>
      _repository.fetchInit(userId: userId);

  Future<MyWorkClosedResult> fetchClosed({required String userId}) =>
      _repository.fetchClosed(userId: userId);

  Future<bool> currentUserHasForwardedBeacon(String beaconId) =>
      _forwardRepository.currentUserHasForwardedBeacon(beaconId);
}
