// A quoted fact's photos use the same chat album widget and full-screen viewer
// as a direct album message. A tap on a photo opens the viewer; a tap on the
// text toggles the quote.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/quoted_fact.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_attachment_widgets.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_fact_quote.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _kText =
    'The venue moved to 221B Baker Street, second floor, use the side '
    'entrance after 6pm since the main door is locked, and bring your own '
    'badge because the front desk stops issuing guest passes at five.';

List<RoomMessageAttachment> _images(int n) => [
  for (var i = 0; i < n; i++)
    RoomMessageAttachment(
      id: 'a$i',
      kind: BeaconRoomMessageAttachmentKind.image,
      position: i,
      mime: 'image/jpeg',
      sizeBytes: 1,
      imageId: 'img-$i',
      imageAuthorId: 'peer-1',
    ),
];

QuotedFact _quote(int images) => QuotedFact(
  factCardId: 'fact-1',
  seq: 1,
  currentSeq: 1,
  status: BeaconFactCardStatusBits.active,
  factText: _kText,
  pinnedById: 'peer-1',
  pinnedByTitle: 'Peer One',
  attachments: _images(images),
);

Widget _harness(Widget child, {Size size = const Size(375, 667)}) =>
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: SizedBox(width: 340, child: child),
          ),
        ),
      ),
    );

final _album = find.byType(RoomMessageInlineImageAlbum);
final _gallery = find.byType(RoomAttachmentFullscreenGallery);
final _open = find.text('Open');

Future<void> _pump(WidgetTester tester, int images) async {
  await tester.pumpWidget(
    _harness(RoomMessageFactQuote(quotedFact: _quote(images))),
  );
  await tester.pump();
}

Future<void> _tapPhoto(WidgetTester tester) async {
  await tester.tap(
    find.descendant(of: _album, matching: find.byType(Image)).first,
  );
  await tester.pumpAndSettle();
}

Finder get _quoteFinder => find.byType(RoomMessageFactQuote);
Finder get _excerpt => find.descendant(
  of: _quoteFinder,
  matching: find.textContaining('The venue moved'),
);
Finder get _fullText =>
    find.descendant(of: _quoteFinder, matching: find.text(_kText));

/// Page-dot count the chat album draws for [n] photos when it is shown on its
/// own (a direct album message), measured with the same finder the quote's
/// album is measured with.
Future<int> _directAlbumDots(WidgetTester tester, int n) async {
  await tester.pumpWidget(
    _harness(RoomMessageInlineImageAlbum(attachments: _images(n))),
  );
  await tester.pump();
  return _dots.evaluate().length;
}

Finder get _dots =>
    find.descendant(of: _album, matching: find.byType(AnimatedContainer));

Finder _counter(String text) =>
    find.descendant(of: _album, matching: find.text(text));

/// The collapsed quote is one line: excerpt visible, full text and "Open" not.
void _expectCollapsed() {
  expect(_excerpt, findsOneWidget);
  expect(_fullText, findsNothing);
  expect(_open, findsNothing);
}

void main() {
  testWidgets('collapsed 3-image quote shows the chat album with counter 1/3, '
      '3 dots and no other image', (tester) async {
    await _pump(tester, 3);
    expect(_album, findsOneWidget);
    expect(_counter('1/3'), findsOneWidget);
    final quoteDots = _dots.evaluate().length;
    expect(quoteDots, greaterThanOrEqualTo(3));
    expect(
      find.descendant(
        of: _quoteFinder,
        matching: find.byWidgetPredicate(
          (w) => w is ListView && w.scrollDirection == Axis.horizontal,
        ),
      ),
      findsNothing,
    );
    // No image outside the album (no avatar-sized thumbnail of its own).
    final images = find
        .descendant(of: _quoteFinder, matching: find.byType(Image))
        .evaluate()
        .toList();
    expect(images, isNotEmpty);
    for (final e in images) {
      expect(
        e.findAncestorWidgetOfExactType<RoomMessageInlineImageAlbum>(),
        isNotNull,
        reason: 'every image of the quote is drawn by the chat album',
      );
    }
    _expectCollapsed();
    // Same dots as a direct album of the same size (replaces the quote).
    expect(await _directAlbumDots(tester, 3), quoteDots);
  });

  testWidgets('tapping the text expands then collapses the quote around the single '
      'album', (tester) async {
    await _pump(tester, 3);
    await tester.tap(_excerpt);
    await tester.pump();
    expect(_fullText, findsOneWidget);
    expect(_open, findsOneWidget);
    expect(_album, findsOneWidget);
    expect(_counter('1/3'), findsOneWidget);
    expect(_gallery, findsNothing);

    await tester.tap(_fullText);
    await tester.pump();
    _expectCollapsed();
    expect(_album, findsOneWidget);
    expect(_gallery, findsNothing);
  });

  testWidgets('next-page button pages the quote album and leaves the quote '
      'collapsed', (tester) async {
    await _pump(tester, 3);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(_counter('2/3'), findsOneWidget);
    expect(_gallery, findsNothing);
    _expectCollapsed();
  });

  testWidgets('tapping the second photo opens the viewer at index 1 titled '
      '2 / 3', (tester) async {
    await _pump(tester, 3);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    await _tapPhoto(tester);
    expect(_gallery, findsOneWidget);
    expect(
      tester.widget<RoomAttachmentFullscreenGallery>(_gallery).initialIndex,
      1,
    );
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('photo tap leaves the quote collapsed after closing the viewer',
      (tester) async {
    await _pump(tester, 3);
    await _tapPhoto(tester);
    expect(_gallery, findsOneWidget);
    expect(
      tester.widget<RoomAttachmentFullscreenGallery>(_gallery).initialIndex,
      0,
    );
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(_gallery, findsNothing);
    expect(_album, findsOneWidget);
    _expectCollapsed();
  });

  testWidgets('single-image quote has no counter and no dots and opens the '
      'viewer at 0', (tester) async {
    await _pump(tester, 1);
    expect(_album, findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d+/\d+$')), findsNothing);
    expect(_dots, findsNothing);
    await _tapPhoto(tester);
    expect(_gallery, findsOneWidget);
    expect(
      tester.widget<RoomAttachmentFullscreenGallery>(_gallery).initialIndex,
      0,
    );
    expect(find.textContaining(RegExp(r'^\d+ / \d+$')), findsNothing);
  });
}
