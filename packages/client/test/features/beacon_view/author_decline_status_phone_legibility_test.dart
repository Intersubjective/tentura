// On a phone the Request app bar must show the author's whole decline line
// (#486): "Looking for helpers · 2 of 2 declined — forward to someone else",
// in English and Russian. The guidance at the end is the point of the line, so
// it may wrap to another line but is never cut off, clipped by the top bar or
// left to overflow. The desktop (split) layout keeps its one-line subtitle.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_anchor_status.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'beacon_view_screen_harness.dart';

const _phone = Size(375, 667);

// Wide enough that the split layout's header pane fits the line on one row
// even with the test font's wide glyphs.
const _wideDesktop = Size(1920, 1080);

final _t = DateTime.utc(2026, 6, 20);

BeaconViewState _authorWithEveryForwardDeclined() {
  final base = beaconViewHarnessAuthorState();
  final author = base.myProfile;
  ForwardEdge declined(String id) => ForwardEdge(
    id: 'e-$id',
    beaconId: base.beacon.id,
    createdAt: _t,
    sender: author,
    recipient: Profile(id: id, displayName: id),
    recipientRejected: true,
  );
  return base.copyWith(
    myForwards: [declined('r1'), declined('r2')],
    forwardsLoaded: true,
  );
}

Finder get _topBar => find.byType(TenturaTopBar);

String _normalized(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

/// Every text paragraph in the top bar that carries a piece of the status line
/// (the status verb, the decline count or the forward guidance). The Request
/// title shares the bar but is not part of the status, so it is left out. How
/// the pieces are arranged (one wrapped paragraph, or one row per piece) is up
/// to the layout.
List<RenderParagraph> _statusParagraphs(
  WidgetTester tester, {
  required List<String> pieces,
}) {
  final finder = find.descendant(
    of: _topBar,
    matching: find.byWidgetPredicate(
      (w) =>
          w is RichText &&
          pieces.any(
            (piece) => _normalized(w.text.toPlainText()).contains(piece),
          ),
    ),
  );
  return [
    for (final e in finder.evaluate())
      tester.renderObject<RenderParagraph>(find.byWidget(e.widget)),
  ];
}

/// Everything the user can read of the status line, in on-screen order.
String _statusText(List<RenderParagraph> paragraphs) =>
    _normalized(paragraphs.map((p) => p.text.toPlainText()).join(' '));

TextPainter _unlimitedPainter(RenderParagraph p) => TextPainter(
  text: p.text,
  textDirection: TextDirection.ltr,
  textScaler: p.textScaler,
  locale: p.locale,
)..layout(maxWidth: p.size.width);

/// Height the text needs when it may use as many lines as it wants.
double _fullTextHeight(RenderParagraph p) {
  final painter = _unlimitedPainter(p);
  final height = painter.height;
  painter.dispose();
  return height;
}

int _fullTextLineCount(RenderParagraph p) {
  final painter = _unlimitedPainter(p);
  final lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines;
}

/// The paragraph shows all of its text: no ellipsis, no dropped lines.
void _expectNotTruncated(RenderParagraph p) {
  expect(
    p.text.toPlainText(),
    isNot(contains('…')),
    reason: 'the text itself must not be shortened',
  );
  expect(
    p.didExceedMaxLines,
    isFalse,
    reason: 'the line must not be truncated with an ellipsis',
  );
  expect(
    p.size.height,
    closeTo(_fullTextHeight(p), 0.5),
    reason: 'every line of the text is laid out',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await registerBeaconViewHarnessGetIt();
  });

  tearDown(() async {
    await unregisterBeaconViewHarnessGetIt();
  });

  for (final (locale, count, guidance) in [
    (const Locale('en'), '2 of 2 declined', 'forward to someone else'),
    (const Locale('ru'), 'отказались: 2 из 2', 'перешлите кому-то ещё'),
  ]) {
    final lang = locale.languageCode;
    final slots = beaconViewStatusSlots(
      lookupL10n(locale),
      _authorWithEveryForwardDeclined(),
    );
    final pieces = [_normalized(slots.slot1), count, guidance];

    group('phone app bar status line ($lang), everyone declined', () {
      testWidgets('shows the whole guidance without cutting it off', (
        tester,
      ) async {
        await pumpBeaconViewHarness(
          tester,
          size: _phone,
          locale: locale,
          beaconState: _authorWithEveryForwardDeclined(),
          threadsState: beaconViewHarnessThreadsState(),
        );

        final paragraphs = _statusParagraphs(tester, pieces: pieces);
        final text = _statusText(paragraphs);

        expect(paragraphs, isNotEmpty, reason: 'status line not rendered');
        for (final piece in pieces) {
          expect(text, contains(piece), reason: 'status line misses "$piece"');
        }
        paragraphs.forEach(_expectNotTruncated);
        expect(tester.takeException(), isNull, reason: 'no layout overflow');
      });

      testWidgets('keeps the guidance inside the top bar, not clipped', (
        tester,
      ) async {
        await pumpBeaconViewHarness(
          tester,
          size: _phone,
          locale: locale,
          beaconState: _authorWithEveryForwardDeclined(),
          threadsState: beaconViewHarnessThreadsState(),
        );

        final guidanceParagraphs = _statusParagraphs(
          tester,
          pieces: [guidance],
        );
        expect(guidanceParagraphs, isNotEmpty, reason: 'guidance not shown');
        final bar = tester.getRect(_topBar);

        for (final paragraph in guidanceParagraphs) {
          final box = paragraph.localToGlobal(Offset.zero) & paragraph.size;
          expect(box.left, greaterThanOrEqualTo(bar.left));
          expect(box.right, lessThanOrEqualTo(bar.right));
          expect(box.bottom, lessThanOrEqualTo(bar.bottom + 0.5));
        }
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets(
    'split desktop header keeps the status as one combined one-line subtitle',
    (tester) async {
      final slots = beaconViewStatusSlots(
        lookupL10n(const Locale('en')),
        _authorWithEveryForwardDeclined(),
      );
      await pumpBeaconViewHarness(
        tester,
        size: _wideDesktop,
        beaconState: _authorWithEveryForwardDeclined(),
        threadsState: beaconViewHarnessThreadsState(),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byKey(beaconSplitChatHeaderKey).evaluate().isNotEmpty &&
            find.byType(TenturaVerticalResizeHandle).evaluate().isNotEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();

      // The expanded split chrome is what this test guards.
      expect(find.byType(TenturaVerticalResizeHandle), findsOneWidget);
      expect(find.byKey(beaconSplitChatHeaderKey), findsOneWidget);

      final subtitles = find.descendant(
        of: find.byKey(beaconSplitChatHeaderKey),
        matching: find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              _normalized(w.text.toPlainText()).contains(
                _normalized(slots.slot1),
              ),
        ),
      );
      // One subtitle paragraph carrying "slot1 · slot2" whole; the status is
      // not split into a row per piece.
      expect(subtitles, findsOneWidget);
      final subtitle = tester.renderObject<RenderParagraph>(subtitles);
      expect(
        _normalized(subtitle.text.toPlainText()),
        _normalized(slots.displayLine),
      );
      _expectNotTruncated(subtitle);
      expect(
        _fullTextLineCount(subtitle),
        1,
        reason: 'plenty of width on desktop: one line, as before',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
