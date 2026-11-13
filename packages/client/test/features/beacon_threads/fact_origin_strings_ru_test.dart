// Every new string of the copied-fact UI has an English and a Russian ARB
// entry, and in Russian on a 375x667 phone each one renders inside the
// screen without overflow: the origin line (Request and Post), «Use in
// another Request», the unavailable snackbar, and the history footer with
// its Open button (a Russian «Open» from the ARB files). (The arrival note and «See the copied version» are
// checked in Russian in beacon_view/fact_origin_arrival_test.dart.)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_actions_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'fact_origin_test_support.dart';
import 'room_cubit_fakes.dart';

const _ru = Locale('ru');
const _phone = Size(375, 667);

const _newStrings = [
  kOriginFromRequest,
  kOriginFromPost,
  kOriginUnavailable,
  kChangedSinceCopied,
  kSeeCopiedVersion,
  kUseInAnotherRequest,
  kEarlierHistoryFooter,
];

/// [richText]: the text is a bare RichText (the app's snackbar), not a Text.
void _expectOnPhone(
  WidgetTester tester,
  String text, {
  bool richText = false,
}) {
  final f = find.text(text, findRichText: richText);
  expect(f, findsOneWidget, reason: '«$text» is shown');
  final r = tester.getRect(f);
  expect(r.left, greaterThanOrEqualTo(0), reason: '«$text» left edge');
  expect(r.right, lessThanOrEqualTo(_phone.width), reason: '«$text» right');
  expect(r.top, greaterThanOrEqualTo(0), reason: '«$text» top');
  expect(r.bottom, lessThanOrEqualTo(_phone.height), reason: '«$text» bottom');
  expect(tester.takeException(), isNull);
}

void _openHostSheet(BuildContext context, BeaconFactCard fact) => unawaited(
  showFactActionsHostSheet(
    context,
    fact: fact,
    canMutate: false,
    onCorrect:
        ({required factCardId, required newText, attachmentsJson}) async {},
    onRemove: ({required factCardId}) async {},
    onSetVisibility: ({required factCardId, required visibility}) async {},
  ),
);

Future<RoomCubit> _loadedRoom() async {
  registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
  final fakeRoom = FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId);
  addTearDown(fakeRoom.dispose);
  final cubit = roomCubitForTest(fakeRoom);
  addTearDown(cubit.close);
  await awaitRoomCubitLoad(cubit);
  return cubit;
}

/// Russian history of [fact] opened from the room's actions sheet; returns
/// every text on screen.
Future<Set<String>> _ruHistoryTexts(
  WidgetTester tester,
  BeaconFactCard fact,
) async {
  registerFactRepository(FakeOriginFactCardRepository(historyLength: 2));
  final cubit = await _loadedRoom();
  await tester.pumpWidget(const SizedBox());
  await pumpOpener(
    tester,
    locale: _ru,
    size: _phone,
    open: (ctx) =>
        unawaited(showFactActionsSheet(ctx, cubit: cubit, fact: fact)),
  );
  final l10n = await L10n.delegate.load(_ru);
  await tester.tap(find.text(l10n.beaconRoomFactCardActionEditHistory));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return {
    for (final w in tester.widgetList<RichText>(find.byType(RichText)))
      if (w.text.toPlainText().trim().isNotEmpty) w.text.toPlainText().trim(),
  };
}

void main() {
  test('each new string has one app_en.arb entry and a Russian app_ru.arb '
      'translation', () {
    for (final english in _newStrings) {
      final ru = russianFor(english);
      expect(hasCyrillic(ru), isTrue, reason: '«$ru» for «$english»');
      expect(ru, isNot(english));
    }
  });

  testWidgets('origin line for a Request and for a Post fits a Russian '
      'phone', (tester) async {
    registerFactRepository(FakeOriginFactCardRepository());
    await pumpOpener(
      tester,
      locale: _ru,
      size: _phone,
      open: (ctx) => _openHostSheet(ctx, copiedFact()),
    );
    _expectOnPhone(tester, russianFor(kOriginFromRequest));

    await tester.pumpWidget(const SizedBox());
    await pumpOpener(
      tester,
      locale: _ru,
      size: _phone,
      open: (ctx) => _openHostSheet(ctx, copiedFact(originBeaconKind: 1)),
    );
    _expectOnPhone(tester, russianFor(kOriginFromPost));
  });

  testWidgets('«Use in another Request» fits a Russian phone', (tester) async {
    registerFactRepository(FakeOriginFactCardRepository());
    final cubit = await _loadedRoom();
    await pumpOpener(
      tester,
      locale: _ru,
      size: _phone,
      open: (ctx) => unawaited(
        showFactActionsSheet(
          ctx,
          cubit: cubit,
          fact: copiedFact(beaconId: kRoomCubitFakeBeaconId),
        ),
      ),
    );
    _expectOnPhone(tester, russianFor(kUseInAnotherRequest));
  });

  testWidgets('the unavailable snackbar fits a Russian phone', (tester) async {
    registerFactRepository(FakeOriginFactCardRepository());
    await pumpOriginRouter(
      tester,
      locale: _ru,
      size: _phone,
      openCopy: (ctx) => _openHostSheet(ctx, copiedFact()),
    );
    await tester.tap(find.text('open-copy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(russianFor(kOriginFromRequest)));
    await tester.pumpAndSettle();

    _expectOnPhone(tester, russianFor(kOriginUnavailable), richText: true);
  });

  testWidgets('the history footer and its Open button fit a Russian phone', (
    tester,
  ) async {
    final plain = await _ruHistoryTexts(
      tester,
      copiedFact(originBeaconKind: null, beaconId: kRoomCubitFakeBeaconId),
    );
    final copy = await _ruHistoryTexts(
      tester,
      copiedFact(beaconId: kRoomCubitFakeBeaconId),
    );

    _expectOnPhone(tester, russianFor(kEarlierHistoryFooter));
    // Its button reads a Russian «Open» from the ARB files, is on screen,
    // and is absent from the history of a fact that is not a copy.
    final openRu = russianValuesFor(kOpen);
    expect(openRu, isNotEmpty);
    final shown = openRu.where(copy.contains).toList();
    expect(shown, isNotEmpty, reason: 'a Russian «Open» among $copy');
    for (final text in shown) {
      expect(hasCyrillic(text), isTrue);
      expect(plain, isNot(contains(text)));
      _expectOnPhone(tester, text);
    }
  });
}
