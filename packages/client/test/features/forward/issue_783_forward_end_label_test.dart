import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/help_offer_end.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_people_labels.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  final en = lookupL10n(const Locale('en'));

  String forwardLabel({
    required bool isWithdrawn,
    CommitmentStakeState stake = CommitmentStakeState.none,
    String? withdrawReason,
    CoordinationResponseType? response,
  }) {
    final kind = helpOfferEndKind(
      isWithdrawn: isWithdrawn,
      stakeState: stake,
      withdrawReason: withdrawReason,
      coordinationResponse: response,
    );
    return helpOfferEndLabel(en, kind, HelpOfferEndLabelSurface.forwardRow);
  }

  test('a declined pending offer is not "Withdrew commitment"', () {
    expect(
      forwardLabel(
        isWithdrawn: true,
        stake: CommitmentStakeState.offered,
        response: CoordinationResponseType.notSuitable,
      ),
      en.helpOfferStatusDeclined,
    );
    expect(
      forwardLabel(
        isWithdrawn: true,
        stake: CommitmentStakeState.offered,
        response: CoordinationResponseType.notSuitable,
      ),
      isNot(en.forwardWithdrawn),
    );
  });

  test('ending participation is not a withdrawal on the Forwards row', () {
    expect(
      forwardLabel(
        isWithdrawn: true,
        stake: CommitmentStakeState.released,
        response: CoordinationResponseType.useful,
      ),
      en.helpOfferParticipationEndedLabel,
    );
  });

  test('a helper who withdrew still reads as withdrew', () {
    expect(
      forwardLabel(
        isWithdrawn: true,
        stake: CommitmentStakeState.exited,
        withdrawReason: 'other',
      ),
      en.forwardWithdrawn,
    );
  });
}
