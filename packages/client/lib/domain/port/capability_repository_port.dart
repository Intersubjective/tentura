import 'package:tentura/domain/capability/forward_band_row.dart';
import 'package:tentura/domain/capability/friend_context.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/capability/tag_projection.dart';

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

  Future<Map<String, List<String>>> fetchTopCapabilitiesBatch({
    required List<String> subjectIds,
    int limit = 2,
    List<String> prioritizeSlugs = const [],
  });

  Future<Map<String, FriendContext>> fetchFriendContextsBatch({
    required List<String> subjectIds,
  });

  Future<List<TagProjection>> fetchSubjectiveTags(String targetId);

  Future<List<ForwardBandRow>> fetchForwardContext({
    required String beaconId,
    String? context,
  });

  Future<List<String>> fetchMyRoutingTags();

  Future<String?> fetchTagExplanation({
    required String targetId,
    required String slug,
  });

  Future<void> seedRoutingAttestation({
    required String subjectId,
    required List<String> slugs,
  });

  Future<void> revokeAcknowledgement({
    required String beaconId,
    required String subjectId,
    required String slug,
  });

  Future<void> setRoutingMute({
    required String slug,
    required bool muted,
  });

  Future<InviteSeedPromptState> fetchInviteSeedPromptState(String subjectId);

  Future<void> inviteSeedPromptAnswer({
    required String subjectId,
    required List<String> slugs,
  });

  Future<void> inviteSeedPromptSkip(String subjectId);
}
