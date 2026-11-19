// The local web integration runner opens Chrome at 375x806 for this test.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

const _privacyHint =
    'Те, кого вы не отметите, не узнают об этом запросе. '
    'Пост останется без изменений.';
const _postMemberCount = 12;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'on a Russian phone the privacy hint fits and all other Post members '
    'can be ticked with confirmation reachable',
    (tester) async {
      await launchApp(app.main);
      final runId = uniqueRunId('bud-invite-phone');
      // Every bootstrap call returns a separate helper and reuses the author
      // after the first call. The Post author is the twelfth member.
      final author = await bootstrapFixture(runId: 'm0-$runId');
      final recipients = [author.helperUserId];
      for (var i = 1; i < _postMemberCount - 1; i++) {
        final next = await bootstrapFixture(
          runId: 'm$i-$runId',
          authorEmail: author.authorEmail,
        );
        expect(next.authorUserId, author.authorUserId);
        recipients.add(next.helperUserId);
      }
      expect(recipients, hasLength(_postMemberCount - 1));
      expect({author.authorUserId, ...recipients}, hasLength(_postMemberCount));

      await logout(tester);
      await loginAs(tester, author.authorEmail);
      final settings = GetIt.I<SettingsCubit>();
      final previousLocale = settings.state.localePreference;
      await settings.setLocalePreference(kLocalePreferenceRu);
      addTearDown(() => settings.setLocalePreference(previousLocale));
      final postId = await createPublishedPost(
        body: uniqueRequestTitle('План на выходные'),
        recipientIds: recipients,
      );
      final requestTitle = uniqueRequestTitle('Перенести теплицу');
      await goToDeepLink(tester, '$kPathBeaconView/$postId');
      await tapAndSettle(tester, find.byIcon(Icons.more_vert).first);
      final ru = await L10n.delegate.load(const Locale('ru'));
      await tapAndSettle(tester, find.text(ru.postBudAction));
      final title = find.byKey(TestIds.key(TestIds.requestTitle));
      await pumpUntilVisible(tester, title);
      await tester.enterText(title, requestTitle);
      await tester.enterText(
        find.byKey(TestIds.key(TestIds.requestDescription)),
        'Нужна помощь в воскресенье.',
      );
      final drainedExceptions = e2eDrainExceptions;
      e2eDrainExceptions = false;
      addTearDown(() => e2eDrainExceptions = drainedExceptions);
      await tapAndSettle(tester, find.byKey(const Key('PostBud.NextButton')));

      final invite = find.byKey(const Key('PostBud.InviteStep'));
      await pumpUntilVisible(tester, invite);
      final context = tester.element(invite);
      expect(MediaQuery.sizeOf(context), const Size(375, 667));
      expect(Localizations.localeOf(context).languageCode, 'ru');

      final hint = find.descendant(
        of: invite,
        matching: find.text(_privacyHint, findRichText: true),
      );
      final scrollable = find
          .descendant(
            of: invite,
            matching: find.byType(Scrollable),
          )
          .first;
      expect(hint, findsOneWidget);
      await tester.ensureVisible(hint);
      await pumpSettleBounded(tester);
      final paragraph = tester.renderObject<RenderParagraph>(hint);
      final omittedLines = paragraph.didExceedMaxLines;
      // Check each word separately so the line's trailing whitespace and
      // subpixel rounding do not count as clipped text.
      final words = RegExp(r'\S+').allMatches(_privacyHint);
      final wordBoxes = [
        for (final word in words)
          paragraph.getBoxesForSelection(
            TextSelection(baseOffset: word.start, extentOffset: word.end),
          ),
      ];
      final viewport = tester.getRect(scrollable).inflate(1);
      final glyphBounds = [
        for (final box in wordBoxes.expand((boxes) => boxes))
          box.toRect().shift(paragraph.localToGlobal(Offset.zero)),
      ];
      final clipped = glyphBounds
          .where(
            (rect) =>
                rect.left < viewport.left ||
                rect.top < viewport.top ||
                rect.right > viewport.right ||
                rect.bottom > viewport.bottom,
          )
          .toList();
      Finder checkbox(String id) => find.byKey(
        TestIds.key(TestIds.forwardRecipientCheckbox(id)),
      );
      await pumpUntilVisible(tester, scrollable);
      await pumpUntil(
        tester,
        () => recipients.any((id) => checkbox(id).evaluate().isNotEmpty),
        label: 'Post invite candidates load',
      );

      for (final id in recipients) {
        final box = checkbox(id);
        final position = tester.state<ScrollableState>(scrollable).position;
        position.jumpTo(position.minScrollExtent);
        await tester.pump();
        await tester.scrollUntilVisible(box, 180, scrollable: scrollable);
        await Scrollable.ensureVisible(tester.element(box), alignment: 0.5);
        await pumpSettleBounded(tester);
        expect(box.hitTestable(), findsOneWidget, reason: id);
        final tick = find.descendant(
          of: box,
          matching: find.byIcon(Icons.check),
        );
        expect(tick, findsNothing, reason: '$id starts unticked');
        await tapAndSettle(tester, box);
        expect(tick, findsOneWidget, reason: '$id is ticked');
      }

      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(position.minScrollExtent);
      await pumpSettleBounded(tester);
      expect(
        find.text(ru.postBudInviteManyWarning(recipients.length)),
        findsOneWidget,
      );

      final confirm = find.byKey(const Key('PostBud.SubmitButton'));
      await tester.ensureVisible(confirm);
      await pumpSettleBounded(tester);
      expect(confirm.hitTestable(), findsOneWidget);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      expect(omittedLines, isFalse, reason: 'the privacy hint wraps in full');
      expect(wordBoxes, everyElement(isNotEmpty));
      expect(clipped, isEmpty, reason: 'Privacy hint glyphs outside $viewport');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
