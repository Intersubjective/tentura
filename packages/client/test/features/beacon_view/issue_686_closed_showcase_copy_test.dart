// #686: a closed Request still told a backup offerer "Your offer is with the
// author" and said "HELPING · 1 person is helping". On a closed or cancelled
// Request an unanswered offer gets a closed-state line and the team reads in
// the past tense.

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
    test('while the Request runs: with the author', () {
      for (final status in [
        BeaconStatus.open,
        BeaconStatus.enoughHelp,
        BeaconStatus.reviewOpen,
      ]) {
        expect(
          beaconShowcaseOfferPendingText(en, _state(status)),
          en.beaconShowcaseOfferPending,
          reason: status.name,
        );
      }
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
              isNot(l10n.beaconShowcaseOfferPending),
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
      expect(
        beaconShowcaseTeamCaption(ru, team(1), finished: true),
        'Помог 1 человек',
      );
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
