// A quoted fact with three photos, read back from the server (room-message
// GraphQL → repository → RoomMessageTile): the quote draws the chat album
// widget and a tap on a photo opens the full-screen viewer at that photo
// without toggling the quote. Once in a Request chat and once in a Post chat.
//
// Seeding (pin, photo uploads, attach to the fact, quote, send) uses the
// app's own repositories/cubit; the chat is then re-opened so the message is
// rendered from the server response, not from the optimistic local copy.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/util/beacon_pinned_facts.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_attachment_widgets.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_fact_quote.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

/// 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

BeaconViewCubit _viewCubit(WidgetTester tester) =>
    tester.element(find.byType(BeaconViewScreen).last).read<BeaconViewCubit>();

RoomCubit _roomCubit(WidgetTester tester) => tester
    .element(find.byKey(TestIds.key(TestIds.roomMessageInput)).first)
    .read<RoomCubit>();

Finder _tileWithBody(String body) => find.byWidgetPredicate(
  (w) =>
      w is RoomMessageTile &&
      w.message.body == body &&
      !w.message.id.startsWith('local:'),
);

/// Pins a fact in [beaconId] and gives it three photos, as the signed-in user.
Future<void> _seedFactWithPhotos(String beaconId, String text) async {
  final repo = GetIt.I<BeaconFactCardRepository>();
  await repo.pin(
    beaconId: beaconId,
    factText: text,
    visibility: BeaconFactCardVisibilityBits.room,
  );
  final cards = await repo.list(beaconId: beaconId);
  final card = activePinnedFacts(cards).firstWhere((f) => f.factText == text);
  final staged = <String>[
    for (var i = 0; i < 3; i++)
      await repo.uploadAttachment(
        beaconId: beaconId,
        upload: RoomPendingUpload(
          bytes: _png,
          fileName: 'photo-$i.png',
          mimeType: 'image/png',
        ),
      ),
  ];
  await repo.correct(
    beaconId: beaconId,
    factCardId: card.id,
    newText: text,
    baseRevisionSeq: card.revisionSeq,
    attachmentsJson: '[${staged.join(',')}]',
  );
}

Future<void> _openChat(WidgetTester tester, String beaconId) async {
  await goToPath(tester, '$kPathBeaconView/$beaconId');
  await pumpUntil(
    tester,
    () =>
        finderHasMatch(find.byKey(TestIds.key(TestIds.roomMessageInput))) ||
        finderHasMatch(find.byKey(TestIds.key(TestIds.beaconTabRoom))),
    label: 'chat of $beaconId reachable',
  );
  await enterChatIfNeeded(tester);
  await pumpUntilVisible(
    tester,
    find.byKey(TestIds.key(TestIds.roomMessageInput)),
    label: 'composer',
  );
}

Future<void> _quoteSendReopenAndTapPhoto(
  WidgetTester tester, {
  required String beaconId,
  required String factText,
  required String body,
}) async {
  await _openChat(tester, beaconId);
  final room = _roomCubit(tester);
  await room.refreshFactCards();
  final card = activePinnedFacts(
    room.state.factCards,
  ).firstWhere((f) => f.factText == factText);
  expect(card.attachments, hasLength(3), reason: 'seeded fact has 3 photos');
  room.setPendingQuotedFact(card);
  expect(await room.sendMessage(body: body), isTrue);
  await pumpUntilVisible(tester, _tileWithBody(body));

  // Re-open: the bubble is now built from the server's message list.
  await goToPath(tester, kPathHome);
  await _openChat(tester, beaconId);
  final tile = _tileWithBody(body);
  await pumpUntilVisible(tester, tile, label: 'quote bubble from server');
  await tester.ensureVisible(tile);

  final album = find.descendant(
    of: find.descendant(of: tile, matching: find.byType(RoomMessageFactQuote)),
    matching: find.byType(RoomMessageInlineImageAlbum),
  );
  await pumpUntilVisible(tester, album, label: 'album inside the quote');
  expect(
    find.descendant(of: album, matching: find.text('1/3')),
    findsOneWidget,
  );

  await tester.tap(
    find.descendant(of: album, matching: find.byType(PageView)),
    warnIfMissed: false,
  );
  await pumpSettleBounded(tester);
  final gallery = find.byType(RoomAttachmentFullscreenGallery);
  await pumpUntilVisible(tester, gallery, label: 'full-screen viewer');
  expect(
    tester.widget<RoomAttachmentFullscreenGallery>(gallery).initialIndex,
    0,
  );
  expect(find.text('1 / 3'), findsOneWidget);

  await tapAndSettle(tester, find.byIcon(Icons.close));
  expect(gallery, findsNothing);
  // The photo tap did not expand the quote.
  final quote = find.descendant(
    of: tile,
    matching: find.byType(RoomMessageFactQuote),
  );
  expect(
    find.descendant(of: quote, matching: find.text(factText)),
    findsNothing,
    reason: 'quote stays collapsed to the excerpt after a photo tap',
  );
  expect(
    find.descendant(
      of: quote,
      matching: find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').contains(' photos fact '),
      ),
    ),
    findsOneWidget,
    reason: 'the one-line excerpt is still shown',
  );
  expect(
    find.descendant(of: quote, matching: find.text('Open')),
    findsNothing,
    reason: 'no Open action: the photo tap did not expand the quote',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'quoted fact photos open the viewer from the server-rendered bubble in a '
    'Request chat and a Post chat',
    (tester) async {
      await launchApp(app.main);
      await pumpSettleBounded(tester);
      // The runner's browser window is a phone (375x667 viewport); the
      // desktop surface is covered by the widget tests on RoomMessageTile.
      expect(
        tester.view.physicalSize / tester.view.devicePixelRatio,
        const Size(375, 667),
        reason: 'the app viewport must be 375x667 (a 375x806 window)',
      );
      final runId = uniqueRunId('fact-quote-album');
      final fixture = await bootstrapFixture(runId: runId);
      final title = uniqueRequestTitle('IT quote album');
      // Long enough that the collapsed excerpt differs from the full text.
      final tag = runId.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
      final requestFact =
          'Request photos fact $tag: ${'the north gate stays open ' * 6}'
              .trim();
      final postFact =
          'Post photos fact $tag: ${'the south gate stays open ' * 6}'.trim();

      await logout(tester);
      await createAndForwardRequest(tester, fixture: fixture, title: title);
      await logout(tester);
      await offerHelpFromInbox(tester, fixture: fixture, requestTitle: title);
      await logout(tester);
      await acceptHelpOffer(tester, fixture: fixture, requestTitle: title);

      await runE2eStep('Request chat', () async {
        final beaconId = _viewCubit(tester).state.beacon.id;
        await _seedFactWithPhotos(beaconId, requestFact);
        await _quoteSendReopenAndTapPhoto(
          tester,
          beaconId: beaconId,
          factText: requestFact,
          body: 'Quote with photos in a Request $tag',
        );
      });

      await runE2eStep('Post chat', () async {
        final postId = await createPublishedPost(
          body: uniqueRequestTitle('IT quote album post'),
          recipientIds: [fixture.helperUserId],
        );
        await _seedFactWithPhotos(postId, postFact);
        await _quoteSendReopenAndTapPhoto(
          tester,
          beaconId: postId,
          factText: postFact,
          body: 'Quote with photos in a Post $tag',
        );
      });
    },
  );
}
