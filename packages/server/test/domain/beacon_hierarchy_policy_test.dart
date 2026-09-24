import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_delivery_direction.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_denial_code.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_status_transition.dart';

import 'package:tentura_server/domain/beacon_visibility.dart';
import 'package:tentura_server/domain/policy/beacon_hierarchy_policy.dart';
import 'package:tentura_server/domain/policy/discussion_product_policy.dart';


BeaconEffectiveAdmissionFacts _admission({
  bool isAuthor = false,
  bool isSteward = false,
  bool isAdmittedParticipant = false,
  bool isBlockedByOwner = false,
}) =>
    BeaconEffectiveAdmissionFacts(
      isAuthor: isAuthor,
      isSteward: isSteward,
      isAdmittedParticipant: isAdmittedParticipant,
      isBlockedByOwner: isBlockedByOwner,
    );

BeaconContentVisibilityFacts _content({
  BeaconStatus status = BeaconStatus.open,
  bool isAuthor = false,
  bool hasActiveForwardEdgeAsRecipient = false,
  bool isRoomAdmittedOrSteward = false,
  bool isActiveHelpOfferer = false,
  bool isDiscoverable = true,
  bool isPublished = true,
  bool isMutuallyVisibleWithAuthor = false,
}) =>
    BeaconContentVisibilityFacts(
      status: status,
      isAuthor: isAuthor,
      hasActiveForwardEdgeAsRecipient: hasActiveForwardEdgeAsRecipient,
      isRoomAdmittedOrSteward: isRoomAdmittedOrSteward,
      isActiveHelpOfferer: isActiveHelpOfferer,
      isDiscoverable: isDiscoverable,
      isPublished: isPublished,
      isMutuallyVisibleWithAuthor: isMutuallyVisibleWithAuthor,
    );

void main() {
  group('DiscussionProductPolicy reserved kind values', () {
    test('matches live persisted coordination kind codes', () {
      expect(DiscussionProductPolicy.kindPlan, 1);
      expect(DiscussionProductPolicy.kindAsk, 2);
      expect(DiscussionProductPolicy.kindBlocker, 3);
      expect(DiscussionProductPolicy.kindPromise, 5);
      expect(DiscussionProductPolicy.supportedCoordinationKinds, {1});
      expect(DiscussionProductPolicy.retiredCoordinationKinds, {2, 3, 5});
    });

    test('rejects non-General scope in production', () {
      const policy = ProductionDiscussionProductPolicy();
      expect(policy.generalOnly, isTrue);
      expect(
        policy.isDiscussionScopeEnabled(threadScopeId: null),
        isTrue,
      );
      expect(
        policy.isDiscussionScopeEnabled(threadScopeId: ''),
        isTrue,
      );
      expect(
        policy.isDiscussionScopeEnabled(threadScopeId: 'thread-1'),
        isFalse,
      );
    });
  });

  group('BeaconHierarchyPolicy capabilities and parent reference', () {
    test('stranger who cannot read parent content cannot list or create', () {
      final caps = BeaconHierarchyPolicy.resolveCapabilities(
        BeaconHierarchyCapabilityFacts(
          admission: _admission(),
          parentStatus: BeaconStatus.open,
          parentHasKnownOwner: true,
          viewerCanReadParentContent: false,
        ),
      );
      expect(caps.canListChildren, isFalse);
      expect(caps.canCreateChild, isFalse);
      expect(caps.denialCode, BeaconHierarchyDenialCode.notAdmitted);
    });

    test('observer who reads parent content can list but not create', () {
      final caps = BeaconHierarchyPolicy.resolveCapabilities(
        BeaconHierarchyCapabilityFacts(
          admission: _admission(),
          parentStatus: BeaconStatus.open,
          parentHasKnownOwner: true,
          viewerCanReadParentContent: true,
        ),
      );
      expect(caps.canListChildren, isTrue);
      expect(caps.canCreateChild, isFalse);
      expect(caps.denialCode, BeaconHierarchyDenialCode.notAdmitted);
    });

    test('draft and deleted parents deny observers before admission', () {
      for (final (status, code) in [
        (BeaconStatus.draft, BeaconHierarchyDenialCode.parentDraft),
        (BeaconStatus.deleted, BeaconHierarchyDenialCode.parentDeleted),
      ]) {
        final caps = BeaconHierarchyPolicy.resolveCapabilities(
          BeaconHierarchyCapabilityFacts(
            admission: _admission(),
            parentStatus: status,
            parentHasKnownOwner: true,
            viewerCanReadParentContent: true,
          ),
        );
        expect(caps.canListChildren, isFalse, reason: '$status');
        expect(caps.canCreateChild, isFalse, reason: '$status');
        expect(caps.denialCode, code, reason: '$status');
      }
    });

    test('admitted eligible parent lists but terminal parent denies create', () {
      final openCaps = BeaconHierarchyPolicy.resolveCapabilities(
        BeaconHierarchyCapabilityFacts(
          admission: _admission(isAdmittedParticipant: true),
          parentStatus: BeaconStatus.open,
          parentHasKnownOwner: true,
          viewerCanReadParentContent: true,
        ),
      );
      expect(openCaps.canListChildren, isTrue);
      expect(openCaps.canCreateChild, isTrue);
      expect(openCaps.denialCode, isNull);

      final closedCaps = BeaconHierarchyPolicy.resolveCapabilities(
        BeaconHierarchyCapabilityFacts(
          admission: _admission(isAdmittedParticipant: true),
          parentStatus: BeaconStatus.closed,
          parentHasKnownOwner: true,
          viewerCanReadParentContent: true,
        ),
      );
      expect(closedCaps.canListChildren, isTrue);
      expect(closedCaps.canCreateChild, isFalse);
      expect(closedCaps.denialCode, BeaconHierarchyDenialCode.parentTerminal);
    });

    test('parent reference states follow authorization matrix', () {
      expect(
        BeaconHierarchyPolicy.resolveParentReference(
          const BeaconParentReferenceFacts(hasParent: false),
        ),
        BeaconParentReference.none,
      );
      expect(
        BeaconHierarchyPolicy.resolveParentReference(
          const BeaconParentReferenceFacts(
            hasParent: true,
            parentStatus: BeaconStatus.deleted,
            parentLinkedDetailAuthorized: true,
            parentBeaconId: 'P',
            parentTitle: 'Parent',
          ),
        ).state,
        BeaconParentReferenceState.unavailable,
      );
      final available = BeaconHierarchyPolicy.resolveParentReference(
        const BeaconParentReferenceFacts(
          hasParent: true,
          parentStatus: BeaconStatus.open,
          parentLinkedDetailAuthorized: true,
          parentBeaconId: 'P',
          parentTitle: 'Parent',
        ),
      );
      expect(available.state, BeaconParentReferenceState.available);
      expect(available.beaconId, 'P');
      expect(available.title, 'Parent');
    });
  });

  group('BeaconHierarchyPolicy lifecycle eligibility §4.3', () {
    test('eligible transitions emit notices for wrapping up/closed/cancelled/deleted',
        () {
      for (final to in [
        BeaconStatus.reviewOpen,
        BeaconStatus.closed,
        BeaconStatus.cancelled,
        BeaconStatus.deleted,
      ]) {
        expect(
          BeaconHierarchyPolicy.isHierarchyLifecycleNoticeEligible(
            from: BeaconStatus.open,
            to: to,
          ),
          isTrue,
          reason: 'open -> $to',
        );
      }
    });

    test('no-op and draft paths do not emit notices', () {
      expect(
        BeaconHierarchyPolicy.isHierarchyLifecycleNoticeEligible(
          from: BeaconStatus.open,
          to: BeaconStatus.open,
        ),
        isFalse,
      );
      expect(
        BeaconHierarchyPolicy.isHierarchyLifecycleNoticeEligible(
          from: BeaconStatus.draft,
          to: BeaconStatus.deleted,
        ),
        isFalse,
      );
    });

    test('local reopen and open-family coordination do not emit notices', () {
      expect(
        BeaconHierarchyPolicy.isHierarchyLifecycleNoticeEligible(
          from: BeaconStatus.reviewOpen,
          to: BeaconStatus.open,
          reason: BeaconStatusTransitionReason.reopenedFromReview,
        ),
        isFalse,
      );
      expect(
        BeaconHierarchyPolicy.isHierarchyLifecycleNoticeEligible(
          from: BeaconStatus.open,
          to: BeaconStatus.needsMoreHelp,
        ),
        isFalse,
      );
      expect(
        BeaconHierarchyPolicy.isHierarchyLifecycleNoticeEligible(
          from: BeaconStatus.draft,
          to: BeaconStatus.open,
          reason: BeaconStatusTransitionReason.publish,
        ),
        isFalse,
      );
    });

    test('wrapping up then closed are separate eligible events', () {
      expect(
        BeaconHierarchyPolicy.isHierarchyLifecycleNoticeEligible(
          from: BeaconStatus.open,
          to: BeaconStatus.reviewOpen,
          reason: BeaconStatusTransitionReason.reviewWindowOpened,
        ),
        isTrue,
      );
      expect(
        BeaconHierarchyPolicy.isHierarchyLifecycleNoticeEligible(
          from: BeaconStatus.reviewOpen,
          to: BeaconStatus.closed,
          reason: BeaconStatusTransitionReason.reviewExpired,
        ),
        isTrue,
      );
    });

    test('delivery direction distinguishes parent and descendants', () {
      expect(
        BeaconHierarchyPolicy.deliveryDirectionForTarget(
          targetIsImmediateParentOfSource: true,
        ),
        BeaconHierarchyDeliveryDirection.child,
      );
      expect(
        BeaconHierarchyPolicy.deliveryDirectionForTarget(
          targetIsImmediateParentOfSource: false,
        ),
        BeaconHierarchyDeliveryDirection.ancestor,
      );
    });
  });

  group('BeaconHierarchyPolicy deleted child tombstone', () {
    test('deleted child tombstone card uses parent admission without content', () {
      expect(
        BeaconHierarchyPolicy.canReadDeletedChildTombstoneCard(
          viewerAdmittedToImmediateParent: true,
          isBlockedByKnownChildOwner: false,
        ),
        isTrue,
      );
      expect(
        BeaconVisibility.canReadContent(
          _content(status: BeaconStatus.deleted),
        ),
        isFalse,
      );
    });
  });
}
