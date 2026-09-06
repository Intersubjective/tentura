import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/discussion_product_policy_port.dart';

/// Kind constants and helpers for discussion/coordination product policy.
///
/// Production servers compose [ProductionDiscussionProductPolicy] at startup
/// (see `packages/server/lib/app/di.dart`). Only direct unit/repository tests
/// may instantiate an internal multi-thread policy variant.
///
/// See `docs/plans/nested-requests-implementation-plan.md` §5.1 and
/// `docs/plans/nested-requests-architecture.md`. Future multi-thread exposure
/// requires a new authorization/API review.
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

  static bool isSupportedCoordinationKind(int kind) =>
      supportedCoordinationKinds.contains(kind);

  static bool isRetiredCoordinationKind(int kind) =>
      retiredCoordinationKinds.contains(kind);
}

/// Production General-only policy — always injected in deployed servers.
@Singleton(as: DiscussionProductPolicyPort)
final class ProductionDiscussionProductPolicy
    implements DiscussionProductPolicyPort {
  const ProductionDiscussionProductPolicy();

  @override
  bool get generalOnly => true;

  @override
  bool isDiscussionScopeEnabled({required String? threadScopeId}) =>
      threadScopeId == null || threadScopeId.isEmpty;

  @override
  bool isCoordinationKindEnabled(int kind) =>
      DiscussionProductPolicy.isSupportedCoordinationKind(kind);
}
