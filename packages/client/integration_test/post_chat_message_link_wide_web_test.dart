import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/widget/post_root_pin_card.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/widget/basic_chat_body.dart';
import 'package:web/web.dart' as web;

import 'support/e2e_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'an opening-message URL retargets the already-open conversation pane',
    (tester) async {
      await launchApp(app.main);
      final fixture = await bootstrapFixture(
        runId: uniqueRunId('post-opening-pane'),
      );
      await logout(tester);
      await loginAs(tester, fixture.authorEmail);

      final openingBody = uniqueRequestTitle('An open Post conversation');
      final postId = await createPublishedPost(
        body: openingBody,
        recipientIds: [fixture.helperUserId],
      );
      final chat = GetIt.I<BeaconThreadsCase>();
      final opening = (await chat.fetchMessages(beaconId: postId)).singleWhere(
        (message) => message.body == openingBody,
      );
      for (var i = 1; i <= 20; i++) {
        expect(
          await chat.createMessage(beaconId: postId, body: 'Reply $i'),
          isNotNull,
        );
      }

      await goToPath(tester, kPathConversations);
      final listPane = find.byKey(TenturaListDetailLayout.listPaneKey);
      final postRow = find.descendant(
        of: listPane,
        matching: find.byKey(ValueKey(postId)),
      );
      await pumpUntilVisible(tester, postRow);
      await tapAndSettle(tester, postRow);

      final screen = find.byType(PostViewScreen);
      final chatBody = find.byType(BasicChatBody);
      final collapsed = find.byKey(const Key('PostRootPinCard.collapsed'));
      final expanded = find.byKey(const Key('PostRootPinCard.expanded'));
      final replyList = find.descendant(
        of: chatBody,
        matching: find.byType(ListView),
      );
      await pumpUntil(
        tester,
        () =>
            collapsed.evaluate().isNotEmpty &&
            tester.state<BasicChatBodyState>(chatBody).isViewportScrollDone,
        label: 'the open conversation pane to collapse its opening card',
      );
      expect(tester.widget<PostViewScreen>(screen).inPane, isTrue);
      final before = tester.state(screen);
      final scrolling = tester.widget<ListView>(replyList).controller;
      expect(scrolling, isNotNull);
      expect(scrolling?.position.pixels, greaterThan(0));

      web.window.location.hash =
          '/post/view/$postId?is_deep_link=true&tab=threads'
          '&thread=general&message=${opening.id}';
      await pumpUntil(
        tester,
        () =>
            expanded.hitTestable().evaluate().isNotEmpty &&
            tester
                    .state<BasicChatBodyState>(chatBody)
                    .highlightedMessageId
                    .value ==
                opening.id,
        step: const Duration(milliseconds: 25),
        timeout: const Duration(seconds: 15),
        label: 'the open pane to expand and highlight its opening card',
      );

      expect(listPane.hitTestable(), findsOneWidget);
      expect(tester.state(screen), same(before));
      expect(
        tester
            .widget<PostRootPinCard>(find.byType(PostRootPinCard))
            .highlighted,
        isTrue,
      );
      expect(scrolling?.position.pixels, scrolling?.position.minScrollExtent);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
