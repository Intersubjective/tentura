import 'package:injectable/injectable.dart';

import 'package:tentura/domain/use_case/use_case_base.dart';

import '../../data/repository/closure_repository.dart';
import '../entity/closure_outcome.dart';
import '../entity/closure_result.dart';
import '../entity/closure_state.dart';

@singleton
final class ClosureCase extends UseCaseBase {
  ClosureCase(
    this._repository, {
    required super.env,
    required super.logger,
  });

  final ClosureRepository _repository;

  Future<ClosureState> fetchState(String beaconId) =>
      _repository.fetchState(beaconId);

  Future<ClosureResult?> fetchResultForViewer(String beaconId) =>
      _repository.fetchResultForViewer(beaconId);

  Future<void> saveOutcome({
    required String beaconId,
    required int expectedEpoch,
    required String helperId,
    required ClosureOutcome? outcome,
  }) => _repository.saveOutcome(
    beaconId: beaconId,
    expectedEpoch: expectedEpoch,
    helperId: helperId,
    outcome: outcome,
  );

  Future<void> saveAuthorSplit({
    required String beaconId,
    required int expectedEpoch,
    required Map<String, int>? split,
  }) => _repository.saveAuthorSplit(
    beaconId: beaconId,
    expectedEpoch: expectedEpoch,
    split: split,
  );

  Future<String?> toggleSupport({
    required String beaconId,
    required int expectedEpoch,
    required String targetId,
    required bool on,
  }) => _repository.toggleSupport(
    beaconId: beaconId,
    expectedEpoch: expectedEpoch,
    targetId: targetId,
    on: on,
  );

  Future<void> done({required String beaconId, required int expectedEpoch}) =>
      _repository.done(beaconId: beaconId, expectedEpoch: expectedEpoch);

  Future<void> skip({required String beaconId, required int expectedEpoch}) =>
      _repository.skip(beaconId: beaconId, expectedEpoch: expectedEpoch);

  Future<void> setMark({
    required String beaconId,
    required int expectedEpoch,
    required String targetId,
    required bool on,
  }) => _repository.setMark(
    beaconId: beaconId,
    expectedEpoch: expectedEpoch,
    targetId: targetId,
    on: on,
  );

  Future<void> saveStory({
    required String beaconId,
    required int expectedEpoch,
    required String body,
  }) => _repository.saveStory(
    beaconId: beaconId,
    expectedEpoch: expectedEpoch,
    body: body,
  );

  Future<void> close(String beaconId) => _repository.close(beaconId);

  Future<void> closeNow({
    required String beaconId,
    required int expectedEpoch,
  }) => _repository.closeNow(beaconId: beaconId, expectedEpoch: expectedEpoch);

  Future<void> extendClosure({
    required String beaconId,
    required int expectedEpoch,
  }) => _repository.extendClosure(
    beaconId: beaconId,
    expectedEpoch: expectedEpoch,
  );

  Future<void> reopen({
    required String beaconId,
    required int expectedEpoch,
  }) => _repository.reopen(beaconId: beaconId, expectedEpoch: expectedEpoch);
}
