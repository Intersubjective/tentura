import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/capability/capability_tag.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/person_capability_event_repository_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class CapabilityCase extends UseCaseBase {
  CapabilityCase(
    this._repository, {
    required super.env,
    required super.logger,
  });

  final PersonCapabilityEventRepositoryPort _repository;

  void _validateSlugs(List<String> slugs) {
    for (final slug in slugs) {
      if (!kAllowedCapabilitySlugs.contains(slug)) {
        throw ExceptionBase(
          code: const CapabilityExceptionCodes(CapabilityExceptionCode.invalidSlug),
          description: 'Unknown capability slug: $slug',
        );
      }
    }
  }

  Future<void> upsertPrivateLabel({
    required String observerId,
    required String subjectId,
    required List<String> slugs,
  }) async {
    if (observerId == subjectId) {
      throw const ExceptionBase(
        code: CapabilityExceptionCodes(
          CapabilityExceptionCode.selfLabelForbidden,
        ),
        description: 'Cannot label yourself',
      );
    }
    _validateSlugs(slugs);
    await _repository.upsertPrivateLabels(
      observerId: observerId,
      subjectId: subjectId,
      slugs: slugs,
    );
  }

  Future<List<String>> getPrivateLabelsForUser({
    required String observerId,
    required String subjectId,
  }) => _repository.fetchPrivateLabels(
    observerId: observerId,
    subjectId: subjectId,
  );

  Future<PersonCapabilityCuesRow> getCapabilityCues({
    required String viewerId,
    required String subjectId,
  }) => _repository.fetchCues(viewerId: viewerId, subjectId: subjectId);

  Future<void> recordForwardReasons({
    required String observerId,
    required String subjectId,
    required String beaconId,
    required List<String> slugs,
    String note = '',
  }) async {
    if (slugs.isEmpty) return;
    _validateSlugs(slugs);
    await _repository.insertForwardReasons(
      observerId: observerId,
      subjectId: subjectId,
      beaconId: beaconId,
      slugs: slugs,
      note: note,
    );
  }

  Future<void> recordCommitRole({
    required String observerId,
    required String subjectId,
    required String beaconId,
    required String slug,
  }) async {
    _validateSlugs([slug]);
    await _repository.insertCommitRole(
      observerId: observerId,
      subjectId: subjectId,
      beaconId: beaconId,
      slug: slug,
    );
  }

  Future<void> recordCloseAcknowledgement({
    required String observerId,
    required String subjectId,
    required String beaconId,
    required List<String> slugs,
  }) async {
    if (slugs.isEmpty) return;
    _validateSlugs(slugs);
    await _repository.insertCloseAcknowledgements(
      observerId: observerId,
      subjectId: subjectId,
      beaconId: beaconId,
      slugs: slugs,
    );
  }
}
