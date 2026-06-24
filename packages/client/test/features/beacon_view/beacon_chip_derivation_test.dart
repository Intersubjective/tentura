import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_chip_derivation.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

void main() {
  final l10n = lookupL10n(const Locale('en'));
  final t = DateTime.utc(2026, 6, 20, 12);

  TimelineHelpOffer helpOffer({
    bool withdrawn = false,
    CoordinationResponseType? response,
    String? helpType,
    String userId = 'u1',
  }) =>
      TimelineHelpOffer(
        user: Profile(id: userId),
        message: 'msg',
        createdAt: t,
        updatedAt: t,
        isWithdrawn: withdrawn,
        coordinationResponse: response,
        helpType: helpType,
      );

  ForwardEdge forwardEdge({
    required String senderId,
    required String recipientId,
  }) =>
      ForwardEdge(
        id: 'f-$senderId-$recipientId',
        beaconId: 'b1',
        createdAt: t,
        sender: Profile(id: senderId),
        recipient: Profile(id: recipientId),
      );

  group('counts', () {
    test('activeHelpOfferCount ignores withdrawn offers', () {
      final offers = [
        helpOffer(),
        helpOffer(withdrawn: true),
        helpOffer(userId: 'u2'),
      ];
      expect(activeHelpOfferCount(offers), 2);
      expect(withdrawnHelpOfferCount(offers), 1);
    });

    test('usefulHelpOfferCount counts only non-withdrawn useful responses', () {
      final offers = [
        helpOffer(response: CoordinationResponseType.useful),
        helpOffer(response: CoordinationResponseType.notSuitable),
        helpOffer(
          response: CoordinationResponseType.useful,
          withdrawn: true,
        ),
      ];
      expect(usefulHelpOfferCount(offers), 1);
    });

    test('distinctForwarderCountTowardViewer deduplicates senders', () {
      expect(
        distinctForwarderCountTowardViewer(
          viewerForwardEdges: [
            forwardEdge(senderId: 'a', recipientId: 'me'),
            forwardEdge(senderId: 'a', recipientId: 'me'),
            forwardEdge(senderId: 'b', recipientId: 'me'),
            forwardEdge(senderId: 'c', recipientId: 'other'),
          ],
          myUserId: 'me',
        ),
        2,
      );
    });
  });

  group('firstParagraphNeedLine', () {
    test('returns null for empty description', () {
      expect(firstParagraphNeedLine(Beacon.empty), isNull);
    });

    test('returns first line before newline', () {
      final beacon = Beacon.empty.copyWith(
        description: 'Need wiring help\nSecond paragraph',
      );
      expect(firstParagraphNeedLine(beacon), 'Need wiring help');
    });

    test('returns whole description when no newline', () {
      final beacon = Beacon.empty.copyWith(description: 'Single line need');
      expect(firstParagraphNeedLine(beacon), 'Single line need');
    });
  });

  group('deriveSupportingChips', () {
    test('includes help offer, useful, and deadline chips for author view', () {
      final endAt = DateTime.utc(2026, 7, 1);
      final chips = deriveSupportingChips(
        l10n: l10n,
        beacon: Beacon.empty.copyWith(
          endAt: endAt,
          status: BeaconStatus.open,
        ),
        helpOffers: [
          helpOffer(response: CoordinationResponseType.useful),
          helpOffer(userId: 'u2'),
        ],
        viewerForwardEdges: const [],
        myUserId: 'author',
        isAuthorView: true,
      );

      expect(
        chips.map((c) => c.label),
        containsAll([
          l10n.beaconChipHelpOffersCount(2),
          l10n.beaconChipUsefulCount(1),
          l10n.beaconChipDeadlineOn(dateFormatYMD(endAt)),
        ]),
      );
      expect(chips.last.emphasized, isTrue);
    });

    test('shows more help needed chip when coordination status requires it', () {
      final chips = deriveSupportingChips(
        l10n: l10n,
        beacon: Beacon.empty.copyWith(
          status: BeaconStatus.needsMoreHelp,
        ),
        helpOffers: const [],
        viewerForwardEdges: const [],
        myUserId: 'author',
        isAuthorView: true,
      );

      expect(chips, hasLength(1));
      expect(chips.single.label, l10n.beaconChipMoreHelpNeeded);
      expect(chips.single.emphasized, isTrue);
    });

    test('shows forwarded-by chip for non-author when edges point to viewer', () {
      final chips = deriveSupportingChips(
        l10n: l10n,
        beacon: Beacon.empty.copyWith(status: BeaconStatus.open),
        helpOffers: const [],
        viewerForwardEdges: [
          forwardEdge(senderId: 'friend', recipientId: 'me'),
        ],
        myUserId: 'me',
        isAuthorView: false,
      );

      expect(
        chips.map((c) => c.label),
        contains(l10n.beaconChipForwardedBy(1)),
      );
    });

    test('shows you-forwarded chip for author on open beacon', () {
      final chips = deriveSupportingChips(
        l10n: l10n,
        beacon: Beacon.empty.copyWith(status: BeaconStatus.open),
        helpOffers: const [],
        viewerForwardEdges: [
          forwardEdge(senderId: 'author', recipientId: 'peer'),
          forwardEdge(senderId: 'author', recipientId: 'peer2'),
        ],
        myUserId: 'author',
        isAuthorView: true,
      );

      expect(
        chips.map((c) => c.label),
        contains(l10n.beaconChipYouForwarded(2)),
      );
    });
  });
}
