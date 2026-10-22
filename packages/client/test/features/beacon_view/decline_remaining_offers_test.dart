// «Decline remaining offers» (#268, D10), client side:
//  - `BeaconViewState.remainingPendingOffers` mirrors the server rule: live
//    ordinary offers from people not admitted (an addressee may be); accepted
//    helpers, backup offers, withdrawn offers and the author are left out;
//  - it is offered only to the author or a steward after «Enough help»;
//  - the confirmation is prefilled with an editable reason and says what it
//    leaves alone; cancelling sends nothing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_admission_reason_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _author = Profile(id: 'u-author', displayName: 'Anna');
const _other = Profile(id: 'u-other', displayName: 'Olga');

TimelineHelpOffer _offer(
  String id, {
  bool withdrawn = false,
  int kind = 0,
  CommitmentStakeState stake = CommitmentStakeState.none,
}) => TimelineHelpOffer(
  user: Profile(id: id, displayName: id),
  message: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  isWithdrawn: withdrawn,
  offerKind: kind,
  stakeState: stake,
);

BeaconParticipant _participant(String id, {required int role}) =>
    BeaconParticipant(
      id: 'p-$id',
      beaconId: 'b1',
      userId: id,
      role: role,
      status: 0,
      roomAccess: RoomAccessBits.admitted,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

BeaconViewState _state({
  BeaconStatus status = BeaconStatus.enoughHelp,
  Profile viewer = _author,
}) => BeaconViewState(
  beacon: Beacon.empty.copyWith(
    id: 'b1',
    status: status,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    author: _author,
  ),
  myProfile: viewer,
  helpOffers: [
    _offer('u-pending'),
    _offer('u-addressee'),
    _offer('u-accepted', stake: CommitmentStakeState.acknowledged),
    _offer('u-roster'),
    _offer('u-steward'),
    _offer('u-backup', kind: 1),
    _offer('u-gone', withdrawn: true),
    _offer(_author.id),
  ],
  admittedHelperRoster: const [Profile(id: 'u-roster')],
  roomParticipants: [
    _participant('u-addressee', role: BeaconParticipantRoleBits.addressee),
    _participant('u-steward', role: BeaconParticipantRoleBits.steward),
  ],
);

void main() {
  group('remainingPendingOffers', () {
    test('keeps only offers still waiting for an answer', () {
      expect(
        _state().remainingPendingOffers.map((o) => o.user.id),
        ['u-pending', 'u-addressee'],
      );
    });

    test('is offered to the author after «Enough help»', () {
      expect(_state().canDeclineRemainingOffers, isTrue);
    });

    test('is not offered before «Enough help»', () {
      expect(
        _state(status: BeaconStatus.open).canDeclineRemainingOffers,
        isFalse,
      );
    });

    test('is not offered to someone who is neither author nor steward', () {
      expect(_state(viewer: _other).canDeclineRemainingOffers, isFalse);
    });
  });

  group('confirmation', () {
    Future<String?> Function() openDialog(WidgetTester tester) {
      String? result = 'unset';
      return () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            locale: const Locale('en'),
            home: TenturaResponsiveScope(
              child: Scaffold(
                body: Builder(
                  builder: (context) {
                    final l10n = L10n.of(context)!;
                    return TextButton(
                      onPressed: () async {
                        result = await HelpOfferAdmissionReasonDialog.show(
                          context,
                          title: l10n.declineRemainingOffersTitle(2),
                          explanatoryNote: l10n.declineRemainingOffersNote,
                          hintText: l10n.helpOfferDeclineDialogHint,
                          submitLabel: l10n.declineRemainingOffersConfirm,
                          initialText: l10n.declineRemainingOffersDefaultReason,
                          destructive: true,
                        );
                      },
                      child: const Text('open'),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        return result;
      };
    }

    testWidgets('is prefilled and says what it leaves alone', (tester) async {
      await openDialog(tester)();

      expect(find.text('Decline remaining offers (2)?'), findsOneWidget);
      expect(find.textContaining('Accepted helpers stay'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Thank you! I have enough help now.',
      );
    });

    testWidgets('sends the (edited) reason on confirm', (tester) async {
      String? reason;
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: TenturaResponsiveScope(
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    reason = await HelpOfferAdmissionReasonDialog.show(
                      context,
                      title: 'Decline remaining offers (2)?',
                      hintText: 'hint',
                      submitLabel: 'Decline all',
                      initialText: 'Thank you!',
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Found someone, thanks');
      await tester.tap(find.text('Decline all'));
      await tester.pumpAndSettle();

      expect(reason, 'Found someone, thanks');
    });

    testWidgets('cancelling an untouched prefill sends nothing', (
      tester,
    ) async {
      String? reason = 'unset';
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: TenturaResponsiveScope(
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    reason = await HelpOfferAdmissionReasonDialog.show(
                      context,
                      title: 'Decline remaining offers (2)?',
                      hintText: 'hint',
                      submitLabel: 'Decline all',
                      initialText: 'Thank you!',
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(reason, isNull, reason: 'closed without a discard prompt');
    });
  });
}
