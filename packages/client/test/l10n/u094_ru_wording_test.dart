// U094 RU: Russian plain words, checked against fresh Russian-speaking test
// readers (see fixes/U094.md and findings/round2/U094_ru_wording_test.md).
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

void main() {
  final ru = L10nRu();

  group('U094 RU plain wording', () {
    test('request page', () {
      expect(ru.labelBeaconTabNow, 'Обзор');
      expect(ru.beaconHudStepLabel, 'СЛЕДУЮЩИЙ ШАГ');
      expect(ru.beaconHudNoCurrentLine, 'Следующего шага пока нет');
      expect(ru.beaconFactsRowLabel, 'Адрес и подробности');
      expect(ru.beaconShowcaseTeamLabel, 'ПОМОГАЮТ');
    });

    test('Activity tab for things that need your answer', () {
      expect(ru.inboxNeedsMe, 'Нужен ваш ответ');
      expect(ru.actionStopWatching, 'Вернуть в «Нужен ваш ответ»');
    });

    test('statuses: one word per status, everywhere', () {
      for (final s in [
        ru.constellationRequestStatusNeedsMoreHelp,
        ru.graphLegendConstellationRequestStatusNeedsMoreHelp,
        ru.myWorkStatusNeedsMoreHelp,
        ru.beaconPhaseNeedsMoreHelp,
      ]) {
        expect(s, 'Нужна ещё помощь');
      }
      for (final s in [
        ru.constellationRequestStatusEnoughHelp,
        ru.graphLegendConstellationRequestStatusEnoughHelp,
        ru.myWorkStatusEnoughHelp,
        ru.coordinationEnoughHelp,
        ru.beaconYouEnoughHelp,
        ru.beaconChipEnoughHelp,
      ]) {
        expect(s, 'Помощи хватает');
      }
      expect(ru.beaconHudEnoughHelp, 'ПОМОЩИ ХВАТАЕТ');
      for (final s in [
        ru.constellationRequestStatusWrappingUp,
        ru.graphLegendConstellationRequestStatusWrappingUp,
        ru.myWorkStatusWrappingUp,
        ru.beaconLifecycleReviewOpen,
        ru.beaconPhaseWrappingUp,
        ru.beaconStatusRowWrappingUp,
      ]) {
        expect(s, 'Подводим итоги');
      }
      expect(ru.beaconHudReviewOpen, 'ПОДВОДИМ ИТОГИ');
    });

    test('status change line reads as a sentence', () {
      expect(
        ru.timelineRequestStatusChanged(
          'Анна',
          ru.requestStatusActivityReviewOpen,
        ),
        'Анна сменил(а) статус: «Подводим итоги»',
      );
      expect(ru.requestStatusActivityMoreHelp, 'Нужна ещё помощь');
      expect(ru.requestStatusActivityEnoughHelp, 'Помощи хватает');
      expect(ru.requestStatusActivityClosed, 'Закрыт');
    });

    test('closing and people', () {
      expect(ru.closureAuthorTitle, 'Подвести итоги и закрыть');
      expect(ru.beaconPeopleLensNotFittingHeading, 'Отклонённые предложения');
      // Gender-neutral: the old «Предложил помощь» read wrong next to «Лея».
      expect(ru.beaconPeopleStatusOfferedHelp, 'Предлагает помощь');
      expect(ru.beaconPeopleStatusHelpOffered, 'Предлагает помощь');
      expect(ru.beaconPeopleStatusWithdrawn, 'Предложение отозвано');
    });

    test('no retired or ambiguous RU words are left on these labels', () {
      // «отзыв» means both "review" and "withdrawal" (the app also uses
      // «Отозвать» for withdrawing an offer); «Обзор» is now the Overview tab.
      final retired = RegExp(
        r'Финальн|финальн|отзыв|Отзыв|окно оценки|ОКНО ОЦЕНКИ|обзора|'
        r'Достаточно помощи|Помощи достаточно|ДОСТАТОЧНО|Ждёт|Факты|В ДЕЛЕ|'
        r'Не подходят|Предложил |Выбыл|^ШАГ$|^Нужна помощь$',
      );
      final values = <String>[
        ru.beaconHudStepLabel,
        ru.inboxNeedsMe,
        ru.beaconFactsRowLabel,
        ru.beaconShowcaseTeamLabel,
        ru.beaconPeopleLensNotFittingHeading,
        ru.beaconPeopleStatusOfferedHelp,
        ru.beaconPeopleStatusWithdrawn,
        ru.myWorkStatusNeedsMoreHelp,
        ru.myWorkStatusEnoughHelp,
        ru.beaconHudReviewOpen,
        ru.requestStatusActivityReviewOpen,
        ru.requestStatusActivityWrappingUp,
        ru.beaconStatusHintCancelWrappingUp,
        ru.beaconStatusRowOutcomeWrappingUp,
        ru.beaconCloseSheetBranchWrappingUp,
        ru.beaconCloseSheetReviewWrappingUpBody,
        ru.beaconCloseSheetPrematureReviewBody,
        ru.beaconCloseSheetReadyReviewBody,
        ru.beaconHudActWrapUpForReview,
        ru.beaconHudActEffectWrapUpForReview,
        ru.beaconReviewExtendAction,
        ru.beaconReviewExtendSuccess,
        ru.beaconActivityLifecycleClosedAfterReview,
        ru.beaconActivityLifecycleReviewExpired,
        ru.beaconStatusHintFinishReviewFirst,
        ru.myWorkChipReviewWindowOpen,
      ];
      for (final v in values) {
        expect(retired.hasMatch(v), isFalse, reason: v);
      }
    });

    test('busy error is in Russian and names no internals', () {
      const e = RemoteApiRetryLaterException(Duration(seconds: 2));
      expect(
        e.toRu,
        'Сервер занят. Попробуйте ещё раз через несколько секунд.',
      );
      expect(e.toEn, 'Busy right now. Try again in a few seconds.');
    });
  });
}
