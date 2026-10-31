// #686: a closed Request still told a backup offerer "Your offer is with the
// author" and said "HELPING · 1 person is helping". On a closed or cancelled
// Request an unanswered offer gets a closed-state line and the team reads in
// the past tense. #527: while it runs, the line says the offer was sent to
// the author, by name, and a second line says what happens next.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_request_modes.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_showcase_surface.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

const _author = Profile(id: 'Uauthor', displayName: 'Ana');
const _fay = Profile(id: 'Ufay', displayName: 'Fay');
const _ben = Profile(id: 'Uben', displayName: 'Ben');

BeaconViewState _state(BeaconStatus status, {int offerKind = 0}) =>
    BeaconViewState(
      beacon: Beacon.empty.copyWith(
        id: 'B1',
        status: status,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        author: _author,
      ),
      myProfile: _fay,
      helpOffers: [
        TimelineHelpOffer(
          user: _fay,
          message: 'I can help on Sunday',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          offerKind: offerKind,
        ),
      ],
    );

void main() {
  final en = L10nEn();
  final ru = L10nRu();

  group('the line under the team for a waiting offer', () {
    test('while the Request runs: with the author, by name (#527)', () {
      for (final status in [
        BeaconStatus.open,
        BeaconStatus.enoughHelp,
        BeaconStatus.reviewOpen,
      ]) {
        expect(
          beaconShowcaseOfferPendingText(en, _state(status)),
          'Offer sent to Ana',
          reason: status.name,
        );
        expect(
          beaconShowcaseOfferPendingText(ru, _state(status)),
          'Предложение отправлено автору (Ana)',
          reason: status.name,
        );
      }
    });

    test('an author with no shown name: with the author (#527)', () {
      final s = _state(BeaconStatus.open);
      final nameless = s.copyWith(
        beacon: s.beacon.copyWith(author: const Profile(id: 'Uauthor')),
      );
      expect(
        beaconShowcaseOfferPendingText(en, nameless),
        'Offer sent to the author',
      );
      expect(
        beaconShowcaseOfferPendingText(ru, nameless),
        'Предложение отправлено автору',
      );
    });

    test('a backup offer while the Request runs (#527)', () {
      final s = _state(BeaconStatus.enoughHelp, offerKind: 1);
      expect(
        beaconShowcaseOfferPendingText(en, s),
        'Backup offer sent to Ana',
      );
      expect(
        beaconShowcaseOfferPendingText(ru, s),
        'Запасное предложение отправлено автору (Ana)',
      );
    });

    test('what happens next: notified, Withdraw only when shown (#527)', () {
      final s = _state(BeaconStatus.open);
      expect(
        beaconShowcaseOfferNextText(en, s, canWithdraw: true),
        "You'll be notified when they answer. "
        'You can withdraw the offer until then.',
      );
      expect(
        beaconShowcaseOfferNextText(en, s, canWithdraw: false),
        "You'll be notified when they answer.",
      );
      expect(
        beaconShowcaseOfferNextText(ru, s, canWithdraw: true),
        'Вы получите уведомление, когда автор ответит. '
        'До тех пор предложение можно отозвать.',
      );
      final backup = _state(BeaconStatus.enoughHelp, offerKind: 1);
      expect(
        beaconShowcaseOfferNextText(en, backup, canWithdraw: false),
        'They may contact you if more help is needed.',
      );
      for (final status in [BeaconStatus.closed, BeaconStatus.cancelled]) {
        expect(
          beaconShowcaseOfferNextText(en, _state(status), canWithdraw: false),
          isNull,
          reason: status.name,
        );
      }
    });

    test('the offer text is quoted under the line (#527)', () {
      final s = _state(BeaconStatus.open);
      expect(
        beaconShowcaseOfferQuoteText(en, s),
        '“I can help on Sunday”',
      );
      expect(
        beaconShowcaseOfferQuoteText(ru, s),
        '«I can help on Sunday»',
      );
      expect(
        beaconShowcaseOfferQuoteText(
          en,
          s.copyWith(helpOffers: [s.helpOffers.single.copyWith(message: ' ')]),
        ),
        isNull,
      );
    });

    test('closed: the backup offer was not needed', () {
      expect(
        beaconShowcaseOfferPendingText(
          en,
          _state(BeaconStatus.closed, offerKind: 1),
        ),
        'This request closed before your backup offer was needed.',
      );
      expect(
        beaconShowcaseOfferPendingText(
          ru,
          _state(BeaconStatus.closed, offerKind: 1),
        ),
        ru.beaconShowcaseBackupOfferUnneededClosed,
      );
    });

    test('closed or cancelled: the offer was not answered', () {
      expect(
        beaconShowcaseOfferPendingText(en, _state(BeaconStatus.closed)),
        'This request closed before your offer was answered.',
      );
      expect(
        beaconShowcaseOfferPendingText(
          en,
          _state(BeaconStatus.cancelled, offerKind: 1),
        ),
        'This request was cancelled before your offer was answered.',
      );
    });

    test('never "with the author" once finished, in either language', () {
      for (final l10n in <L10n>[en, ru]) {
        for (final status in [BeaconStatus.closed, BeaconStatus.cancelled]) {
          for (final kind in [0, 1]) {
            expect(
              beaconShowcaseOfferPendingText(
                l10n,
                _state(status, offerKind: kind),
              ),
              isNot(l10n.beaconShowcaseOfferSent),
            );
          }
        }
      }
    });
  });

  group('the team, once finished', () {
    BeaconShowcaseTeam team(int total) => BeaconShowcaseTeam(
      visible: const [_ben],
      acquaintances: const [],
      hiddenCount: total - 1,
    );

    test('speaks in the past tense', () {
      expect(
        beaconShowcaseTeamCaption(en, team(1), finished: true),
        '1 person helped',
      );
      expect(
        beaconShowcaseTeamCaption(en, team(2), finished: true),
        '2 people helped',
      );
      for (final (count, text) in [
        (1, 'Помог 1 человек'),
        (2, 'Помогли 2 человека'),
        (5, 'Помогли 5 человек'),
        (21, 'Помог 21 человек'),
        (22, 'Помогли 22 человека'),
      ]) {
        expect(
          beaconShowcaseTeamCaption(ru, team(count), finished: true),
          text,
        );
      }
      expect(
        beaconShowcaseTeamCaption(
          en,
          const BeaconShowcaseTeam(
            visible: [],
            acquaintances: [],
            hiddenCount: 0,
          ),
          finished: true,
        ),
        en.beaconShowcaseTeamEmptyClosed,
      );
    });

    testWidgets('the strip label is HELPED', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: BeaconShowcaseTeamStrip(team: team(1), finished: true),
          ),
        ),
      );
      expect(find.text('HELPED'), findsOneWidget);
      expect(find.text('HELPING'), findsNothing);
      expect(find.text('1 person helped'), findsOneWidget);
    });
  });
}
