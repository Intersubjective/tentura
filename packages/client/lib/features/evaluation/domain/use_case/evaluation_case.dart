import 'package:injectable/injectable.dart';

import 'package:tentura/domain/use_case/use_case_base.dart';

import '../../data/repository/evaluation_repository.dart';
import '../entity/evaluation_participant.dart';
import '../entity/evaluation_summary.dart';
import '../entity/review_window_info.dart';

@singleton
final class EvaluationCase extends UseCaseBase {
  EvaluationCase(
    this._repository, {
    required super.env,
    required super.logger,
  });

  final EvaluationRepository _repository;

  Future<ReviewWindowInfo> fetchReviewWindowStatus(String beaconId) =>
      _repository.fetchReviewWindowStatus(beaconId);

  Future<List<EvaluationParticipant>> fetchParticipants(String beaconId) =>
      _repository.fetchParticipants(beaconId);

  Future<EvaluationSummary> fetchSummary(String beaconId) =>
      _repository.fetchSummary(beaconId);

  Future<({ReviewWindowInfo window, List<EvaluationParticipant> participants})>
      fetchDraftModeBootstrap(String beaconId) =>
          _repository.fetchDraftModeBootstrap(beaconId);

  Future<List<EvaluationParticipant>> fetchDraftParticipants(String beaconId) =>
      _repository.fetchDraftParticipants(beaconId);

  Future<void> draftSave({
    required String beaconId,
    required String evaluatedUserId,
    required int value,
    List<String> reasonTags = const [],
    String note = '',
  }) =>
      _repository.draftSave(
        beaconId: beaconId,
        evaluatedUserId: evaluatedUserId,
        value: value,
        reasonTags: reasonTags,
        note: note,
      );

  Future<void> submit({
    required String beaconId,
    required String evaluatedUserId,
    required int value,
    List<String> reasonTags = const [],
    String note = '',
  }) =>
      _repository.submit(
        beaconId: beaconId,
        evaluatedUserId: evaluatedUserId,
        value: value,
        reasonTags: reasonTags,
        note: note,
      );

  Future<void> finalize(String beaconId) => _repository.finalize(beaconId);

  Future<void> skip(String beaconId) => _repository.skip(beaconId);
}
