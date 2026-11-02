// #945: in Message actions the line under the reaction grid (the hint, or
// the hovered / held emoji's meaning) wraps to two lines instead of being cut
// to one with an ellipsis (RU «Наведите или удерживайте эмодзи, чтобы увидеть
// его значение» did not fit at 375 px), and it always reserves two lines, so
// the sheet below does not move when the hint turns into a meaning and back.
//
// Sibling matrix: hint and every meaning preview; RU and EN at 375×667;
// desktop EN (hover hint → preview → hint).

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/reaction_quick_picker.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

import '../../support/phone_surface.dart';
import 'support/room_body_harness.dart';

const _viewer = Profile(id: 'me', displayName: 'Me');
const _other = Profile(id: 'other', displayName: 'Alex');

RoomMessage _message() => RoomMessage(
  id: 'm1',
  beaconId: 'b1',
  authorId: _other.id,
  author: _other,
  body: 'We need a ladder on Saturday',
  createdAt: DateTime.utc(2026, 11, 2, 9),
);

Future<void> _pumpRequestRoom(
  WidgetTester tester, {
  required Locale locale,
  required Size size,
}) async {
  final state =
      roomBodyState(
        messages: [_message()],
      ).copyWith(
        participants: [
          roomBodyAdmittedParticipant(beaconId: 'b1', profile: _viewer),
          roomBodyAdmittedParticipant(beaconId: 'b1', profile: _other),
        ],
        participantsLoaded: true,
      );
  await pumpBeaconRoomBody(
    tester,
    roomState: state,
    width: size.width,
    height: size.height,
    enableComposer: false,
    locale: locale,
  );
  await tester.pump(const Duration(milliseconds: 500));
}

Finder _messageBody() {
  final inline = find.byType(RoomMessageTextBody);
  return inline.evaluate().isNotEmpty ? inline : find.byType(ShowMoreText);
}

/// Opens Message actions on the message: a long-press, or a right click with
/// [mouse] (which then stays over the sheet for hovering).
Future<void> _openActions(WidgetTester tester, {TestGesture? mouse}) async {
  final at = tester.getTopLeft(_messageBody().first) + const Offset(8, 8);
  if (mouse != null) {
    await mouse.down(at);
    await mouse.up();
  } else {
    await tester.longPressAt(at);
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.byType(BottomSheet), findsOneWidget);
  expect(find.byType(ReactionQuickPicker), findsOneWidget);
}

/// The line under the emoji grid, whichever state it is in.
Finder _line(L10n l10n) => find.descendant(
  of: find.byType(ReactionQuickPicker),
  matching: find.byWidgetPredicate(
    (w) =>
        w is Text &&
        w.data != null &&
        (w.data == l10n.beaconRoomReactionPickerHint ||
            BeaconRoomMessageReaction.quickPickerEmojis.any(
              (e) => w.data == '$e  ${reactionEmojiMeaning(l10n, e)}',
            )),
  ),
);

/// One line of the line's text style (forced strut: fontSize × height).
double _lineHeight(WidgetTester tester, L10n l10n) {
  final style = tester.widget<Text>(_line(l10n)).style!;
  return style.fontSize! * style.height!;
}

RenderParagraph _paragraph(WidgetTester tester, L10n l10n) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: _line(l10n), matching: find.byType(RichText)),
    );

/// The line shows [text] in full: nothing cut, at most two lines, and its
/// box is exactly two lines tall.
void _expectTwoLineSlot(WidgetTester tester, L10n l10n, String text) {
  final line = tester.widget<Text>(_line(l10n));
  expect(line.data, text);
  final paragraph = _paragraph(tester, l10n);
  expect(paragraph.didExceedMaxLines, isFalse, reason: 'ellipsized: $text');
  expect(
    tester.getSize(_line(l10n)).height,
    moreOrLessEquals(2 * _lineHeight(tester, l10n), epsilon: 0.01),
    reason: 'the line reserves two lines: $text',
  );
}

/// The top of the first thing below the picker in the sheet.
double _belowTop(WidgetTester tester) {
  final picker = tester.getRect(find.byType(ReactionQuickPicker));
  return picker.bottom;
}

/// Real Inter (Cyrillic included), so widths are the ones a phone measures,
/// not the square test font's.
Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final weight in const ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('fonts/Inter-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadInter);
  final ru = L10nRu();
  final en = L10nEn();
  const pray = '\u{1F64F}';

  group('#945 phone 375×667', () {
    testWidgets('RU: the full hint wraps to two lines, not ellipsized', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await _pumpRequestRoom(
        tester,
        locale: const Locale('ru'),
        size: kPhoneSurface,
      );
      await _openActions(tester);

      _expectTwoLineSlot(tester, ru, ru.beaconRoomReactionPickerHint);
      // It really needs the second line at this width.
      final boxes = _paragraph(tester, ru).getBoxesForSelection(
        TextSelection(
          baseOffset: 0,
          extentOffset: ru.beaconRoomReactionPickerHint.length,
        ),
      );
      final lineTops = boxes.map((b) => b.top.round()).toSet();
      expect(lineTops.length, 2, reason: 'RU hint wraps at 375 px');
    });

    testWidgets('RU: every meaning preview fits, same height as the hint; '
        'the sheet below does not move', (tester) async {
      await usePhoneSurface(tester);
      await _pumpRequestRoom(
        tester,
        locale: const Locale('ru'),
        size: kPhoneSurface,
      );
      await _openActions(tester);
      final hintHeight = tester.getSize(_line(ru)).height;
      final hintBelow = _belowTop(tester);

      for (final emoji in BeaconRoomMessageReaction.quickPickerEmojis) {
        await tester.longPress(
          find.descendant(
            of: find.byType(ReactionQuickPicker),
            matching: find.text(emoji),
          ),
        );
        await tester.pump();
        final text = '$emoji  ${reactionEmojiMeaning(ru, emoji)}';
        _expectTwoLineSlot(tester, ru, text);
        expect(tester.getSize(_line(ru)).height, hintHeight, reason: text);
        expect(_belowTop(tester), hintBelow, reason: text);
      }
    });

    testWidgets('EN: the hint is not ellipsized and reserves the same two '
        'lines as a preview', (tester) async {
      await usePhoneSurface(tester);
      await _pumpRequestRoom(
        tester,
        locale: const Locale('en'),
        size: kPhoneSurface,
      );
      await _openActions(tester);
      _expectTwoLineSlot(tester, en, en.beaconRoomReactionPickerHint);
      final hintBelow = _belowTop(tester);

      await tester.longPress(
        find.descendant(
          of: find.byType(ReactionQuickPicker),
          matching: find.text(pray),
        ),
      );
      await tester.pump();
      _expectTwoLineSlot(
        tester,
        en,
        '$pray  ${en.beaconRoomReactionMeaningThanks}',
      );
      expect(_belowTop(tester), hintBelow);
    });
  });

  testWidgets(
    '#945 desktop EN: hover hint → preview → hint keeps two lines and the '
    'sheet still',
    (tester) async {
      await _pumpRequestRoom(
        tester,
        locale: const Locale('en'),
        size: const Size(1280, 800),
      );
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await _openActions(tester, mouse: mouse);
      _expectTwoLineSlot(tester, en, en.beaconRoomReactionPickerHint);
      final hintBelow = _belowTop(tester);
      await mouse.moveTo(
        tester.getCenter(
          find.descendant(
            of: find.byType(ReactionQuickPicker),
            matching: find.text(pray),
          ),
        ),
      );
      await tester.pump();
      _expectTwoLineSlot(
        tester,
        en,
        '$pray  ${en.beaconRoomReactionMeaningThanks}',
      );
      expect(_belowTop(tester), hintBelow);

      await mouse.moveTo(Offset.zero);
      await tester.pump();
      _expectTwoLineSlot(tester, en, en.beaconRoomReactionPickerHint);
      expect(_belowTop(tester), hintBelow);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
