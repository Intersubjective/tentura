// U094: plain words, checked against fresh test readers (see
// fixes/U094.md and findings/round2/U094_wording_test.md).
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
      expect(en.activityMovedToStream, 'Moved down to your Activity feed');
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
    });

    test('people and closing', () {
      expect(en.beaconPeopleLensNotFittingHeading, 'Declined offers');
      expect(en.closureAuthorTitle, 'Close & sum up');
    });

    test('no retired jargon is left in any EN string', () {
      // Retired labels must not survive as whole labels anywhere.
      final retired = RegExp(
        r'IN ON IT|In on it|Nothing noted yet|Needs me|Not fitting|'
        r'Moved to the stream|Wrapping up|wrapping up|Enough help committed$',
      );
      final values = <String>[
        en.labelBeaconTabNow,
        en.beaconShowcaseTeamLabel,
        en.beaconShowcaseTeamSheetTitle,
        en.beaconHudNoCurrentLine,
        en.inboxNeedsMe,
        en.actionStopWatching,
        en.activityMovedToStream,
        en.beaconPeopleLensNotFittingHeading,
        en.beaconPhaseWrappingUp,
        en.beaconStatusHintCancelWrappingUp,
        en.beaconCloseSheetBranchWrappingUp,
        en.beaconCloseSheetReviewWrappingUpBody,
        en.beaconCloseSheetPrematureReviewBody,
        en.coordinationEnoughHelp,
      ];
      for (final v in values) {
        expect(retired.hasMatch(v), isFalse, reason: v);
      }
    });
  });

  group('U094 plain wording (RU)', () {
    test('same terms, consistent RU', () {
      expect(ru.labelBeaconTabNow, 'Обзор');
      expect(ru.beaconShowcaseTeamLabel, 'ПОМОГАЮТ');
      expect(ru.beaconShowcaseTeamSheetTitle, 'Помогают');
      expect(ru.beaconHudNoCurrentLine, 'Следующего шага пока нет');
      expect(ru.beaconFactsRowLabel, 'Адрес и детали');
      expect(ru.inboxNeedsMe, 'Ждёт вас');
      expect(ru.actionStopWatching, 'Вернуть в «Ждёт вас»');
      expect(ru.activityMovedToStream, 'Перемещено ниже, в ленту «Активность»');
      expect(
        const MovedToInboxMessage().toRu,
        'Предложение отозвано. Обновления по нему останутся во вкладке «Слежу».',
      );
      expect(ru.coordinationEnoughHelp, 'Достаточно помощи');
      expect(ru.beaconPhaseWrappingUp, 'Финальная проверка');
      expect(ru.beaconStatusRowWrappingUp, 'Финальная проверка');
      expect(ru.myWorkStatusWrappingUp, 'Финальная проверка');
      expect(ru.beaconPeopleLensNotFittingHeading, 'Отклонённые предложения');
      expect(ru.closureAuthorTitle, 'Закрыть и подвести итоги');
    });
  });
}
