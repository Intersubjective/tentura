import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/domain/use_case/use_case_base.dart';

import '../../data/repository/inbox_repository.dart';
import '../entity/inbox_item.dart';
import '../enum.dart';

@singleton
final class InboxCase extends UseCaseBase {
  InboxCase(
    this._repository, {
    required super.env,
    required super.logger,
  });

  final InboxRepository _repository;

  Stream<void> get localMutations => _repository.localMutations;

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
}
