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

  Future<List<ViewerVisibleCapabilityRow>> fetchViewerVisible({
    required String viewerId,
    required String subjectId,
  }) => _repository.fetchDeduplicatedCapabilities(
    viewerId: viewerId,
    subjectId: subjectId,
  );

  Future<Map<String, List<String>>> fetchTopCapabilitiesBatch({
    required String viewerId,
    required List<String> subjectIds,
    int limit = 2,
  }) => _repository.fetchTopCapabilitiesBatch(
    viewerId: viewerId,
    subjectIds: subjectIds,
    limit: limit,
  );

  /// Atomically reconciles the full set of capabilities that [observerId] wants
  /// to see on [subjectId]'s profile.
  ///
  /// - Added slugs (in [slugs] but not in current private-label set): remove
  ///   tombstone + upsert private label.
  /// - Removed slugs (in current private-label set but not in [slugs]): soft-
  ///   delete private label + insert tombstone.
  /// - Slugs only visible through automatic sources (forward/commit/closeAck):
  ///   removing them creates a tombstone even if there was no private label.
  Future<void> setViewerVisible({
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

    final targetSet = slugs.toSet();

    // Delete tombstones for every slug the viewer wants visible (re-enables them).
    for (final slug in targetSet) {
      await _repository.deleteTombstone(
        observerId: observerId,
        subjectId: subjectId,
        slug: slug,
      );
    }

    // Update private labels: upserts new positives, soft-deletes removed ones.
    await _repository.upsertPrivateLabels(
      observerId: observerId,
      subjectId: subjectId,
      slugs: slugs,
    );

    // Fetch effective visible set (after tombstone-deletes and private-label upsert).
    // Anything still visible that the viewer didn't include in targetSet needs
    // a tombstone — this covers automatic slugs (commits, forwards, close-acks)
    // that the viewer is explicitly opting out of.
    final currentVisible = await _repository.fetchDeduplicatedCapabilities(
      viewerId: observerId,
      subjectId: subjectId,
    );
    final removed = currentVisible
        .map((r) => r.slug)
        .toSet()
        .difference(targetSet);
    for (final slug in removed) {
      await _repository.insertTombstone(
        observerId: observerId,
        subjectId: subjectId,
        slug: slug,
      );
    }
  }
}
