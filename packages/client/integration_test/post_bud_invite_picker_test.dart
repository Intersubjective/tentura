import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

const _memberCount = 12;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'budding a Request from a Post of 12 members shows every invitee by '
    'name, search narrows the list, and the two ticked people are invited',
    (tester) async {
      await launchApp(app.main);
      await pumpSettleBounded(tester);

      // One author befriended by 12 helpers: the first call creates the
      // author, the others reuse the author's account.
      final runId = uniqueRunId('post-bud-invite-picker');
      final first = await bootstrapFixture(runId: 'm0-$runId');
      final authorEmail = first.authorEmail;
      final memberIds = [first.helperUserId];
      for (var i = 1; i < _memberCount; i++) {
        final next = await bootstrapFixture(
          runId: 'm$i-$runId',
          authorEmail: authorEmail,
        );
        memberIds.add(next.helperUserId);
      }
      expect(memberIds.toSet(), hasLength(_memberCount));

      await logout(tester);
      await loginAs(tester, authorEmail);
      final postId = await createPublishedPost(
        body: uniqueRequestTitle('IT bud invite post'),
        recipientIds: memberIds,
      );
      final requestTitle = uniqueRequestTitle('IT bud invite request');

      await goToDeepLink(tester, '$kPathBeaconView/$postId');
      await runE2eStep('open the bud form from the Post menu', () async {
        await tapAndSettle(tester, find.byIcon(Icons.more_vert).first);
        final budLabels = [
          for (final code in ['ru', 'en'])
            (await L10n.delegate.load(Locale(code))).postBudAction,
        ];
        await tapAndSettle(
          tester,
          find
              .byWidgetPredicate(
                (w) => w is Text && budLabels.contains(w.data),
              )
              .first,
        );
        await pumpUntilVisible(
          tester,
          find.byKey(TestIds.key(TestIds.requestTitle)),
        );
      });

      await runE2eStep('fill the title and go to the invite step', () async {
        final titleField = find.byKey(TestIds.key(TestIds.requestTitle));
        await tester.enterText(titleField, requestTitle);
        await tester.enterText(
          find.byKey(TestIds.key(TestIds.requestDescription)),
          'Integration test request for $requestTitle',
        );
        await pumpSettleBounded(tester);
        await tapAndSettle(tester, find.byKey(const Key('PostBud.NextButton')));
        await pumpUntilVisible(
          tester,
          find.byKey(const Key('PostBud.InviteStep')),
        );
      });

      final picker = find.byType(ForwardRecipientPicker);
      await pumpUntil(
        tester,
        () =>
            finderHasMatch(picker) &&
            tester
                    .element(picker)
                    .read<ForwardCubit>()
                    .state
                    .candidates
                    .length ==
                _memberCount,
        label: 'all $_memberCount members loaded in the picker',
      );
      final cubit = tester.element(picker).read<ForwardCubit>();
      final names = {
        for (final c in cubit.state.candidates) c.id: c.profile.shownName,
      };
      Finder rowOf(String id) =>
          find.byKey(TestIds.key(TestIds.forwardRecipient(id)));

      // Scrolls the lazy list until [finder] is built, then pins it on screen.
      Future<void> reveal(Finder finder, String label) async {
        final scrollable = find
            .descendant(of: picker, matching: find.byType(Scrollable))
            .first;
        var down = true;
        await pumpUntil(
          tester,
          () {
            if (finderHasMatch(finder)) return true;
            final position = tester.state<ScrollableState>(scrollable).position;
            if (position.pixels >= position.maxScrollExtent) down = false;
            if (position.pixels <= 0) down = true;
            position.jumpTo(
              (position.pixels +
                      (down ? 1 : -1) * position.viewportDimension / 2)
                  .clamp(0, position.maxScrollExtent),
            );
            return false;
          },
          label: label,
        );
        await tester.ensureVisible(finder.first);
        await pumpSettleBounded(tester);
      }

      await runE2eStep('every invite row shows its member name', () async {
        expect(names.keys.toSet(), memberIds.toSet());
        final unknown = [
          for (final code in ['ru', 'en'])
            (await L10n.delegate.load(Locale(code))).unknownPerson,
        ];
        for (final entry in names.entries) {
          expect(
            entry.value.trim(),
            isNotEmpty,
            reason: 'name of ${entry.key}',
          );
          expect(unknown, isNot(contains(entry.value.trim())));
          await reveal(rowOf(entry.key), 'row of ${entry.key}');
          expect(
            find.descendant(
              of: rowOf(entry.key),
              matching: find.textContaining(entry.value, findRichText: true),
            ),
            findsWidgets,
            reason: 'row of ${entry.key} shows «${entry.value}»',
          );
        }
        for (final text in unknown) {
          expect(find.text(text), findsNothing);
        }
      });

      final searchField = find
          .descendant(of: picker, matching: find.byType(TextField))
          .first;
      await runE2eStep(
        'search narrows the list to the searched member',
        () async {
          final target = memberIds[3];
          final query = names[target]!;
          await tester.enterText(searchField, query);
          final expected = {
            for (final e in names.entries)
              if (e.value.toLowerCase().contains(query.toLowerCase())) e.key,
          };
          expect(expected, contains(target));
          await pumpUntil(
            tester,
            () =>
                {
                  for (final id in memberIds)
                    if (finderHasMatch(rowOf(id))) id,
                }.difference(expected).isEmpty &&
                finderHasMatch(rowOf(target)),
            label: 'list narrowed to «$query»',
          );
          expect(
            expected.length,
            lessThan(_memberCount),
            reason: 'names: $names',
          );
          await tester.enterText(searchField, '');
          await pumpSettleBounded(tester);
        },
      );

      final ticked = [memberIds[0], memberIds[1]];
      await runE2eStep('tick two members and write one note', () async {
        for (final id in ticked) {
          final box = find.byKey(
            TestIds.key(TestIds.forwardRecipientCheckbox(id)),
          );
          await reveal(box, 'checkbox of $id');
          await tapAndSettle(tester, box);
        }
        expect(cubit.state.selectedIds, containsAll(ticked));
        expect(cubit.state.selectedIds.length, ticked.length);

        await reveal(rowOf(ticked.first), 'row of ${ticked.first}');
        final addNote = find.byWidgetPredicate(
          (w) =>
              w is IconButton &&
              (w.tooltip?.contains(names[ticked.first]!) ?? false),
        );
        await tapAndSettle(tester, addNote);
        await tester.enterText(
          find.descendant(of: picker, matching: find.byType(TextField)).last,
          'IT invite note',
        );
        await pumpSettleBounded(tester);
        expect(cubit.state.perRecipientNotes[ticked.first], 'IT invite note');
      });

      await runE2eStep('submit opens the new Request', () async {
        await tapAndSettle(
          tester,
          find.byKey(const Key('PostBud.SubmitButton')),
        );
        final router = GetIt.I<RootRouter>();
        await pumpUntil(
          tester,
          () {
            final segments = Uri.parse(router.currentUrl).pathSegments;
            return router.currentUrl.contains(kPathBeaconView) &&
                segments.isNotEmpty &&
                segments.last != postId;
          },
          label: 'new Request opened',
        );
        final childId = Uri.parse(router.currentUrl).pathSegments.last;

        final data = await runGraphQlAs(
          email: authorEmail,
          restoreEmail: authorEmail,
          query:
              '{ beaconAuthorInvites(beaconId: "$childId") '
              '{ inviteeId status } }',
        );
        final invites = (data['beaconAuthorInvites']! as List)
            .cast<Map<String, dynamic>>();
        expect(
          {for (final i in invites) i['inviteeId'] as String},
          ticked.toSet(),
        );
        expect(
          invites.every((i) => i['status'] == 'pending'),
          isTrue,
          reason: '$invites',
        );
      });
    },
  );
}
