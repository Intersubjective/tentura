import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/beacon_room/domain/use_case/beacon_room_case.dart';

import '../../data/repository/inbox_repository.dart';
import '../entity/inbox_item.dart';
import '../enum.dart';

@singleton
final class InboxCase extends UseCaseBase {
  InboxCase(
    this._repository,
    this._beaconRoomCase, {
    required super.env,
    required super.logger,
  });

  final InboxRepository _repository;

  final BeaconRoomCase _beaconRoomCase;

  /// Inbox list refresh after local writes or session read-watermark changes.
  Stream<void> get localMutations => MergeStream<void>([
        _repository.localMutations,
        _beaconRoomCase.readWatermarkChanges.map((_) {}),
      ]);

  Future<List<InboxItem>> fetch({required String userId}) =>
      _repository.fetch(userId: userId);

  Future<void> setStatus({
    required String beaconId,
    required InboxItemStatus status,
    String rejectionMessage = '',
  }) =>
      _repository.setStatus(
        beaconId: beaconId,
        status: status,
        rejectionMessage: rejectionMessage,
      );

  Future<void> dismissTombstone({
    required String beaconId,
    DateTime? dismissedAt,
  }) =>
      _repository.dismissTombstone(
        beaconId: beaconId,
        dismissedAt: dismissedAt,
      );

  int resolveRoomUnread({
    required String beaconId,
    required int serverCount,
    required DateTime? serverSeenAt,
  }) =>
      _beaconRoomCase.resolveUnread(
        beaconId: beaconId,
        serverCount: serverCount,
        serverSeenAt: serverSeenAt,
      );
}
