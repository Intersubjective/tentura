import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/person_capability_event_repository_port.dart';

@Injectable(
  as: PersonCapabilityEventRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class PersonCapabilityEventRepositoryMock
    implements PersonCapabilityEventRepositoryPort {
  @override
  Future<void> upsertPrivateLabels({
    required String observerId,
    required String subjectId,
    required List<String> slugs,
  }) => Future.value();

  @override
  Future<List<String>> fetchPrivateLabels({
    required String observerId,
    required String subjectId,
  }) => Future.value(const []);

  @override
  Future<void> insertForwardReasons({
    required String observerId,
    required String subjectId,
    required String beaconId,
    required List<String> slugs,
    String note = '',
  }) => Future.value();

  @override
  Future<void> insertCommitRole({
    required String observerId,
    required String subjectId,
    required String beaconId,
    required String slug,
  }) => Future.value();

  @override
  Future<void> insertCloseAcknowledgements({
    required String observerId,
    required String subjectId,
    required String beaconId,
    required List<String> slugs,
  }) => Future.value();

  @override
  Future<PersonCapabilityCuesRow> fetchCues({
    required String viewerId,
    required String subjectId,
  }) => Future.value(
    const PersonCapabilityCuesRow(
      privateLabels: [],
      forwardReasonsByMe: [],
      closeAckByMe: [],
      closeAckAboutMe: [],
    ),
  );

  @override
  Future<void> insertTombstone({
    required String observerId,
    required String subjectId,
    required String slug,
  }) => Future.value();

  @override
  Future<void> deleteTombstone({
    required String observerId,
    required String subjectId,
    required String slug,
  }) => Future.value();

  @override
  Future<List<ViewerVisibleCapabilityRow>> fetchDeduplicatedCapabilities({
    required String viewerId,
    required String subjectId,
  }) => Future.value(const []);

  @override
  Future<Map<String, List<String>>> fetchTopCapabilitiesBatch({
    required String viewerId,
    required List<String> subjectIds,
    int limit = 2,
    List<String> prioritizeSlugs = const [],
  }) => Future.value(const {});

  @override
  Future<List<ForwardReasonRow>> fetchForwardReasonsByBeaconId({
    required String beaconId,
    required String viewerId,
  }) => Future.value(const []);

  @override
  Future<List<FriendContextRow>> fetchFriendContextsBatch({
    required String viewerId,
    required List<String> friendIds,
  }) => Future.value(const []);
}
