import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/beacon_visibility.dart';

BeaconContentVisibilityFacts _content({
  BeaconStatus status = BeaconStatus.open,
  bool isAuthor = false,
  bool hasActiveForwardEdgeAsRecipient = false,
  bool isRoomAdmittedOrSteward = false,
  bool isActiveHelpOfferer = false,
  bool isMutualFriendOfAuthor = false,
}) =>
    BeaconContentVisibilityFacts(
      status: status,
      isAuthor: isAuthor,
      hasActiveForwardEdgeAsRecipient: hasActiveForwardEdgeAsRecipient,
      isRoomAdmittedOrSteward: isRoomAdmittedOrSteward,
      isActiveHelpOfferer: isActiveHelpOfferer,
      isMutualFriendOfAuthor: isMutualFriendOfAuthor,
    );

BeaconInvolvementVisibilityFacts _involvement({
  required BeaconContentVisibilityFacts contentFacts,
  bool isOnActiveForwardEdge = false,
  bool isActiveHelpOfferer = false,
  bool isRoomAdmittedOrSteward = false,
  bool isMutualFriendOfAuthor = false,
}) =>
    BeaconInvolvementVisibilityFacts(
      contentFacts: contentFacts,
      isOnActiveForwardEdge: isOnActiveForwardEdge,
      isActiveHelpOfferer: isActiveHelpOfferer,
      isRoomAdmittedOrSteward: isRoomAdmittedOrSteward,
      isMutualFriendOfAuthor: isMutualFriendOfAuthor,
    );

void main() {
  group('BeaconVisibility.canReadContent', () {
    test('author reads own draft/open/reviewOpen/closed/cancelled', () {
      for (final status in [
        BeaconStatus.draft,
        BeaconStatus.open,
        BeaconStatus.reviewOpen,
        BeaconStatus.closed,
        BeaconStatus.cancelled,
        BeaconStatus.needsMoreHelp,
      ]) {
        expect(
          BeaconVisibility.canReadContent(
            _content(status: status, isAuthor: true),
          ),
          isTrue,
          reason: 'author + $status',
        );
      }
    });

    test('author cannot read deleted content via content predicate', () {
      expect(
        BeaconVisibility.canReadContent(
          _content(status: BeaconStatus.deleted, isAuthor: true),
        ),
        isFalse,
      );
    });

    test('non-author cannot read draft or deleted', () {
      for (final status in [BeaconStatus.draft, BeaconStatus.deleted]) {
        expect(
          BeaconVisibility.canReadContent(_content(status: status)),
          isFalse,
          reason: 'non-author + $status',
        );
      }
    });

    test('active forward recipient reads open/closed/cancelled', () {
      for (final status in [
        BeaconStatus.open,
        BeaconStatus.closed,
        BeaconStatus.cancelled,
      ]) {
        expect(
          BeaconVisibility.canReadContent(
            _content(
              status: status,
              hasActiveForwardEdgeAsRecipient: true,
            ),
          ),
          isTrue,
          reason: 'forward recipient + $status',
        );
      }
    });

    test('sender-only forward edge does not grant content', () {
      expect(
        BeaconVisibility.canReadContent(_content()),
        isFalse,
      );
      expect(
        BeaconVisibility.canReadInvolvement(
          _involvement(
            contentFacts: _content(),
            isOnActiveForwardEdge: true,
          ),
        ),
        isFalse,
      );
    });

    test('mutual friend reads non-draft non-deleted beacons', () {
      expect(
        BeaconVisibility.canReadContent(
          _content(isMutualFriendOfAuthor: true),
        ),
        isTrue,
      );
      expect(
        BeaconVisibility.canReadContent(
          _content(
            status: BeaconStatus.draft,
            isMutualFriendOfAuthor: true,
          ),
        ),
        isFalse,
      );
    });

    test('one-way vote without mutual friendship reads nothing', () {
      expect(BeaconVisibility.canReadContent(_content()), isFalse);
    });

    test('active help-offerer reads content', () {
      expect(
        BeaconVisibility.canReadContent(
          _content(isActiveHelpOfferer: true),
        ),
        isTrue,
      );
    });

    test('withdrawn help offer alone does not grant content', () {
      expect(
        BeaconVisibility.canReadContent(
          _content(isActiveHelpOfferer: false),
        ),
        isFalse,
      );
    });

    test('room-admitted participant or steward reads content', () {
      expect(
        BeaconVisibility.canReadContent(
          _content(isRoomAdmittedOrSteward: true),
        ),
        isTrue,
      );
    });

    test('requested/invited room access alone does not grant content', () {
      expect(
        BeaconVisibility.canReadContent(
          _content(isRoomAdmittedOrSteward: false),
        ),
        isFalse,
      );
    });
  });

  group('BeaconVisibility.canReadInvolvement', () {
    test('forward recipient sees involvement', () {
      final content = _content(hasActiveForwardEdgeAsRecipient: true);
      expect(
        BeaconVisibility.canReadInvolvement(
          _involvement(
            contentFacts: content,
            isOnActiveForwardEdge: true,
          ),
        ),
        isTrue,
      );
    });

    test('mutual friend sees involvement when content visible', () {
      expect(
        BeaconVisibility.canReadInvolvement(
          _involvement(
            contentFacts: _content(isMutualFriendOfAuthor: true),
            isMutualFriendOfAuthor: true,
          ),
        ),
        isTrue,
      );
    });

    test('deleted beacon returns no involvement graph', () {
      expect(
        BeaconVisibility.canReadInvolvement(
          _involvement(
            contentFacts: _content(
              status: BeaconStatus.deleted,
              isAuthor: true,
            ),
            isOnActiveForwardEdge: true,
          ),
        ),
        isFalse,
      );
    });

    test('content-invisible viewer never sees involvement', () {
      expect(
        BeaconVisibility.canReadInvolvement(
          _involvement(
            contentFacts: _content(),
            isOnActiveForwardEdge: true,
            isMutualFriendOfAuthor: true,
          ),
        ),
        isFalse,
      );
    });
  });

  group('BeaconVisibility.canReadTombstone', () {
    test('non-deleted beacon never tombstones', () {
      expect(
        BeaconVisibility.canReadTombstone(
          const BeaconTombstoneFacts(
            status: BeaconStatus.open,
            isAuthor: true,
            hasInboxItem: true,
            hasForwardEdgeHistory: true,
            hasHelpOfferHistory: true,
            hasParticipantRow: true,
          ),
        ),
        isFalse,
      );
    });

    test('deleted beacon tombstone for author and durable rows', () {
      for (final facts in [
        const BeaconTombstoneFacts(
          status: BeaconStatus.deleted,
          isAuthor: true,
          hasInboxItem: false,
          hasForwardEdgeHistory: false,
          hasHelpOfferHistory: false,
          hasParticipantRow: false,
        ),
        const BeaconTombstoneFacts(
          status: BeaconStatus.deleted,
          isAuthor: false,
          hasInboxItem: true,
          hasForwardEdgeHistory: false,
          hasHelpOfferHistory: false,
          hasParticipantRow: false,
        ),
        const BeaconTombstoneFacts(
          status: BeaconStatus.deleted,
          isAuthor: false,
          hasInboxItem: false,
          hasForwardEdgeHistory: true,
          hasHelpOfferHistory: false,
          hasParticipantRow: false,
        ),
      ]) {
        expect(BeaconVisibility.canReadTombstone(facts), isTrue);
      }
    });

    test('deleted beacon with no durable row returns false', () {
      expect(
        BeaconVisibility.canReadTombstone(
          const BeaconTombstoneFacts(
            status: BeaconStatus.deleted,
            isAuthor: false,
            hasInboxItem: false,
            hasForwardEdgeHistory: false,
            hasHelpOfferHistory: false,
            hasParticipantRow: false,
          ),
        ),
        isFalse,
      );
    });
  });

  group('BeaconVisibility.canPreviewInvite', () {
    test('valid beacon invite preview', () {
      expect(
        BeaconVisibility.canPreviewInvite(
          const BeaconInvitePreviewFacts(
            invitationExists: true,
            invitationConsumed: false,
            invitationExpired: false,
            hasBeaconId: true,
            beaconStatus: BeaconStatus.open,
            beaconAllowsForward: true,
            issuerCanReadContent: true,
            issuerCanForward: true,
          ),
        ),
        isTrue,
      );
    });

    test('consumed/expired/missing beacon invite denied', () {
      for (final facts in [
        const BeaconInvitePreviewFacts(
          invitationExists: false,
          invitationConsumed: false,
          invitationExpired: false,
          hasBeaconId: true,
          beaconStatus: BeaconStatus.open,
          beaconAllowsForward: true,
          issuerCanReadContent: true,
          issuerCanForward: true,
        ),
        const BeaconInvitePreviewFacts(
          invitationExists: true,
          invitationConsumed: true,
          invitationExpired: false,
          hasBeaconId: true,
          beaconStatus: BeaconStatus.open,
          beaconAllowsForward: true,
          issuerCanReadContent: true,
          issuerCanForward: true,
        ),
        const BeaconInvitePreviewFacts(
          invitationExists: true,
          invitationConsumed: false,
          invitationExpired: true,
          hasBeaconId: true,
          beaconStatus: BeaconStatus.open,
          beaconAllowsForward: true,
          issuerCanReadContent: true,
          issuerCanForward: true,
        ),
      ]) {
        expect(BeaconVisibility.canPreviewInvite(facts), isFalse);
      }
    });

    test('draft/deleted/closed beacon invite denied', () {
      for (final status in [
        BeaconStatus.draft,
        BeaconStatus.deleted,
        BeaconStatus.closed,
        BeaconStatus.reviewOpen,
      ]) {
        expect(
          BeaconVisibility.canPreviewInvite(
            BeaconInvitePreviewFacts(
              invitationExists: true,
              invitationConsumed: false,
              invitationExpired: false,
              hasBeaconId: true,
              beaconStatus: status,
              beaconAllowsForward: status.allowsForward,
              issuerCanReadContent: true,
              issuerCanForward: status.allowsForward,
            ),
          ),
          isFalse,
          reason: '$status beacon invite',
        );
      }
    });

    test('issuer without read/forward rights denied', () {
      expect(
        BeaconVisibility.canPreviewInvite(
          const BeaconInvitePreviewFacts(
            invitationExists: true,
            invitationConsumed: false,
            invitationExpired: false,
            hasBeaconId: true,
            beaconStatus: BeaconStatus.open,
            beaconAllowsForward: true,
            issuerCanReadContent: false,
            issuerCanForward: true,
          ),
        ),
        isFalse,
      );
    });
  });
}
