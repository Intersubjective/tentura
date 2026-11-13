// Arriving at the source of a copied fact (plan D7/D8, §6.1), end to end:
// the reader taps the copy's origin line, BeaconFactCardOrigin answers over
// the real GraphQL stack (HTTP -> Ferry -> BeaconFactCardRepository mapping
// -> BeaconThreadsCase), the real router opens the source Request with
// focus_fact, and the real Request screen built from that URL shows the
// focused fact: a reader who is not a member of the source lands on its
// pinned facts sheet, not the chat, and the focused fact's actions open by
// themselves. An unavailable answer over the same stack ends in the
// snackbar with the location unchanged. The focused fact's actions say
// «Changed since it was copied» when it changed, and «See the copied
// version» (members of the source only) opens its history with the copied
// revision visibly highlighted.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_actions_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_history_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/widget/thread_detail.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../beacon_threads/fact_origin_test_support.dart';
import 'beacon_view_screen_harness.dart';

const _viewer = Profile(id: 'Uviewer000001', displayName: 'Viewer');
const _author = Profile(id: 'Uauthor000001', displayName: 'Author');

/// The source Request as a reader who is not a member sees it: content and
/// public facts readable, the chat not joined.
BeaconViewState _nonMemberSourceState() => BeaconViewState(
  beacon: Beacon(
    id: kSourceBeaconId,
    title: 'Source request',
    author: _author,
    createdAt: kBeaconViewHarnessNow,
    updatedAt: kBeaconViewHarnessNow,
  ),
  myProfile: _viewer,
  firstLoadDone: true,
  load: BeaconViewLoad.contentRead,
  roomParticipantsLoaded: true,
  roomParticipants: [
    BeaconParticipant(
      id: 'p-author',
      beaconId: kSourceBeaconId,
      userId: _author.id,
      role: 0,
      status: 0,
      roomAccess: RoomAccessBits.admitted,
      createdAt: kBeaconViewHarnessNow,
      updatedAt: kBeaconViewHarnessNow,
    ),
  ],
  // F is the copied fact's source; G is another fact of the same Request.
  factCards: [
    sourceFact().copyWith(pinnedByTitle: 'Fiona', lastEditedByTitle: ''),
    sourceFact().copyWith(
      id: 'Fsource-other',
      factText: 'Bring a torch',
      pinnedByTitle: 'Gus',
      lastEditedByTitle: '',
    ),
  ],
);

Map<String, Object?> _availableRow({
  required bool changedSinceCopy,
  required bool canSeeCopiedRevision,
  int? copiedRevisionSeq,
}) => {
  'available': true,
  'beaconId': kSourceBeaconId,
  'factCardId': kSourceFactId,
  'beaconKind': 0,
  'changedSinceCopy': changedSinceCopy,
  'canSeeCopiedRevision': canSeeCopiedRevision,
  'copiedRevisionSeq': copiedRevisionSeq,
};

/// Signs in, answers origin with [originRow] over the wire, opens the
/// copy's actions on the copy's page and taps its origin line.
Future<({OriginWire wire, Uri before, Uri after})> _tapOriginOnCopy(
  WidgetTester tester, {
  required Map<String, Object?> originRow,
  Locale locale = const Locale('en'),
  Size size = const Size(375, 812),
}) async {
  await registerBeaconViewHarnessGetIt(profile: _viewer);
  addTearDown(unregisterBeaconViewHarnessGetIt);
  final wire = (await tester.runAsync(
    () => OriginWire.start(
      origin: originRow,
      revisions: [
        for (final seq in [6, 5, 4, 3, 2, 1]) wireRevisionRow(seq),
      ],
    ),
  ))!;
  addTearDown(() => tester.runAsync(wire.close));
  registerFactRepository(wire.repository);

  final router = await pumpOriginRouter(
    tester,
    locale: locale,
    size: size,
    openCopy: (ctx) => unawaited(
      showFactActionsHostSheet(
        ctx,
        fact: copiedFact(),
        canMutate: false,
        onCorrect:
            ({required factCardId, required newText, attachmentsJson}) async {},
        onRemove: ({required factCardId}) async {},
        onSetVisibility: ({required factCardId, required visibility}) async {},
      ),
    ),
    sourceScope: (outlet) => beaconViewHarnessRouteScope(
      beaconState: _nonMemberSourceState(),
      threadsState: beaconViewHarnessThreadsState(authorId: _author.id),
      child: outlet,
    ),
  );
  final before = routerLocation(router);
  await tester.tap(find.text('open-copy'));
  await tester.pumpAndSettle();

  final originText = locale.languageCode == 'ru'
      ? russianFor(kOriginFromRequest)
      : kOriginFromRequest;
  await tapAndPumpRealAsync(tester, find.text(originText));
  expect(wire.sent, contains('BeaconFactCardOrigin'));
  return (wire: wire, before: before, after: routerLocation(router));
}

/// The open fact actions sheet (the scroll view holding its title).
Finder _actionsSheet(L10n l10n) => find
    .ancestor(
      of: find.text(l10n.beaconRoomFactManageSheetTitle),
      matching: find.byType(SingleChildScrollView),
    )
    .first;

/// The focused fact's actions opened by themselves on arrival: the sheet's
/// provenance names Fiona, who pinned F, and not Gus, who pinned the other.
Future<void> _expectFocusedSheetOpen(WidgetTester tester) async {
  final l10n = await L10n.delegate.load(const Locale('en'));
  expect(find.text(l10n.beaconRoomFactManageSheetTitle), findsOneWidget);
  final sheet = _actionsSheet(l10n);
  expect(
    find.descendant(of: sheet, matching: find.textContaining('Fiona')),
    findsOneWidget,
  );
  expect(
    find.descendant(of: sheet, matching: find.textContaining('Gus')),
    findsNothing,
  );
}

void main() {
  testWidgets('an unavailable origin over the real transport shows «The '
      "original isn't available to you» and the location does not change", (
    tester,
  ) async {
    final tap = await _tapOriginOnCopy(
      tester,
      originRow: const {
        'available': false,
        'beaconId': null,
        'factCardId': null,
        'beaconKind': null,
        'changedSinceCopy': null,
        'canSeeCopiedRevision': null,
        'copiedRevisionSeq': null,
      },
    );

    expect(find.text(kOriginUnavailable, findRichText: true), findsOneWidget);
    expect(tap.after, tap.before);
    expect(find.text(kCopyPageMarker), findsOneWidget);
  });

  testWidgets('a non-member taps an available origin: the source Request '
      "opens on its pinned facts sheet and the focused fact's actions open "
      'by themselves, not the chat', (tester) async {
    final tap = await _tapOriginOnCopy(
      tester,
      originRow: _availableRow(
        changedSinceCopy: false,
        canSeeCopiedRevision: false,
      ),
    );

    expect(tap.after.path, '/beacon/view/$kSourceBeaconId');
    expect(tap.after.queryParameters['focus_fact'], kSourceFactId);
    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.beaconFactsSheetTitle), findsOneWidget);
    expect(find.textContaining(kSourceFactText), findsWidgets);
    await _expectFocusedSheetOpen(tester);
    expect(find.byType(ThreadDetail), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a changed source says «Changed since it was copied» in the '
      "focused fact's actions; «See the copied version» opens its history "
      'with only the copied revision marked', (tester) async {
    final semantics = tester.ensureSemantics();
    await _tapOriginOnCopy(
      tester,
      originRow: _availableRow(
        changedSinceCopy: true,
        canSeeCopiedRevision: true,
        copiedRevisionSeq: 3,
      ),
    );
    await _expectFocusedSheetOpen(tester);

    expect(find.text(kChangedSinceCopied), findsOneWidget);
    expect(find.text(kSeeCopiedVersion), findsOneWidget);

    await tester.tap(find.text(kSeeCopiedVersion));
    await pumpRealAsync(tester);

    expect(find.byType(FactHistorySheet), findsOneWidget);
    await scrollToRevision(tester, 3);
    await pumpRealAsync(tester);
    expect(selectedRevisions(tester), {3});
    semantics.dispose();
  });

  testWidgets('an unchanged source shows no «Changed since it was copied»', (
    tester,
  ) async {
    await _tapOriginOnCopy(
      tester,
      originRow: _availableRow(
        changedSinceCopy: false,
        canSeeCopiedRevision: true,
        copiedRevisionSeq: 3,
      ),
    );
    await _expectFocusedSheetOpen(tester);

    expect(find.text(kChangedSinceCopied), findsNothing);
  });

  testWidgets('without canSeeCopiedRevision there is no «See the copied '
      'version», even when the source changed', (tester) async {
    await _tapOriginOnCopy(
      tester,
      originRow: _availableRow(
        changedSinceCopy: true,
        canSeeCopiedRevision: false,
        copiedRevisionSeq: 3,
      ),
    );
    await _expectFocusedSheetOpen(tester);

    expect(find.text(kChangedSinceCopied), findsOneWidget);
    expect(find.text(kSeeCopiedVersion), findsNothing);
  });

  testWidgets('in Russian at 375x667 the note and the copied-version button '
      'are translated and fit on screen', (tester) async {
    const phone = Size(375, 667);
    await _tapOriginOnCopy(
      tester,
      locale: const Locale('ru'),
      size: phone,
      originRow: _availableRow(
        changedSinceCopy: true,
        canSeeCopiedRevision: true,
        copiedRevisionSeq: 3,
      ),
    );

    for (final english in [kChangedSinceCopied, kSeeCopiedVersion]) {
      final ru = russianFor(english);
      expect(hasCyrillic(ru), isTrue);
      final text = find.text(ru);
      expect(text, findsOneWidget, reason: '«$ru» on screen');
      final rect = tester.getRect(text);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(phone.width));
      expect(rect.bottom, lessThanOrEqualTo(phone.height));
    }
    expect(tester.takeException(), isNull);
  });
}
