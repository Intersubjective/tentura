import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/declined_offer_notice.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _author = Profile(id: 'auth', displayName: 'Author');
const _me = Profile(id: 'me', displayName: 'Me');

TimelineHelpOffer _offer({
  bool isWithdrawn = true,
  HelpOfferAdmissionAction? admissionAction =
      HelpOfferAdmissionAction.decline,
}) => TimelineHelpOffer(
  user: _me,
  message: 'I can help',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  isWithdrawn: isWithdrawn,
  admissionAction: admissionAction,
  lastDeclineReason: 'We have enough hands',
);

BeaconViewState _state(List<TimelineHelpOffer> offers, {Profile? author}) =>
    BeaconViewState(
      beacon: Beacon.empty.copyWith(
        id: 'Bxxxx',
        updatedAt: DateTime(2026),
        author: author ?? _author,
      ),
      helpOffers: offers,
      myProfile: _me,
    );

/// UI review #216: an author's decline must not be silent for the offerer.
void main() {
  group('BeaconViewState.myDeclinedHelpOffer', () {
    test('is the viewer offer the author declined', () {
      expect(
        _state([_offer()]).myDeclinedHelpOffer?.lastDeclineReason,
        'We have enough hands',
      );
    });

    test('is null for an offer the viewer withdrew themselves', () {
      expect(
        _state([_offer(admissionAction: null)]).myDeclinedHelpOffer,
        isNull,
      );
    });

    test('is null once the viewer has an active offer again', () {
      expect(
        _state([
          _offer(),
          _offer(isWithdrawn: false, admissionAction: null),
        ]).myDeclinedHelpOffer,
        isNull,
      );
    });

    test('is null on the viewer own request', () {
      expect(_state([_offer()], author: _me).myDeclinedHelpOffer, isNull);
    });
  });

  group('DeclinedOfferNotice', () {
    Future<void> pump(
      WidgetTester tester, {
      String? reason,
      bool canOfferAgain = true,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: DeclinedOfferNotice(
            reason: reason,
            canOfferAgain: canOfferAgain,
          ),
        ),
      ),
    );

    testWidgets('shows the title, the author note and the re-offer hint', (
      tester,
    ) async {
      await pump(tester, reason: '  We have enough hands ');

      expect(find.text('Your offer was declined'), findsOneWidget);
      expect(find.text("Author's note"), findsOneWidget);
      expect(find.text('We have enough hands'), findsOneWidget);
      expect(
        find.text('You can offer help again if something changes.'),
        findsOneWidget,
      );
    });

    testWidgets('hides an empty note and the hint when re-offer is closed', (
      tester,
    ) async {
      await pump(tester, reason: ' ', canOfferAgain: false);

      expect(find.text('Your offer was declined'), findsOneWidget);
      expect(find.text("Author's note"), findsNothing);
      expect(
        find.text('You can offer help again if something changes.'),
        findsNothing,
      );
    });
  });
}
