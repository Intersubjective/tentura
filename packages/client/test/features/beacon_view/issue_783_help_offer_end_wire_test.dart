// #783: a non-author's helpOffersWithCoordination row has no admission
// action. Stake, response and withdraw reason still travel on that
// operation, and the People label is read from them.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/help_offer_end.dart';
import 'package:tentura/features/beacon_view/data/repository/coordination_repository.dart';
import 'package:tentura/features/beacon_view/ui/bloc/timeline_help_offer_mapping.dart';
import 'package:tentura/ui/presenter/beacon_people_labels.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/remote_wire_harness.dart';

const _beaconId = 'B783wire00001';

Map<String, dynamic> _offerJson({
  required String userId,
  required String name,
  required int status,
  required int stakeState,
  int? responseType,
  int? admissionAction,
  String? withdrawReason,
}) => {
  '__typename': 'HelpOfferWithCoordinationRow',
  'beaconId': _beaconId,
  'userId': userId,
  'message': 'I can help',
  'helpType': null,
  'roleLabel': null,
  'status': status,
  'withdrawReason': withdrawReason,
  'createdAt': '2026-06-15T12:00:00.000Z',
  'updatedAt': '2026-06-15T12:00:00.000Z',
  'editedAt': null,
  'responseType': responseType,
  'responseUpdatedAt': null,
  'responseAuthorUserId': null,
  'roomAccess': 0,
  'admissionAction': admissionAction,
  'lastDeclineReason': null,
  'lastRemoveReason': null,
  'offerKind': 0,
  'stakeState': stakeState,
  'isDirectAuthorForward': false,
  'authorSeenAt': null,
  'user': {
    '__typename': 'User',
    'id': userId,
    'displayName': name,
    'description': '',
    'my_vote': null,
    'trusts_viewer': false,
    'is_mutual_friend': false,
    'image': null,
    'user_presence': null,
    'user_availability': null,
  },
};

void main() {
  test(
    'stripped offers query maps ended and declined, not withdrawn',
    () async {
      final sent = <WireSent>[];
      final en = lookupL10n(const Locale('en'));
      late Map<String, HelpOfferEndKind> kinds;

      await withRemoteWire(
        {
          'HelpOffersWithCoordination': {
            '__typename': 'query_root',
            'helpOffersWithCoordination': [
              // Non-author: admission cleared, stake released.
              _offerJson(
                userId: 'Uended0000001',
                name: 'Dave',
                status: 1,
                stakeState: CommitmentStakeState.released.index,
                responseType: 0,
              ),
              // Non-author: admission cleared, response notSuitable.
              _offerJson(
                userId: 'Udeclined0001',
                name: 'Bob',
                status: 1,
                stakeState: CommitmentStakeState.offered.index,
                responseType: 4,
              ),
              _offerJson(
                userId: 'Uwithdrew0001',
                name: 'Eve',
                status: 1,
                stakeState: CommitmentStakeState.exited.index,
                withdrawReason: 'other',
              ),
            ],
          },
        },
        sent,
        (remote) async {
          final rows = await CoordinationRepository(
            remote,
          ).fetchHelpOffersWithCoordination(beaconId: _beaconId);
          final offers = timelineHelpOffersFromRemote(rows);
          kinds = {
            for (final offer in offers)
              offer.user.displayName: helpOfferEndKind(
                isWithdrawn: offer.isWithdrawn,
                admissionAction: offer.admissionAction,
                stakeState: offer.stakeState,
                withdrawReason: offer.withdrawReason,
                coordinationResponse: offer.coordinationResponse,
              ),
          };
        },
      );

      expect(sent.single.operationName, 'HelpOffersWithCoordination');
      expect(sent.single.variables['beaconId'], _beaconId);
      final query = sent.single.operationName;
      expect(query, 'HelpOffersWithCoordination');

      expect(kinds['Dave'], HelpOfferEndKind.participationEnded);
      expect(kinds['Bob'], HelpOfferEndKind.declined);
      expect(kinds['Eve'], HelpOfferEndKind.withdrew);
      expect(
        helpOfferEndLabel(
          en,
          kinds['Dave']!,
          HelpOfferEndLabelSurface.peopleBadge,
        ),
        en.helpOfferParticipationEndedLabel,
      );
      expect(
        helpOfferEndLabel(
          en,
          kinds['Bob']!,
          HelpOfferEndLabelSurface.peopleBadge,
        ),
        en.helpOfferStatusDeclined,
      );
      expect(
        helpOfferEndLabel(
          en,
          kinds['Bob']!,
          HelpOfferEndLabelSurface.forwardRow,
        ),
        isNot(en.forwardWithdrawn),
      );
      expect(
        helpOfferEndLabel(
          en,
          kinds['Eve']!,
          HelpOfferEndLabelSurface.forwardRow,
        ),
        en.forwardWithdrawn,
      );
    },
  );
}
