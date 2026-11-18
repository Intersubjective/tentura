import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/widget/basic_chat_body.dart';

import 'support/e2e_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a Post message link scrolls to and highlights an older reply', (
    tester,
  ) async {
    await launchApp(app.main);
    final fixture = await bootstrapFixture(
      runId: uniqueRunId('post-message-link'),
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
      body: 'The earlier reply',
    );
    expect(targetId, isNotNull);
    for (var i = 1; i <= 50; i++) {
      // Use both members of the conversation so neither exceeds the per-user
      // rate limit while preparing a chat longer than one page.
      if (i == 25) {
        await logout(tester);
        await loginAs(tester, fixture.authorEmail);
      }
      final id = await chat.createMessage(
        beaconId: postId,
        body: 'Newer reply $i',
      );
      expect(id, isNotNull);
    }
    final latest = await chat.fetchMessages(beaconId: postId);
    expect(latest, hasLength(50));
    expect(latest.map((message) => message.id), isNot(contains(targetId)));

    await goToDeepLink(tester, '/post/view/$postId?message=$targetId');
    final chatBody = find.byType(BasicChatBody);
    final target = find.byWidgetPredicate(
      (widget) => widget is RoomMessageTile && widget.message.id == targetId,
    );
    final viewport = find.ancestor(of: target, matching: find.byType(Viewport));
    await pumpUntil(
      tester,
      () {
        if (target.evaluate().isEmpty) return false;
        final tile = tester.widget<RoomMessageTile>(target);
        if (tile.highlightedMessageId?.value != targetId) return false;
        final positioned = tester
            .state<BasicChatBodyState>(chatBody)
            .isViewportScrollDone;
        return positioned &&
            tester.getRect(viewport.first).contains(tester.getCenter(target));
      },
      step: const Duration(milliseconds: 50),
      label: 'the earlier reply to be inside the chat viewport and highlighted',
      timeout: const Duration(seconds: 15),
    );
    expect(find.byType(PostViewScreen), findsOneWidget);
    expect(
      tester
          .widget<BasicChatBody>(chatBody)
          .messages
          .map((message) => message.body),
      contains('Newer reply 50'),
    );
    // The rich text may end with an invisible inline timestamp spacer.
    final body = find.descendant(
      of: target,
      matching: find.textContaining(RegExp(r'^The earlier reply\uFFFC?$')),
    );
    expect(body, findsOneWidget);
    expect(
      tester.getRect(viewport.first).contains(tester.getCenter(body)),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
