// U094: plain words, checked against fresh test readers (see
// fixes/U094.md and findings/round2/U094_wording_test.md).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_view/ui/message/help_offer_messages.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

void main() {
  final en = L10nEn();
  final ru = L10nRu();

  group('U094 plain wording (EN)', () {
    test('request tabs and team', () {
      expect(en.labelBeaconTabNow, 'Overview');
      expect(en.beaconShowcaseTeamLabel, 'HELPING');
      expect(en.beaconShowcaseTeamSheetTitle, 'Helping');
      expect(en.beaconHudNoCurrentLine, 'No next step yet');
      expect(en.beaconFactsRowLabel, 'Address & details');
    });

    test('Activity tabs and toasts', () {
      expect(en.inboxNeedsMe, 'Waiting on you');
      expect(en.actionStopWatching, 'Return to Waiting on you');
      expect(
        en.activityMovedToStream,
        'Moved out of “For you” to the list below',
      );
      expect(
        const MovedToInboxMessage().toEn,
        "Offer withdrawn. You'll still get updates on it under Following.",
      );
    });

    test('statuses', () {
      expect(en.coordinationEnoughHelp, 'Enough help');
      for (final s in [
        en.beaconPhaseWrappingUp,
        en.beaconStatusRowWrappingUp,
        en.myWorkStatusWrappingUp,
        en.beaconLifecycleReviewOpen,
        en.constellationRequestStatusWrappingUp,
        en.graphLegendConstellationRequestStatusWrappingUp,
      ]) {
        expect(s, 'Final check');
      }
      expect(en.requestStatusActivityWrappingUp, 'final check');
      expect(en.requestStatusActivityReviewOpen, 'final check');
    });

    test('people and closing', () {
      expect(en.beaconPeopleLensNotFittingHeading, 'Declined offers');
      expect(en.closureAuthorTitle, 'Close & sum up');
    });

    test('no retired jargon is left in any EN string', () {
      // Scan every EN value in the ARB, not a hand-picked key list (#542
      // review: `beaconCloseSheetEvidenceEnoughHelp` slipped through), and
      // keep the closing stage under one name: the actions say "final
      // check" like the status, not "wrap up" or "review window".
      final retired = RegExp(
        'IN ON IT|In on it|Nothing noted yet|Needs me|Not fitting|'
        'Moved to the stream|[Ww]rapping up|[Ww]rap up|Enough help committed|'
        r'[Rr]eview window|[Rr]eview period|[Rr]eviewers?\b|'
        r'Extend review|[Ww]aiting for reviews',
      );
      final arb =
          jsonDecode(File('l10n/app_en.arb').readAsStringSync())
              as Map<String, dynamic>;
      final offenders = [
        for (final MapEntry(:key, :value) in arb.entries)
          if (!key.startsWith('@') &&
              value is String &&
              retired.hasMatch(value))
            '$key: $value',
      ];
      expect(offenders, isEmpty);
    });

    test('closing-stage actions use the status name', () {
      expect(en.beaconHudActWrapUpForReview, 'Start final check');
      expect(en.beaconCloseSheetReadyReviewTitle, 'Ready for the final check');
      expect(en.beaconCloseSheetActionStartFinalCheck, 'Start final check');
      expect(en.beaconCloseSheetEvidenceEnoughHelp, 'Marked: enough help');
    });
  });

  group('U094 plain wording (RU)', () {
    // RU words re-chosen by the Russian reader test (u094_ru_wording_test.dart).
    test('same terms, consistent RU', () {
      expect(ru.labelBeaconTabNow, 'Обзор');
      expect(ru.beaconShowcaseTeamLabel, 'ПОМОГАЮТ');
      expect(ru.beaconShowcaseTeamSheetTitle, 'Помогают');
      expect(ru.beaconHudNoCurrentLine, 'Следующего шага пока нет');
      expect(ru.beaconFactsRowLabel, 'Адрес и подробности');
      expect(ru.inboxNeedsMe, 'Нужен ваш ответ');
      expect(ru.actionStopWatching, 'Вернуть в «Нужен ваш ответ»');
      expect(ru.activityMovedToStream, 'Перенесено из «Для вас» в список ниже');
      expect(
        const MovedToInboxMessage().toRu,
        'Предложение отозвано. Обновления по нему останутся во вкладке «Слежу».',
      );
      expect(ru.coordinationEnoughHelp, 'Помощи хватает');
      expect(ru.beaconPhaseWrappingUp, 'Подводим итоги');
      expect(ru.beaconStatusRowWrappingUp, 'Подводим итоги');
      expect(ru.myWorkStatusWrappingUp, 'Подводим итоги');
      expect(ru.beaconPeopleLensNotFittingHeading, 'Отклонённые предложения');
      expect(ru.closureAuthorTitle, 'Подвести итоги и закрыть');
    });
  });
}
