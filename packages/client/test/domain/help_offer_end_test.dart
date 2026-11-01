import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/help_offer_end.dart';
import 'package:tentura/ui/presenter/beacon_people_labels.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  final en = lookupL10n(const Locale('en'));
  final ru = lookupL10n(const Locale('ru'));

  test('author fields and a stripped non-author row name the same end', () {
    final cases =
        <
          ({
            String name,
            HelpOfferEndKind kind,
            bool isWithdrawn,
            HelpOfferAdmissionAction? admission,
            CommitmentStakeState stake,
            String? reason,
            CoordinationResponseType? response,
          })
        >[
          (
            name: 'helper withdrew',
            kind: HelpOfferEndKind.withdrew,
            isWithdrawn: true,
            admission: null,
            stake: CommitmentStakeState.exited,
            reason: 'other',
            response: null,
          ),
          (
            name: 'author ended participation',
            kind: HelpOfferEndKind.participationEnded,
            isWithdrawn: false,
            admission: HelpOfferAdmissionAction.remove,
            stake: CommitmentStakeState.released,
            reason: null,
            response: CoordinationResponseType.useful,
          ),
          (
            name: 'non-author sees participation ended',
            kind: HelpOfferEndKind.participationEnded,
            isWithdrawn: true,
            admission: null,
            stake: CommitmentStakeState.released,
            reason: null,
            response: CoordinationResponseType.useful,
          ),
          (
            name: 'author declined a pending offer',
            kind: HelpOfferEndKind.declined,
            isWithdrawn: true,
            admission: HelpOfferAdmissionAction.decline,
            stake: CommitmentStakeState.offered,
            reason: null,
            response: CoordinationResponseType.notSuitable,
          ),
          (
            name: 'non-author sees the decline',
            kind: HelpOfferEndKind.declined,
            isWithdrawn: true,
            admission: null,
            stake: CommitmentStakeState.offered,
            reason: null,
            response: CoordinationResponseType.notSuitable,
          ),
          (
            name: 'removed from the discussion, admission stripped',
            kind: HelpOfferEndKind.participationEnded,
            isWithdrawn: true,
            admission: null,
            stake: CommitmentStakeState.acknowledged,
            reason: null,
            response: CoordinationResponseType.useful,
          ),
        ];

    for (final c in cases) {
      expect(
        helpOfferEndKind(
          isWithdrawn: c.isWithdrawn,
          admissionAction: c.admission,
          stakeState: c.stake,
          withdrawReason: c.reason,
          coordinationResponse: c.response,
        ),
        c.kind,
        reason: c.name,
      );
    }
  });

  test('a later withdrawal after removal is a withdrawal', () {
    expect(
      helpOfferEndKind(
        isWithdrawn: true,
        admissionAction: HelpOfferAdmissionAction.remove,
        stakeState: CommitmentStakeState.exited,
        withdrawReason: 'other',
      ),
      HelpOfferEndKind.withdrew,
    );
  });

  test('an active re-offer keeps a stale decline admission (#708)', () {
    expect(
      helpOfferEndKind(
        isWithdrawn: false,
        admissionAction: HelpOfferAdmissionAction.decline,
        coordinationResponse: CoordinationResponseType.notSuitable,
      ),
      HelpOfferEndKind.none,
    );
  });

  test('forward row and people badge share the end, not the withdraw word', () {
    String forward(HelpOfferEndKind kind) => helpOfferEndLabel(
      en,
      kind,
      HelpOfferEndLabelSurface.forwardRow,
    );
    String badge(HelpOfferEndKind kind) => helpOfferEndLabel(
      en,
      kind,
      HelpOfferEndLabelSurface.peopleBadge,
    );

    expect(forward(HelpOfferEndKind.declined), en.helpOfferStatusDeclined);
    expect(forward(HelpOfferEndKind.declined), isNot(en.forwardWithdrawn));
    expect(
      forward(HelpOfferEndKind.participationEnded),
      en.helpOfferParticipationEndedLabel,
    );
    expect(forward(HelpOfferEndKind.withdrew), en.forwardWithdrawn);
    expect(badge(HelpOfferEndKind.withdrew), en.labelWithdrawn);
    expect(badge(HelpOfferEndKind.declined), en.helpOfferStatusDeclined);
    expect(
      helpOfferEndLabel(
        ru,
        HelpOfferEndKind.declined,
        HelpOfferEndLabelSurface.forwardRow,
      ),
      ru.helpOfferStatusDeclined,
    );
    expect(
      helpOfferEndLabel(
        ru,
        HelpOfferEndKind.participationEnded,
        HelpOfferEndLabelSurface.peopleBadge,
      ),
      ru.helpOfferParticipationEndedLabel,
    );
  });
}
