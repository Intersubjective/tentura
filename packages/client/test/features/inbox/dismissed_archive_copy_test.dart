import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/inbox/ui/widget/activity_forward_outcome_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// #485: "Declined" meant two things. Requests the viewer puts away from
/// Activity ("Can't help" / "Remove from Activity") land in an archive that
/// must be called "Dismissed"; "declined" stays reserved for help offers the
/// author turned down.
void main() {
  final en = lookupL10n(const Locale('en'));
  final ru = lookupL10n(const Locale('ru'));

  group('dismissed-requests archive copy', () {
    test('English archive title and tab label say Dismissed', () {
      expect(en.inboxRejectedTitle, 'Dismissed');
      expect(en.inboxTabRejected, 'Dismissed');
    });

    test('English empty state talks about dismissed requests and posts', () {
      expect(
        en.inboxRejectedEmptyHint,
        'Requests and posts you dismissed from Activity land here. You can bring any of them back.',
      );
      expect(en.inboxTabRejectedEmpty.toLowerCase(), contains('dismissed'));
      expect(en.inboxTabRejectedEmpty.toLowerCase(), contains('post'));
      for (final s in [
        en.inboxRejectedTitle,
        en.inboxTabRejected,
        en.inboxTabRejectedEmpty,
        en.inboxRejectedEmptyHint,
      ]) {
        expect(s.toLowerCase(), isNot(contains('declin')), reason: s);
      }
    });

    test('Russian archive copy no longer uses the offer-decline word', () {
      // "Отклонённые" / "отклонили" is the word the Russian offer strings use
      // ("Ваше предложение отклонено"), so the archive must not reuse it.
      for (final s in [
        ru.inboxRejectedTitle,
        ru.inboxTabRejected,
        ru.inboxTabRejectedEmpty,
        ru.inboxRejectedEmptyHint,
      ]) {
        expect(s.toLowerCase(), isNot(contains('отклон')), reason: s);
        expect(s.trim(), isNotEmpty);
      }
      expect(ru.inboxRejectedTitle, isNot(en.inboxRejectedTitle));
      expect(ru.inboxRejectedEmptyHint, isNot(en.inboxRejectedEmptyHint));
    });
  });

  // V3 (#611, part of #485): the request-side "declined" strings say
  // "dismissed", matching the Dismissed tab.
  group('request-side outcome copy says dismissed', () {
    test('English request-side strings say dismissed', () {
      expect(en.activityForwardOutcomeNotInterested, 'You dismissed it');
      expect(en.forwardDeclined, 'Dismissed this request');
      expect(en.myForwardDeclined, 'Dismissed');
      expect(en.myForwardDeclinedWithReason('Busy'), 'Dismissed: Busy');
      for (final s in [
        en.activityForwardOutcomeNotInterested,
        en.forwardDeclined,
        en.myForwardDeclined,
        en.myForwardDeclinedWithReason('Busy'),
      ]) {
        expect(s.toLowerCase(), isNot(contains('declin')), reason: s);
      }
    });

    test('Russian request-side strings say убрано, not отклонено', () {
      expect(ru.activityForwardOutcomeNotInterested, 'Вы убрали');
      expect(ru.forwardDeclined, 'Убрал(а) этот запрос');
      expect(ru.myForwardDeclined, 'Убрано');
      expect(ru.myForwardDeclinedWithReason('Занят'), 'Убрано: Занят');
      for (final s in [
        ru.activityForwardOutcomeNotInterested,
        ru.forwardDeclined,
        ru.myForwardDeclined,
        ru.myForwardDeclinedWithReason('Занят'),
      ]) {
        expect(s.toLowerCase(), isNot(contains('отклон')), reason: s);
        expect(s.toLowerCase(), isNot(contains('отказ')), reason: s);
      }
    });

    test('the Activity outcome label for notInterested says dismissed', () {
      expect(
        activityForwardOutcomeLabel(en, AttentionForwardOutcome.notInterested),
        'You dismissed it',
      );
      expect(
        activityForwardOutcomeLabel(ru, AttentionForwardOutcome.notInterested),
        'Вы убрали',
      );
    });
  });

  group('offer copy keeps declined', () {
    test('English offer strings still say declined', () {
      expect(en.helpOfferStatusDeclined, 'Declined');
      expect(en.myWorkOfferDeclined, 'Author declined your offer');
      expect(en.helpOfferDeclinedNoticeTitle, 'Your offer was declined');
      expect(en.updatesFallbackTitleOfferDeclined, 'Offer declined');
      expect(en.beaconPeopleLensNotFittingHeading, 'Declined offers');
    });

    test('Russian offer strings still use the decline word', () {
      for (final s in [
        ru.helpOfferStatusDeclined,
        ru.myWorkOfferDeclined,
        ru.helpOfferDeclinedNoticeTitle,
        ru.updatesFallbackTitleOfferDeclined,
        ru.beaconPeopleLensNotFittingHeading,
      ]) {
        expect(s.toLowerCase(), contains('отклон'), reason: s);
      }
    });
  });
}
