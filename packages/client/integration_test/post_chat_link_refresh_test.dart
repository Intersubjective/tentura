import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/features/beacon_threads/data/gql/_g/room_message_create.req.gql.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/widget/basic_chat_body.dart';

import 'support/e2e_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a linked older Post reply stays in view as a new reply arrives',
    (tester) async {
      await launchApp(app.main);
      final fixture = await bootstrapFixture(
        runId: uniqueRunId('post-chat-link-refresh'),
      );
      await logout(tester);
      await loginAs(tester, fixture.authorEmail);
      final postId = await createPublishedPost(
        body: uniqueRequestTitle('Post with a long chat'),
        recipientIds: [fixture.helperUserId],
      );
      final chat = GetIt.I<BeaconThreadsCase>();
      await logout(tester);
      await loginAs(tester, fixture.helperEmail);
      final targetId = await chat.createMessage(
        beaconId: postId,
        body: 'Earlier linked reply',
      );
      expect(targetId, isNotNull);
      for (var i = 1; i <= 50; i++) {
        // Split setup between the two participants to stay under the rate limit.
        if (i == 25) {
          await logout(tester);
          await loginAs(tester, fixture.authorEmail);
        }
        expect(
          await chat.createMessage(beaconId: postId, body: 'Newer reply $i'),
          isNotNull,
        );
      }
      final page = await chat.fetchMessages(beaconId: postId);
      expect(page, hasLength(50));
      expect(page.map((message) => message.id), isNot(contains(targetId)));

      await goToDeepLink(tester, '/post/view/$postId?message=$targetId');
      final chatBody = find.byType(BasicChatBody);
      final target = find.byWidgetPredicate(
        (widget) => widget is RoomMessageTile && widget.message.id == targetId,
        description: 'tile for the linked older reply',
      );
      final viewport = find.ancestor(
        of: target,
        matching: find.byType(Viewport),
      );
      bool targetIsInView() =>
          target.evaluate().isNotEmpty &&
          viewport.evaluate().isNotEmpty &&
          tester.getRect(viewport.first).contains(tester.getCenter(target));

      await pumpUntil(
        tester,
        () =>
            targetIsInView() &&
            tester.state<BasicChatBodyState>(chatBody).isViewportScrollDone &&
            tester
                    .widget<RoomMessageTile>(target)
                    .highlightedMessageId
                    ?.value ==
                targetId,
        step: const Duration(milliseconds: 50),
        timeout: const Duration(seconds: 15),
        label: 'the linked older reply to be visible and highlighted',
      );
      final previousExceptionPolicy = e2eDrainExceptions;
      e2eDrainExceptions = false;
      addTearDown(() => e2eDrainExceptions = previousExceptionPolicy);

      final room = tester
          .element(find.byType(PostViewScreen))
          .read<ThreadHostCubit>()
          .roomCubit!;
      final result = await postGraphQlAsUser(
        email: fixture.helperEmail,
        restoreEmail: fixture.authorEmail,
        request: GRoomMessageCreateReq(
          (request) => request.vars
            ..beaconId = postId
            ..body = 'New reply from the other participant',
        ),
      );
      final data = result['data'] as Map<String, dynamic>;
      final created = data['RoomMessageCreate'] as Map<String, dynamic>;
      final newReplyId = created['id'] as String;

      // An insert can paint immediately over realtime. Reload the real page as
      // well so the test observes whether the room can keep the linked reply
      // when it applies a snapshot that omits it.
      await room.reloadMessages(silent: true);
      await pumpUntil(
        tester,
        () =>
            room.state.messages.any((message) => message.id == newReplyId) &&
            room.state.messages.every((message) => message.id != page.first.id),
        label: 'the room to apply the new page containing the latest reply',
      );
      await tester.pumpAndSettle();

      expect(
        {
          'linked tile count': target.evaluate().length,
          'linked reply in viewport': targetIsInView(),
          'new reply loaded': room.state.messages.any(
            (message) => message.id == newReplyId,
          ),
          'Flutter exception': tester.takeException(),
        },
        {
          'linked tile count': 1,
          'linked reply in viewport': true,
          'new reply loaded': true,
          'Flutter exception': null,
        },
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
