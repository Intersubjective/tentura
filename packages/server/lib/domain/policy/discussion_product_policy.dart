/// Production discussion capability: General-only threads and supported kinds.
abstract final class DiscussionProductPolicy {
  DiscussionProductPolicy._();

  /// Persisted coordination kind codes — never renumber retired values.
  static const int kindPlan = 1;
  static const int kindAsk = 2;
  static const int kindBlocker = 3;
  static const int kindPromise = 5;

  static const Set<int> supportedCoordinationKinds = {kindPlan};

  static const Set<int> retiredCoordinationKinds = {
    kindAsk,
    kindBlocker,
    kindPromise,
  };

  /// Public product exposes only General (null thread scope).
  static const bool productionGeneralOnly = true;

  static bool isSupportedCoordinationKind(int kind) =>
      supportedCoordinationKinds.contains(kind);

  static bool isRetiredCoordinationKind(int kind) =>
      retiredCoordinationKinds.contains(kind);

  static bool isDiscussionScopeEnabled({required String? threadScopeId}) {
    if (!productionGeneralOnly) {
      return true;
    }
    return threadScopeId == null || threadScopeId.isEmpty;
  }

  static bool isCoordinationKindEnabled(int kind) =>
      isSupportedCoordinationKind(kind);
}
