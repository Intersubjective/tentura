// Fact continuity, a Post's facts (plan docs/plans/fact-continuity-architecture.md
// §8 web integration row, acceptance scenario 6; D2, D17).
//
// Alice publishes a Post to Bob. Bob owns two Requests R1 and R2. Alice
// writes an ordinary message and sees it as the last message of the Posts
// list row. Bob pins it as a fact (a UI gesture) and sees it in the Post info
// sheet; Alice's row keeps the same last message and unread count. Bob copies
// the fact into R1, Alice ends the Post, and Bob still sees the fact — no Edit
// or Unpin in its actions, and a correction sent to the server is refused —
// and copies it from the archive into R2. The Post stays closed throughout.
//
// Pin, copies, the close and every list read are the app's own UI paths over
// the local server. Bob's direct correction goes through [postGraphQlAsUser],
// as in fact_copy_chain_origin_walk_test.dart.
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_threads/data/gql/_g/beacon_fact_card_correct.req.gql.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_provenance_line.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_fact_card.dart';
import 'package:tentura/features/inbox/ui/widget/post_conversation_row.dart';
import 'package:tentura/features/post_view/ui/widget/post_action.dart';
import 'package:tentura/features/post_view/ui/widget/post_info_sheet.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

late L10n _l10n;

TestGesture? _mouse;

/// One desktop mouse for the whole run, added once and then moved: a second
/// `addPointer` over a pointer that was never removed trips the mouse tracker.
Future<TestGesture> _hoverAt(WidgetTester tester, Offset at) async {
  final existing = _mouse;
  if (existing != null) {
    await existing.moveTo(at);
    return existing;
  }
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: at);
  return _mouse = mouse;
}

Finder _action(String label) => find.widgetWithText(ListTile, label).last;

Finder get _composer => find.byKey(TestIds.key(TestIds.roomMessageInput));

Finder _tileWithBody(String body) => find.byWidgetPredicate(
  (w) =>
      w is RoomMessageTile &&
      w.message.body == body &&
      !w.message.id.startsWith('local:'),
);

Finder _factCardWithText(String beaconId, String text) =>
    find.byWidgetPredicate(
      (w) =>
          w is BeaconPinnedFactCard &&
          w.fact.beaconId == beaconId &&
          w.fact.factText == text,
    );

Finder _postRow(String postId) => find.byWidgetPredicate(
  (w) => w is PostConversationRow && w.post.id == postId,
);

void _expectSignedInAs(String userId, String who) => expect(
  GetIt.I<ProfileCubit>().state.profile.id,
  userId,
  reason: 'expected to be signed in as $who',
);

Future<void> _switchTo(
  WidgetTester tester, {
  required String email,
  required String userId,
  required String who,
}) async {
  await logout(tester);
  await loginAs(tester, email);
  await pumpUntil(
    tester,
    () => GetIt.I<ProfileCubit>().state.profile.id == userId,
    label: 'profile switched to $who',
  );
}

bool _anySheetOpen() =>
    find.byType(Material).evaluate().any((e) => ModalRoute.of(e) is PopupRoute);

Future<void> _closeSheets(WidgetTester tester) async {
  for (var i = 0; i < 6 && _anySheetOpen(); i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpSettleBounded(tester);
  }
  expect(_anySheetOpen(), isFalse, reason: 'sheets left open over the page');
}

/// Opens the Post at [postId] with its conversation loaded (the root message
/// shown), so a later send or sheet does not race the room's first load.
Future<void> _openPost(
  WidgetTester tester,
  String postId, {
  required String rootBody,
}) async {
  await _closeSheets(tester);
  await goToDeepLink(tester, '$kPathBeaconView/$postId');
  await pumpUntilVisible(
    tester,
    find.textContaining(rootBody).first,
    label: 'Post conversation loaded',
  );
}

/// ⋮ → «About this post»; waits for the sheet.
Future<void> _openPostInfo(WidgetTester tester) async {
  await tapAndSettle(tester, find.byType(PopupMenuButton<PostAction>).first);
  await tapAndSettle(
    tester,
    find.widgetWithText(PopupMenuItem<PostAction>, _l10n.postMenuInfo),
  );
  await pumpUntilVisible(tester, find.byType(PostInfoSheet));
}

Finder get _factsInPostInfo => find.descendant(
  of: find.byType(PostInfoSheet),
  matching: find.byType(BeaconPinnedFactCard),
);

/// Opens [card]'s actions the way a desktop web user does: the hover «More»
/// button when the card offers one, a secondary click otherwise.
Future<void> _openFactActions(WidgetTester tester, Finder card) async {
  await pumpUntilVisible(tester, card);
  await tester.ensureVisible(card);
  final mouse = await _hoverAt(tester, tester.getCenter(card));
  await pumpSettleBounded(tester);
  final more = find.descendant(
    of: card,
    matching: find.widgetWithIcon(IconButton, Icons.more_horiz),
  );
  final sheetTitle = find.text(_l10n.beaconRoomFactManageSheetTitle);
  if (finderHasMatch(more)) {
    await tester.tap(more);
    await pumpSettleBounded(tester);
  } else {
    final provenance = find.descendant(
      of: card,
      matching: find.byType(FactProvenanceLine),
    );
    await mouse.moveTo(tester.getCenter(provenance));
    final secondary = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await secondary.down(tester.getCenter(provenance));
    await secondary.up();
    await pumpSettleBounded(tester);
    if (!await tryPumpUntilVisible(tester, sheetTitle)) {
      await tester.tap(provenance);
      await pumpSettleBounded(tester);
    }
  }
  await pumpUntilVisible(tester, sheetTitle, label: 'fact actions sheet');
}

Future<void> _copyThroughUi(
  WidgetTester tester, {
  required Finder card,
  required String destinationTitle,
}) async {
  await _openFactActions(tester, card);
  await tapAndSettle(
    tester,
    _action(_l10n.beaconRoomFactCardActionUseElsewhere),
  );
  await tapAndSettle(
    tester,
    find.widgetWithText(ListTile, destinationTitle).last,
  );
  await pumpUntilVisible(
    tester,
    find.text(
      _l10n.beaconFactCopyCopiedTo(destinationTitle),
      findRichText: true,
    ),
    label: 'Copied to $destinationTitle snackbar',
  );
}

/// Request [beaconId]'s facts sheet lists a fact with [text] brought from a
/// Post.
Future<void> _expectCopyInRequest(
  WidgetTester tester, {
  required String beaconId,
  required String text,
}) async {
  await _closeSheets(tester);
  await goToPath(tester, '$kPathBeaconView/$beaconId');
  await pumpUntilVisible(tester, find.byType(BeaconViewScreen));
  final tabNow = find.byKey(TestIds.key(TestIds.beaconTabNow));
  await pumpUntilVisible(tester, tabNow, label: 'Request $beaconId tab now');
  await tapAndSettle(tester, tabNow);
  final open = find.byKey(TestIds.key(TestIds.beaconFactsOpen));
  await pumpUntilVisible(tester, open);
  await tester.ensureVisible(open);
  await tapAndSettle(tester, open);
  final card = _factCardWithText(beaconId, text);
  await pumpUntilVisible(tester, card, label: 'copy listed in $beaconId');
  expect(
    find.descendant(
      of: card,
      matching: find.text(_l10n.beaconRoomFactOriginFromPost),
    ),
    findsOneWidget,
  );
}

PostConversationRow _row(String postId) =>
    _postRow(postId).evaluate().single.widget as PostConversationRow;

/// The Posts list row of [postId], freshly loaded.
Future<PostConversationRow> _readPostRow(
  WidgetTester tester,
  String postId, {
  bool archived = false,
}) async {
  await _closeSheets(tester);
  await goToPath(tester, kPathConversations);
  if (archived) {
    // A closed Post leaves «Active» for the archive view.
    final active = find.text(_l10n.postsFilterActive);
    await pumpUntilVisible(tester, active, label: 'Posts filter control');
    await tapAndSettle(tester, active.first);
    await tapAndSettle(tester, find.text(_l10n.postsTabArchive).last);
  }
  await pumpUntilVisible(tester, _postRow(postId), label: 'Posts list row');
  return _row(postId);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a Post fact pinned by a member shows in the Post info sheet without '
    'touching the Posts list, is copied into a Request, and stays listed, '
    'uneditable and copyable after the Post is closed',
    (tester) async {
      _l10n = await L10n.delegate.load(const Locale('en'));
      expect(_l10n.postClosedMarker, 'closed');
      expect(_l10n.beaconRoomFactOriginFromPost, 'Brought from another Post');
      expect(_l10n.postInfoFactsHeading, 'Facts');
      await launchApp(app.main);
      await pumpSettleBounded(tester);

      final fixture = await bootstrapFixture(
        runId: uniqueRunId('fact-post'),
      );
      final aliceEmail = fixture.authorEmail;
      final aliceId = fixture.authorUserId;
      final bobEmail = fixture.helperEmail;
      final bobId = fixture.helperUserId;

      final rootBody = uniqueRequestTitle('IT fact post root');
      final factText = uniqueRequestTitle('IT fact post spare keys');
      final titleR1 = uniqueRequestTitle('IT fact post R1');
      final titleR2 = uniqueRequestTitle('IT fact post R2');

      await _switchTo(tester, email: bobEmail, userId: bobId, who: 'Bob');
      final r1 = await createPublishedBeacon(title: titleR1);
      final r2 = await createPublishedBeacon(title: titleR2);

      await _switchTo(tester, email: aliceEmail, userId: aliceId, who: 'Alice');
      final postId = await createPublishedPost(
        body: rootBody,
        recipientIds: [bobId],
      );

      late int unreadBefore;
      await runE2eStep(
        'Alice sends an ordinary message; her row shows it',
        () async {
          _expectSignedInAs(aliceId, 'Alice');
          await _openPost(tester, postId, rootBody: rootBody);
          await pumpUntilVisible(tester, _composer, label: 'composer');
          await sendRoomMessage(tester, factText);
          final row = await _readPostRow(tester, postId);
          expect(row.post.lastMessageExcerpt?.trim(), factText);
          unreadBefore = row.post.unreadCount;
          expect(unreadBefore, 0);
        },
      );

      await _switchTo(tester, email: bobEmail, userId: bobId, who: 'Bob');

      late String factId;
      await runE2eStep('Bob pins the message as a fact', () async {
        await _openPost(tester, postId, rootBody: rootBody);
        final tile = _tileWithBody(factText);
        await pumpUntilVisible(tester, tile);
        await tester.ensureVisible(tile);
        await _hoverAt(
          tester,
          tester.getCenter(
            find.descendant(
              of: tile,
              matching: find.byType(RoomMessageTextBody),
            ),
          ),
        );
        await pumpSettleBounded(tester);
        final more = find.descendant(
          of: tile,
          matching: find.widgetWithIcon(IconButton, Icons.more_horiz),
        );
        await pumpUntilVisible(tester, more);
        await tester.tap(more);
        await pumpSettleBounded(tester);
        await tapAndSettle(tester, _action(_l10n.beaconRoomActionPinFact));
        RoomCubit room() => tester
            .element(find.byType(RoomMessageTile).first)
            .read<RoomCubit>();
        await pumpUntil(
          tester,
          () => room().state.factCards.any((f) => f.factText == factText),
          label: 'fact pinned in the Post',
        );
        factId = room().state.factCards
            .firstWhere((f) => f.factText == factText)
            .id;
      });

      await runE2eStep('the Post info sheet lists the fact', () async {
        await _openPostInfo(tester);
        await pumpUntilVisible(tester, find.text(_l10n.postInfoFactsHeading));
        expect(_factsInPostInfo, findsOneWidget);
        final shown = tester
            .widget<BeaconPinnedFactCard>(_factsInPostInfo)
            .fact;
        expect(shown.id, factId);
        expect(shown.factText, factText);
      });

      await runE2eStep('Bob copies the fact into R1', () async {
        await _copyThroughUi(
          tester,
          card: _factsInPostInfo,
          destinationTitle: titleR1,
        );
        await _expectCopyInRequest(tester, beaconId: r1, text: factText);
      });

      await _switchTo(tester, email: aliceEmail, userId: aliceId, who: 'Alice');

      await runE2eStep(
        "the pin leaves Alice's row without a blank message or new unread",
        () async {
          final row = await _readPostRow(tester, postId);
          expect(row.post.lastMessageExcerpt?.trim(), factText);
          expect(row.post.unreadCount, unreadBefore);
        },
      );

      await runE2eStep('Alice ends the Post', () async {
        await _openPost(tester, postId, rootBody: rootBody);
        await tapAndSettle(
          tester,
          find.byType(PopupMenuButton<PostAction>).first,
        );
        await tapAndSettle(
          tester,
          find.widgetWithText(
            PopupMenuItem<PostAction>,
            _l10n.postActionCloseNow,
          ),
        );
        await pumpUntilVisible(
          tester,
          find.text(_l10n.postCloseNowConfirmTitle),
        );
        await tapAndSettle(
          tester,
          find.widgetWithText(FilledButton, _l10n.postActionCloseNow),
        );
        await pumpUntil(
          tester,
          () => !finderHasMatch(_composer),
          label: 'composer gone after the Post is closed',
        );
        final row = await _readPostRow(tester, postId, archived: true);
        expect(row.post.isClosed, isTrue);
        expect(
          find.descendant(
            of: _postRow(postId),
            matching: find.text(_l10n.postClosedMarker),
          ),
          findsOneWidget,
        );
      });

      await _switchTo(tester, email: bobEmail, userId: bobId, who: 'Bob');

      await runE2eStep('the closed Post still lists the fact', () async {
        await _openPost(tester, postId, rootBody: rootBody);
        expect(_composer, findsNothing);
        await _openPostInfo(tester);
        await pumpUntilVisible(tester, find.text(_l10n.postInfoFactsHeading));
        expect(_factsInPostInfo, findsOneWidget);
        expect(
          tester.widget<BeaconPinnedFactCard>(_factsInPostInfo).fact.factText,
          factText,
        );
      });

      await runE2eStep('the archived fact cannot be edited in the UI', () async {
        await _openFactActions(tester, _factsInPostInfo);
        expect(find.text(_l10n.beaconRoomFactCardActionEdit), findsNothing);
        expect(find.text(_l10n.beaconRoomFactCardActionRemove), findsNothing);
        expect(
          find.text(_l10n.beaconRoomFactCardActionUseElsewhere),
          findsOneWidget,
        );
        expect(find.text(_l10n.beaconRoomFactCardActionCopy), findsOneWidget);
        await _closeSheets(tester);
      });

      await runE2eStep('the server refuses a correction', () async {
        await expectLater(
          postGraphQlAsUser(
            email: bobEmail,
            restoreEmail: bobEmail,
            request: GBeaconFactCardCorrectReq(
              (b) => b.vars
                ..beaconId = postId
                ..factCardId = factId
                ..newText = '$factText (edited)'
                ..baseRevisionSeq = 1,
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('GraphQL as'),
            ),
          ),
        );
        await _openPost(tester, postId, rootBody: rootBody);
        await _openPostInfo(tester);
        await pumpUntilVisible(tester, _factsInPostInfo);
        expect(
          tester.widget<BeaconPinnedFactCard>(_factsInPostInfo).fact.factText,
          factText,
        );
      });

      await runE2eStep('Bob copies the archived fact into R2', () async {
        await _copyThroughUi(
          tester,
          card: _factsInPostInfo,
          destinationTitle: titleR2,
        );
        await _expectCopyInRequest(tester, beaconId: r2, text: factText);
      });

      await runE2eStep('the Post stays closed', () async {
        await _openPost(tester, postId, rootBody: rootBody);
        expect(_composer, findsNothing);
        final row = await _readPostRow(tester, postId, archived: true);
        expect(row.post.isClosed, isTrue);
        expect(
          find.descendant(
            of: _postRow(postId),
            matching: find.text(_l10n.postClosedMarker),
          ),
          findsOneWidget,
        );
      });
    },
  );
}
