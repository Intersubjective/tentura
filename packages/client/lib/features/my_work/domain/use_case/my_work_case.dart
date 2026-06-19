import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';

import '../../data/repository/my_work_repository.dart';
import '../entity/my_work_card_view_model.dart';

@singleton
final class MyWorkCase extends UseCaseBase {
  MyWorkCase(
    this._repository,
    this._forwardRepository,
    this._beaconRepository,
    this._coordinationItemCase, {
    required super.env,
    required super.logger,
  });

  final MyWorkRepository _repository;

  final ForwardRepository _forwardRepository;

  final BeaconRepository _beaconRepository;

  final CoordinationItemCase _coordinationItemCase;

  Stream<RepositoryEvent<Beacon>> get beaconChanges => _beaconRepository.changes;

  Future<MyWorkInitResult> fetchInit({required String userId}) =>
      _repository.fetchInit(userId: userId);

  Future<MyWorkClosedResult> fetchClosed({required String userId}) =>
      _repository.fetchClosed(userId: userId);

  Future<bool> currentUserHasForwardedBeacon(String beaconId) =>
      _forwardRepository.currentUserHasForwardedBeacon(beaconId);

  Future<List<MyWorkCardViewModel>> attachLastActivityEvents(
    List<MyWorkCardViewModel> cards,
  ) async {
    if (cards.isEmpty) {
      return cards;
    }
    final byBeacon = await _repository.fetchLastActivityEventsByBeaconId(
      cards.map((c) => c.beaconId).toList(),
    );
    return [
      for (final card in cards)
        () {
          final last = byBeacon[card.beaconId];
          return last == null
              ? card
              : card.copyWith(lastActivityEvent: last);
        }(),
    ];
  }

  Future<List<MyWorkCardViewModel>> attachResponsibilityCounts(
    List<MyWorkCardViewModel> cards,
  ) async {
    if (cards.isEmpty) {
      return cards;
    }
    final byBeacon = await _coordinationItemCase.fetchResponsibilityBatch(
      cards.map((c) => c.beaconId).toList(),
    );
    return [
      for (final card in cards)
        card.copyWith(
          youResponsibility: byBeacon[card.beaconId] ??
              CoordinationResponsibility(beaconId: card.beaconId),
        ),
    ];
  }
}
