/// Production discussion capability contract (General-only + supported kinds).
///
/// See `docs/plans/nested-requests-implementation-plan.md` §5.1 and
/// `docs/plans/nested-requests-architecture.md`. Future multi-thread product
/// exposure requires a new authorization/API review — do not widen through env
/// vars, GraphQL args, admin toggles, or client flags.
abstract class DiscussionProductPolicyPort {
  /// When true, only General (null thread scope) is a public conversation.
  bool get generalOnly;

  bool isDiscussionScopeEnabled({required String? threadScopeId});

  bool isCoordinationKindEnabled(int kind);
}
