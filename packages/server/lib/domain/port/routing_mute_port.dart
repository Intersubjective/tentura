abstract interface class RoutingMutePort {
  /// Subject-keyed mute map: each subject's muted routing slugs.
  Future<Map<String, Set<String>>> mutedSlugsFor({
    required List<String> subjectIds,
  });

  Future<Set<String>> mutedSlugsForUser(String userId);

  Future<void> setMute({
    required String userId,
    required String tagSlug,
    required bool muted,
  });

  /// Population-wide mute counts keyed by tag slug (routing mute screen).
  Future<Map<String, int>> muteCountsByTag();
}
