import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_child_request_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_child_requests_section.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_hierarchy_parent_link.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_cards.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offer help, admit helper, chat, and manage items', (
    tester,
  ) async {
    await launchApp(app.main);
    await tester.pumpAndSettle();

    final fixture = await bootstrapFixture(
      runId: uniqueRunId('offer-admit'),
    );
    final title = uniqueRequestTitle('IT offer admit');

    await logout(tester);
    await createAndForwardRequest(
      tester,
      fixture: fixture,
      title: title,
    );

    await logout(tester);
    await offerHelpFromInbox(
      tester,
      fixture: fixture,
      requestTitle: title,
    );

    await logout(tester);
    await acceptHelpOffer(
      tester,
      fixture: fixture,
      requestTitle: title,
    );

    await logout(tester);
    await loginAs(tester, fixture.helperEmail);
    // After offering help the request moves from Inbox to the helper's
    // My Work (involved) list.
    await openRequestFromMyWork(tester, requestTitle: title);

    await enterChatIfNeeded(tester);
    final parentCubit = tester
        .element(find.byType(BeaconChildRequestsSection))
        .read<BeaconViewCubit>();
    final parentId = parentCubit.state.beacon.id;
    final childTitle = uniqueRequestTitle('IT child');
    late String childId;
    await runE2eStep('create child from parent Discussion', () async {
      final createChild = find.byKey(TestIds.key(TestIds.childRequestCreate));
      await pumpUntilVisible(tester, createChild);
      await tester.ensureVisible(createChild);
      await tapAndSettle(tester, createChild);
      final titleField = find.byKey(TestIds.key(TestIds.requestTitle));
      await pumpUntilVisible(tester, titleField);
      await tester.enterText(titleField, childTitle);
      await tester.enterText(
        find.byKey(TestIds.key(TestIds.requestDescription)),
        'Independent child request for the parent',
      );
      syncBeaconCreateDraftFields(
        tester,
        title: childTitle,
        description: 'Independent child request for the parent',
      );
      final composer = tester
          .element(find.byKey(const Key('BeaconCreate.FormBody')))
          .read<BeaconCreateCubit>();
      expect(
        (composer.state.creationContext! as BeaconCreationContextChild)
            .parentBeaconId,
        parentId,
      );
      await tapAndSettle(
        tester,
        find.byKey(TestIds.key(TestIds.requestRecipientsTab)),
      );
      final publish = find.byKey(TestIds.key(TestIds.requestMakeLive));
      await pumpUntilVisible(tester, publish);
      await tester.ensureVisible(publish);
      await tapAndSettle(tester, publish);
      await pumpUntilVisible(tester, find.byType(BeaconHierarchyParentLink));
      final parentLink = tester.widget<BeaconHierarchyParentLink>(
        find.byType(BeaconHierarchyParentLink),
      );
      expect(parentLink.reference.beaconId, parentId);
      final child = tester
          .element(find.byType(BeaconHierarchyParentLink))
          .read<BeaconViewCubit>()
          .state
          .beacon;
      childId = child.id;
      expect(child.author.id, fixture.helperUserId);
      expect(child.status, BeaconStatus.open);
    });
    await runE2eStep('Active child card and parent navigation', () async {
      await tapAndSettle(
        tester,
        find.byKey(TestIds.key(TestIds.childRequestParentLink)),
      );
      await enterChatIfNeeded(tester);
      final activeCard = find.descendant(
        of: find.byKey(TestIds.key(TestIds.childRequestsActive)),
        matching: find.byKey(TestIds.key(TestIds.childRequestCard(childId))),
      );
      await pumpUntilVisible(tester, activeCard);
      expect(
        tester.widget<BeaconChildRequestCard>(activeCard).summary.status,
        BeaconStatus.open,
      );
      await tester.ensureVisible(activeCard);
      await tapAndSettle(tester, activeCard);
      await pumpUntilVisible(tester, find.byType(BeaconHierarchyParentLink));
    });
    await runE2eStep('close child as its author from My Work', () async {
      await showMyWorkList(tester);
      final childCard = find.byWidgetPredicate(
        (widget) =>
            widget is MyWorkCardRouter && widget.vm.beacon.id == childId,
      );
      await pumpUntilVisible(tester, childCard);
      final overflow = find.descendant(
        of: childCard,
        matching: find.byKey(TestIds.key(TestIds.beaconOverflowMenu)),
      );
      await tapAndSettle(tester, overflow);
      await tapAndSettle(
        tester,
        find.byKey(TestIds.key(TestIds.beaconOverflowClose)),
      );
      await tapAndSettle(
        tester,
        find.byKey(TestIds.key(TestIds.beaconCloseConfirm)),
      );
      await pumpUntil(
        tester,
        () =>
            finderHasMatch(childCard) &&
            tester.widget<MyWorkCardRouter>(childCard).vm.beacon.status ==
                BeaconStatus.closed,
      );
    });
    await runE2eStep('Finished child card while parent stays open', () async {
      await openRequestFromMyWork(tester, requestTitle: title);
      await enterChatIfNeeded(tester);
      final finishedCard = find.descendant(
        of: find.byKey(TestIds.key(TestIds.childRequestsFinished)),
        matching: find.byKey(TestIds.key(TestIds.childRequestCard(childId))),
      );
      await pumpUntilVisible(tester, finishedCard);
      expect(
        tester.widget<BeaconChildRequestCard>(finishedCard).summary.status,
        BeaconStatus.closed,
      );
      expect(
        find.descendant(
          of: find.byKey(TestIds.key(TestIds.childRequestsActive)),
          matching: find.byKey(TestIds.key(TestIds.childRequestCard(childId))),
        ),
        findsNothing,
      );
      expect(
        tester
            .element(find.byType(BeaconChildRequestsSection))
            .read<BeaconViewCubit>()
            .state
            .beacon
            .status,
        BeaconStatus.open,
      );
    });
    await runE2eStep(
      'send room message',
      () => sendRoomMessage(tester, 'Integration test room message'),
    );

    await runE2eStep('log out helper', () => logout(tester));
    await runE2eStep(
      'log in author',
      () => loginAs(tester, fixture.authorEmail),
    );
    await runE2eStep(
      'open author request from My Work',
      () => openRequestFromMyWork(tester, requestTitle: title),
    );
    await runE2eStep(
      'author receives General chat after child closure',
      () async {
        await enterChatIfNeeded(tester);
        final received = find.byWidgetPredicate(
          (widget) =>
              widget is RoomMessageTile &&
              widget.message.body == 'Integration test room message' &&
              widget.message.authorId == fixture.helperUserId,
        );
        await pumpUntilVisible(tester, received);
      },
    );
    await tapAndSettle(
      tester,
      find.byKey(TestIds.key(TestIds.beaconTabPeople)),
    );
    await runE2eStep(
      'end helper participation',
      () async {
        await endHelperParticipation(tester, fixture: fixture);
        await pumpUntil(
          tester,
          () => !finderHasMatch(
            find.byKey(
              TestIds.key(TestIds.helpOfferRelease(fixture.helperUserId)),
            ),
          ),
        );
      },
    );
  });
}
