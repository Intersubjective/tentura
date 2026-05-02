import 'package:tentura/domain/capability/person_capability_cues.dart';

abstract class CapabilityRepositoryPort {
  Stream<void> get changes;

  Future<void> dispose();

  Future<List<String>> fetchMyPrivateLabelsForUser(String subjectId);

  Future<void> setPrivateLabels({
    required String subjectId,
    required List<String> slugs,
  });

  Future<PersonCapabilityCues> fetchCues(String subjectId);

  Future<void> setViewerVisible({
    required String subjectId,
    required List<String> slugs,
  });
}
