// The one fact picker (`FactPickerSheet`) switches between scopes and always
// shows its search field (plan docs/plans/fact-pick-from-available-1288.md
// P9–P11, §5):
//
// * Quote mode (`showFactPickerSheet`, the chat composer's «Fact»): scopes
//   «In this Request» / «In this Post», «Saved» and «All my facts». A fact
//   of this episode is quoted in place; one from elsewhere is copied here,
//   then the copy is quoted. A read-only room keeps only «In this …».
// * Bring mode (`showFactPickFromAvailableSheet`, the Facts lists' «Pick
//   from available»): scopes «Saved» and «All my facts», opens on Saved;
//   a tap copies the fact here, calls `onBrought` once, closes and says
//   «Fact added» (or «Already there»).
//
// «In this …» and «Saved» filter locally with the server's fold (lower case,
// ё as е, every word must occur); «All my facts» asks the server once the
// query has 2 or more letters. One row builder renders every scope:
// thumbnail or fact icon, ★ on saved facts, «No longer available» + remove
// for a fact that can no longer be copied.
//
// The sheets run over a real RoomCubit (quote) and the production
// BeaconThreadsCase registered in GetIt, wrapping a fake fact repository.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/exception/beacon_fact_card_exceptions.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_copy_destination_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_picker_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'fact_origin_test_support.dart';
import 'room_cubit_fakes.dart';

const _room = kRoomCubitFakeBeaconId;
const _otherBeacon = 'Bother0000001';
const _bringBeacon = 'B1';

// Existing strings, read from the generated L10n so a wording change to an
// existing key does not fail these tests.
final _enL10n = lookupL10n(const Locale('en'));
final _ruL10n = lookupL10n(const Locale('ru'));
final _tabRequest = _enL10n.beaconRoomFactPickerTabRequest;
final _tabPost = _enL10n.beaconRoomFactPickerTitlePost;
final _tabSaved = _enL10n.beaconRoomFactPickerTabSaved;
final _noLongerAvailable = _enL10n.beaconRoomFactPickerSavedUnavailable;
final _alreadyThere = _enL10n.beaconFactCopyAlreadyThere;

// New picker strings (plan §5).
const _tabAll = 'All my facts';
const _titlePick = 'Pick a fact';
const _searchHint = 'Search facts';
const _typeMore = 'Type 2 or more letters';
const _nothingFound = 'Nothing found';
const _factAdded = 'Fact added';

const _roomFactId = 'Froom00000001';
const _roomFactText = 'Meet at the north gate';

const _imageAttachmentJson =
    '[{"id":"A1","kind":1,"position":0,"mime":"image/jpeg",'
    '"sizeBytes":1000,"imageId":"img-1","imageAuthorId":"Ubob",'
    '"width":10,"height":10}]';

final _imageAttachment = parseRoomMessageAttachmentsJson(_imageAttachmentJson);

BeaconFactCard _card(
  String id,
  String text, {
  String beaconId = _room,
  List<RoomMessageAttachment> attachments = const [],
}) => BeaconFactCard(
  id: id,
  beaconId: beaconId,
  factText: text,
  visibility: BeaconFactCardVisibilityBits.public,
  pinnedBy: 'Ubob',
  pinnedByTitle: 'Bob',
  createdAt: DateTime.utc(2026, 11),
  status: BeaconFactCardStatusBits.active,
  revisionSeq: 2,
  attachments: attachments,
);

BeaconSavedFact _saved(
  String id,
  String text, {
  String beaconId = _otherBeacon,
  String attachmentsJson = '[]',
}) => (
  factCardId: id,
  available: true,
  beaconId: beaconId,
  beaconKind: 0,
  factText: text,
  attachmentsJson: attachmentsJson,
);

BeaconSavedFact _gone(String id) => (
  factCardId: id,
  available: false,
  beaconId: null,
  beaconKind: null,
  factText: null,
  attachmentsJson: null,
);

BeaconFactSearchHit _hit(
  String id,
  String text, {
  String beaconId = _otherBeacon,
  bool saved = false,
  String attachmentsJson = '[]',
}) => (
  factCardId: id,
  beaconId: beaconId,
  beaconKind: 0,
  factText: text,
  attachmentsJson: attachmentsJson,
  saved: saved,
);

/// Server-side fake: room facts, saved list, search and copy. A successful
/// copy adds the copy to the destination's fact list.
class _Repo extends FakeBeaconFactCardRepository {
  _Repo({
    List<BeaconFactCard>? roomFacts,
    List<BeaconSavedFact>? saved,
    List<BeaconFactSearchHit>? hits,
  }) : roomFacts = roomFacts ?? [_card(_roomFactId, _roomFactText)],
       saved = saved ?? [],
       hits = hits ?? [];

  final List<BeaconFactCard> roomFacts;
  final List<BeaconSavedFact> saved;

  /// Returned by every search (the fake does not filter).
  List<BeaconFactSearchHit> hits;
  BeaconFactCopyOutcome copyOutcome = BeaconFactCopyOutcome.created;
  Object? copyError;

  /// `copy:<src>-><dest>`, `list:<beacon>`, `search:<q>`, `unsave:<id>`.
  final log = <String>[];
  final searchCalls = <({String query, String? excludeBeaconId})>[];
  final copyCalls = <({String source, String destination})>[];
  final unsaveCalls = <String>[];

  static String copyIdOf(String source) => '$source-copy';

  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) async {
    log.add('list:$beaconId');
    return roomFacts.where((f) => f.beaconId == beaconId).toList();
  }

  @override
  Future<List<BeaconSavedFact>> savedList() async {
    log.add('saved');
    return List.of(saved);
  }

  @override
  Future<List<BeaconFactSearchHit>> search({
    required String query,
    String? excludeBeaconId,
  }) async {
    log.add('search:$query');
    searchCalls.add((query: query, excludeBeaconId: excludeBeaconId));
    return List.of(hits);
  }

  @override
  Future<void> unsave({required String factCardId}) async {
    log.add('unsave:$factCardId');
    unsaveCalls.add(factCardId);
    saved.removeWhere((s) => s.factCardId == factCardId);
  }

  @override
  Future<BeaconFactCopyResult> copy({
    required String sourceFactCardId,
    required String destinationBeaconId,
  }) async {
    log.add('copy:$sourceFactCardId->$destinationBeaconId');
    copyCalls.add((
      source: sourceFactCardId,
      destination: destinationBeaconId,
    ));
    final error = copyError;
    if (error != null) Error.throwWithStackTrace(error, StackTrace.current);
    final text = [
      for (final s in saved)
        if (s.factCardId == sourceFactCardId) s.factText,
      for (final h in hits)
        if (h.factCardId == sourceFactCardId) h.factText,
    ].firstOrNull;
    final id = copyIdOf(sourceFactCardId);
    if (!roomFacts.any((f) => f.id == id)) {
      roomFacts.add(_card(id, text ?? 'copied', beaconId: destinationBeaconId));
    }
    return (factCardId: id, outcome: copyOutcome);
  }
}

void _registerLogger() {
  final getIt = GetIt.instance;
  if (getIt.isRegistered<Logger>()) return;
  getIt.registerSingleton<Logger>(Logger('test'));
  addTearDown(() {
    // ignore: discarded_futures -- best-effort unregister.
    getIt.unregister<Logger>();
  });
}

Future<RoomCubit> _roomCubit({required bool writable}) async {
  registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
  final fakeRoom = FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId);
  addTearDown(fakeRoom.dispose);
  final cubit = roomCubitForTest(
    fakeRoom,
    beaconRoomCase: GetIt.instance<BeaconThreadsCase>(),
  );
  addTearDown(cubit.close);
  await awaitRoomCubitLoad(cubit);
  cubit.syncBeaconStatus(writable ? BeaconStatus.open : BeaconStatus.closed);
  return cubit;
}

/// Opens the composer's quote picker over a loaded room.
Future<RoomCubit> _openQuote(
  WidgetTester tester,
  _Repo repo, {
  bool writable = true,
  bool isPost = false,
  Locale locale = const Locale('en'),
  Size size = const Size(375, 812),
}) async {
  _registerLogger();
  registerFactRepository(repo);
  final cubit = await _roomCubit(writable: writable);
  await pumpOpener(
    tester,
    locale: locale,
    size: size,
    open: (ctx) =>
        unawaited(showFactPickerSheet(ctx, cubit: cubit, isPost: isPost)),
  );
  expect(find.byType(FactPickerSheet), findsOneWidget);
  return cubit;
}

class _Brought {
  int calls = 0;
}

/// Opens the bring-here picker for [beaconId].
Future<_Brought> _openBring(
  WidgetTester tester,
  _Repo repo, {
  String beaconId = _bringBeacon,
  bool isPost = false,
  Locale locale = const Locale('en'),
  Size size = const Size(375, 812),
}) async {
  _registerLogger();
  registerFactRepository(repo);
  final brought = _Brought();
  await pumpOpener(
    tester,
    locale: locale,
    size: size,
    open: (ctx) => unawaited(
      showFactPickFromAvailableSheet(
        ctx,
        beaconId: beaconId,
        isPost: isPost,
        onBrought: () async => brought.calls++,
      ),
    ),
  );
  expect(find.byType(FactPickerSheet), findsOneWidget);
  return brought;
}

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(FactPickerSheet), matching: f);

TenturaUnderlineTabs? _tabs(WidgetTester tester) {
  final f = _inSheet(find.byType(TenturaUnderlineTabs));
  return f.evaluate().isEmpty ? null : tester.widget<TenturaUnderlineTabs>(f);
}

Future<void> _openTab(WidgetTester tester, String label) async {
  final tab = find.descendant(
    of: _inSheet(find.byType(TenturaUnderlineTabs)),
    matching: find.textContaining(label),
  );
  expect(tab, findsOneWidget, reason: 'the picker has a «$label» scope');
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

Finder _searchField([String hint = _searchHint]) => _inSheet(
  find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint,
  ),
);

/// Types [text] into the search field and lets the server debounce run.
Future<void> _search(WidgetTester tester, String text) async {
  expect(_searchField(), findsOneWidget, reason: 'the search field shows');
  await tester.enterText(_searchField(), text);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

/// The picker row showing [text]: its nearest tappable ancestor (whatever
/// tile widget the row is built from).
Finder _row(String text) => find
    .ancestor(
      of: _inSheet(find.text(text)),
      matching: find.byWidgetPredicate(
        (w) => w is InkWell || w is ListTile || w is GestureDetector,
      ),
    )
    .first;

/// A non-star icon placed before (left of) the row's [text]: the leading
/// fact icon, not the trailing ★ or a menu.
Finder _leadingIconIn(WidgetTester tester, String text) {
  final textLeft = tester.getTopLeft(_inSheet(find.text(text))).dx;
  final icons = find
      .descendant(
        of: _row(text),
        matching: find.byWidgetPredicate(
          (w) => w is Icon && !_starIcons.contains(w.icon),
        ),
      )
      .evaluate()
      .toSet();
  return find.byElementPredicate((e) {
    if (!icons.contains(e)) return false;
    final box = e.renderObject;
    if (box is! RenderBox || !box.hasSize) return false;
    return box.localToGlobal(Offset(box.size.width, 0)).dx <= textLeft + 0.5;
  });
}

/// No layout overflow: no FlutterError (a RenderFlex overflow is reported as
/// one) and every text in the sheet lies within the screen width. Whether a
/// label is ellipsised is not checked: widget tests use the square-glyph
/// test font, so label widths here are not the real ones.
void _expectNoOverflow(WidgetTester tester, {required double width}) {
  expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
  for (final e in _inSheet(find.byType(RichText)).evaluate()) {
    final ro = e.renderObject;
    if (ro is! RenderParagraph || !ro.hasSize) continue;
    final label = ro.text.toPlainText();
    final left = ro.localToGlobal(Offset.zero).dx;
    final right = ro.localToGlobal(Offset(ro.size.width, 0)).dx;
    expect(
      left,
      greaterThanOrEqualTo(-0.5),
      reason: '«$label» starts off screen',
    );
    expect(
      right,
      lessThanOrEqualTo(width + 0.5),
      reason: '«$label» ends off screen',
    );
  }
}

Finder _inRow(String text, Finder what) =>
    find.descendant(of: _row(text), matching: what);

final _starIcons = {
  Icons.star,
  Icons.star_rounded,
  Icons.star_sharp,
  Icons.grade,
  Icons.grade_rounded,
};

final _star = find.byWidgetPredicate(
  (w) => switch (w) {
    Icon(:final icon) => _starIcons.contains(icon),
    Text(:final data) => (data ?? '').contains('★'),
    _ => false,
  },
);

/// The row's own button. An unavailable row offers only removal, so any
/// button in it (whatever its wording or icon) is the remove action. An M3
/// IconButton builds an inner ButtonStyleButton, so the public button types
/// are matched rather than ButtonStyleButton (which would count it twice).
Finder _removeControlIn(String text) => _inRow(
  text,
  find.byWidgetPredicate(
    (w) =>
        w is IconButton ||
        w is TextButton ||
        w is FilledButton ||
        w is OutlinedButton ||
        w is ElevatedButton,
  ),
);

Finder _inSnackBar(String text) => find.descendant(
  of: find.byType(SnackBar),
  matching: find.text(text, findRichText: true),
);

L10n _l10n(WidgetTester tester) =>
    L10n.of(tester.element(find.byType(FactPickerSheet)))!;

/// Every string the sheet renders.
List<String> _sheetStrings(WidgetTester tester) => [
  for (final e in _inSheet(find.byType(RichText)).evaluate())
    (e.widget as RichText).text.toPlainText(),
];

List<BeaconFactCard> _roomFacts(int n) => [
  for (var i = 0; i < n; i++) _card('Froom${'$i'.padLeft(8, '0')}', 'Room $i'),
];

List<BeaconSavedFact> _savedN(int n) => [
  for (var i = 0; i < n; i++) _saved('Fsave${'$i'.padLeft(8, '0')}', 'Kept $i'),
];

List<BeaconFactSearchHit> _hitsN(int n) => [
  for (var i = 0; i < n; i++) _hit('Fhit0${'$i'.padLeft(8, '0')}', 'Found $i'),
];

void main() {
  group('quote mode scopes', () {
    testWidgets('a writable Request room with one fact opens on «In this '
        'Request» beside «Saved» and «All my facts», with a search field; a '
        'tap quotes the fact without a copy and closes', (tester) async {
      final repo = _Repo();
      final cubit = await _openQuote(tester, repo);

      final tabs = _tabs(tester);
      expect(tabs, isNotNull, reason: 'the scopes are underline tabs');
      expect(tabs!.tabs, hasLength(3));
      expect(tabs.tabs[0], _tabRequest);
      expect(tabs.tabs[1], contains(_tabSaved));
      expect(tabs.tabs[2], _tabAll);
      expect(tabs.selectedIndex, 0, reason: 'opens on «In this Request»');
      expect(_searchField(), findsOneWidget);

      await tester.tap(_inSheet(find.text(_roomFactText)));
      await tester.pumpAndSettle();

      expect(cubit.state.pendingQuotedFact?.factCardId, _roomFactId);
      expect(repo.copyCalls, isEmpty);
      expect(find.byType(FactPickerSheet), findsNothing);
    });

    testWidgets('a Post room’s first scope reads «In this Post»; the other '
        'two are unchanged', (tester) async {
      await _openQuote(tester, _Repo(), isPost: true);

      final tabs = _tabs(tester);
      expect(tabs, isNotNull);
      expect(tabs!.tabs, hasLength(3));
      expect(tabs.tabs[0], _tabPost);
      expect(tabs.tabs[1], contains(_tabSaved));
      expect(tabs.tabs[2], _tabAll);
    });

    testWidgets('a read-only room shows only «In this …»: no Saved or All '
        'scope, its facts listed and the search field still shown', (
      tester,
    ) async {
      await _openQuote(tester, _Repo(), writable: false);

      // The one scope is named «In this Request» once, as a heading or a
      // single tab above the search field (not as a fact row).
      final tabs = _tabs(tester);
      if (tabs != null) expect(tabs.tabs, [_tabRequest]);
      expect(_inSheet(find.text(_tabRequest)), findsOneWidget);
      expect(_searchField(), findsOneWidget);
      expect(
        tester.getBottomLeft(_inSheet(find.text(_tabRequest))).dy,
        lessThanOrEqualTo(tester.getTopLeft(_searchField()).dy),
        reason: '«In this Request» names the scope above the search field',
      );
      expect(_inSheet(find.textContaining(_tabSaved)), findsNothing);
      expect(_inSheet(find.text(_tabAll)), findsNothing);
      expect(_inSheet(find.text(_roomFactText)), findsOneWidget);
      expect(_searchField(), findsOneWidget);
    });

    for (final n in [0, 1, 6]) {
      testWidgets('the search field is shown on every scope with $n rows', (
        tester,
      ) async {
        final repo = _Repo(
          roomFacts: _roomFacts(n),
          saved: _savedN(n),
          hits: _hitsN(n),
        );
        await _openQuote(tester, repo);
        expect(_searchField(), findsOneWidget, reason: 'In this Request');

        await _openTab(tester, _tabSaved);
        expect(_searchField(), findsOneWidget, reason: 'Saved');

        await _openTab(tester, _tabAll);
        expect(_searchField(), findsOneWidget, reason: 'All my facts');
        await _search(tester, 'found');
        expect(_searchField(), findsOneWidget, reason: 'All with results');
      });

      testWidgets('the bring picker shows the search field on Saved and All '
          'with $n rows', (tester) async {
        final repo = _Repo(saved: _savedN(n), hits: _hitsN(n));
        await _openBring(tester, repo);
        expect(_searchField(), findsOneWidget, reason: 'Saved');

        await _openTab(tester, _tabAll);
        expect(_searchField(), findsOneWidget, reason: 'All my facts');
        await _search(tester, 'found');
        expect(_searchField(), findsOneWidget, reason: 'All with results');
      });
    }
  });

  group('quote mode picks from Saved', () {
    testWidgets('a ★ Saved fact from another Request is copied here, then '
        'the copy is quoted and the sheet closes', (tester) async {
      const id = 'Fsavother0001';
      const text = 'Shed code 4471';
      final repo = _Repo(saved: [_saved(id, text)]);
      final cubit = await _openQuote(tester, repo);
      await _openTab(tester, _tabSaved);
      expect(_inRow(text, _star), findsWidgets, reason: 'a saved row has ★');
      await tester.tap(_inSheet(find.text(text)));
      await tester.pumpAndSettle();

      expect(repo.copyCalls, [(source: id, destination: _room)]);
      expect(cubit.state.pendingQuotedFact?.factCardId, _Repo.copyIdOf(id));
      expect(find.byType(FactPickerSheet), findsNothing);
    });
  });

  group('local scopes filter with the server fold', () {
    const yolka = 'Ёлка у дома';
    const keys = 'Keys';

    Future<void> expectFold(WidgetTester tester, _Repo repo) async {
      await _search(tester, 'елка');
      expect(_inSheet(find.text(yolka)), findsOneWidget, reason: 'ё = е');
      expect(_inSheet(find.text(keys)), findsNothing);

      await _search(tester, 'елка дом');
      expect(_inSheet(find.text(yolka)), findsOneWidget, reason: 'two words');
      expect(_inSheet(find.text(keys)), findsNothing);

      await _search(tester, 'елка keys');
      expect(_inSheet(find.text(yolka)), findsNothing, reason: 'every word');
      expect(_inSheet(find.text(keys)), findsNothing);

      expect(repo.searchCalls, isEmpty, reason: 'local scopes ask no server');
    }

    testWidgets('«In this Request» matches ё as е and needs every word', (
      tester,
    ) async {
      final repo = _Repo(
        roomFacts: [
          _card('Fyolka0000001', yolka),
          _card('Fkeys00000001', keys),
        ],
      );
      await _openQuote(tester, repo);
      await expectFold(tester, repo);
    });

    testWidgets('the bring picker’s «Saved» matches ё as е and needs every '
        'word', (tester) async {
      final repo = _Repo(
        saved: [_saved('Fyolka0000001', yolka), _saved('Fkeys00000001', keys)],
      );
      await _openBring(tester, repo);
      expect(_inSheet(find.text(yolka)), findsOneWidget);
      await expectFold(tester, repo);
    });

    testWidgets('«Saved» matches ё as е and needs every word', (tester) async {
      final repo = _Repo(
        saved: [_saved('Fyolka0000001', yolka), _saved('Fkeys00000001', keys)],
      );
      await _openQuote(tester, repo);
      await _openTab(tester, _tabSaved);
      await expectFold(tester, repo);
    });
  });

  group('«All my facts» searches the server', () {
    testWidgets('a 1-letter query shows «Type 2 or more letters» and asks no '
        'server', (tester) async {
      final repo = _Repo(hits: _hitsN(2));
      await _openQuote(tester, repo);
      await _openTab(tester, _tabAll);
      await _search(tester, 'f');

      expect(_inSheet(find.text(_typeMore)), findsOneWidget);
      expect(repo.searchCalls, isEmpty);
    });

    testWidgets('a longer query with no server hits shows «Nothing found»; '
        'the search excludes this room’s own facts', (tester) async {
      final repo = _Repo();
      await _openQuote(tester, repo);
      await _openTab(tester, _tabAll);
      await _search(tester, 'zz');

      expect(_inSheet(find.text(_nothingFound)), findsOneWidget);
      expect(repo.searchCalls, isNotEmpty);
      expect(repo.searchCalls.last.query, 'zz');
      expect(repo.searchCalls.last.excludeBeaconId, _room);
    });

    testWidgets('the bring picker: a 1-letter query shows «Type 2 or more '
        'letters» without a search; a longer one with no hits shows «Nothing '
        'found»', (tester) async {
      final repo = _Repo();
      await _openBring(tester, repo);
      await _openTab(tester, _tabAll);

      await _search(tester, 'f');
      expect(_inSheet(find.text(_typeMore)), findsOneWidget);
      expect(repo.searchCalls, isEmpty);

      await _search(tester, 'zz');
      expect(_inSheet(find.text(_nothingFound)), findsOneWidget);
      expect(repo.searchCalls.last.query, 'zz');
      expect(repo.searchCalls.last.excludeBeaconId, _bringBeacon);
    });

    testWidgets('typing lists the server hits; tapping a hit from another '
        'Request copies it here, then quotes the copy and closes', (
      tester,
    ) async {
      const hitId = 'Fhitother0001';
      const hitText = 'Shed code 4471';
      final repo = _Repo(hits: [_hit(hitId, hitText)]);
      final cubit = await _openQuote(tester, repo);
      await _openTab(tester, _tabAll);
      expect(_inSheet(find.text(hitText)), findsNothing);
      await _search(tester, 'shed');

      expect(repo.searchCalls, isNotEmpty, reason: 'the server is asked');
      expect(repo.searchCalls.last.query, 'shed');
      expect(_inSheet(find.text(hitText)), findsOneWidget);
      await tester.tap(_inSheet(find.text(hitText)));
      await tester.pumpAndSettle();

      expect(repo.copyCalls, [(source: hitId, destination: _room)]);
      expect(
        cubit.state.pendingQuotedFact?.factCardId,
        _Repo.copyIdOf(hitId),
        reason: 'the copy is quoted, not the source',
      );
      expect(find.byType(FactPickerSheet), findsNothing);
    });
  });

  group('one row builder for every scope', () {
    testWidgets('★ marks saved facts on «All my facts» and «Saved»; an '
        'unsaved hit has none; a saved fact of this Request is quoted in '
        'place without a copy', (tester) async {
      const savedHit = 'Kept gate code';
      const plainHit = 'Plain gate note';
      final repo = _Repo(
        saved: [_saved(_roomFactId, _roomFactText, beaconId: _room)],
        hits: [
          _hit('Fhitsaved0001', savedHit, saved: true),
          _hit('Fhitplain0001', plainHit),
        ],
      );
      final cubit = await _openQuote(tester, repo);
      expect(
        _inRow(_roomFactText, _star),
        findsWidgets,
        reason: '«In this Request»: a saved fact of this Request has ★',
      );

      await _openTab(tester, _tabAll);
      await _search(tester, 'gate');
      expect(_inRow(savedHit, _star), findsWidgets);
      expect(_inRow(plainHit, _star), findsNothing);

      await _openTab(tester, _tabSaved);
      expect(_inRow(_roomFactText, _star), findsWidgets);

      await tester.tap(_inSheet(find.text(_roomFactText)));
      await tester.pumpAndSettle();
      expect(cubit.state.pendingQuotedFact?.factCardId, _roomFactId);
      expect(repo.copyCalls, isEmpty);
      expect(find.byType(FactPickerSheet), findsNothing);
    });

    testWidgets('a fact with an image shows a thumbnail and a text-only fact '
        'the fact icon, on «In this Request», «Saved» and «All my facts»', (
      tester,
    ) async {
      const imgHere = 'Photo of the gate';
      const txtHere = 'Gate is green';
      const imgSaved = 'Photo of the shed';
      const txtSaved = 'Shed is red';
      const imgHit = 'Photo of the barn';
      const txtHit = 'Barn is blue';
      final repo = _Repo(
        roomFacts: [
          _card('Fimghere00001', imgHere, attachments: _imageAttachment),
          _card('Ftxthere00001', txtHere),
        ],
        saved: [
          _saved(
            'Fimgsave00001',
            imgSaved,
            attachmentsJson: _imageAttachmentJson,
          ),
          _saved('Ftxtsave00001', txtSaved),
        ],
        hits: [
          _hit('Fimghit000001', imgHit, attachmentsJson: _imageAttachmentJson),
          _hit('Ftxthit000001', txtHit),
        ],
      );
      await _openQuote(tester, repo);

      void expectLeading(String img, String txt, String scope) {
        expect(
          _inRow(img, find.byType(Image)),
          findsOneWidget,
          reason: '$scope: an image fact shows its thumbnail',
        );
        expect(
          _inRow(txt, find.byType(Image)),
          findsNothing,
          reason: '$scope: a text-only fact has no thumbnail',
        );
        expect(
          _leadingIconIn(tester, txt),
          findsOneWidget,
          reason: '$scope: a text-only fact shows the fact icon before it',
        );
      }

      expectLeading(imgHere, txtHere, 'In this Request');
      await _openTab(tester, _tabSaved);
      expectLeading(imgSaved, txtSaved, 'Saved');
      await _openTab(tester, _tabAll);
      await _search(tester, 'is');
      expectLeading(imgHit, txtHit, 'All my facts');
    });
  });

  group('failed picks', () {
    testWidgets('quote mode: a Saved fact from another Request that is no '
        'longer available keeps the sheet open, shows the copy failure and '
        're-renders the row as «No longer available» with a remove button', (
      tester,
    ) async {
      const id = 'Fsavgone00002';
      const text = 'Old ladder spot';
      final repo = _Repo(saved: [_saved(id, text)])
        ..copyError = const BeaconFactCopySourceUnavailableException();
      final cubit = await _openQuote(tester, repo);
      await _openTab(tester, _tabSaved);
      expect(_inRow(text, _star), findsWidgets, reason: 'a saved row has ★');
      await tester.tap(_inSheet(find.text(text)));
      await tester.pumpAndSettle();

      expect(repo.copyCalls, [(source: id, destination: _room)]);
      expect(find.byType(FactPickerSheet), findsOneWidget);
      expect(cubit.state.pendingQuotedFact, isNull);
      expect(
        _inSnackBar(
          factCopyFailureText(
            _l10n(tester),
            const BeaconFactCopySourceUnavailableException(),
          ),
        ),
        findsOneWidget,
      );
      expect(_inSheet(find.text(_noLongerAvailable)), findsOneWidget);
      expect(_removeControlIn(_noLongerAvailable), findsOneWidget);
    });

    testWidgets('quote mode: an unavailable saved row does nothing on tap; '
        'its remove button unsaves it once and the row disappears, while '
        'the search field stays', (tester) async {
      const goneId = 'Fgone00000002';
      final repo = _Repo(
        saved: [_gone(goneId), _saved('Fkept0000002', 'Kept')],
      );
      final cubit = await _openQuote(tester, repo);
      await _openTab(tester, _tabSaved);
      expect(_searchField(), findsOneWidget);

      expect(_inSheet(find.text(_noLongerAvailable)), findsOneWidget);
      await tester.tap(_inSheet(find.text(_noLongerAvailable)));
      await tester.pumpAndSettle();
      expect(repo.copyCalls, isEmpty);
      expect(cubit.state.pendingQuotedFact, isNull);
      expect(find.byType(FactPickerSheet), findsOneWidget);

      await tester.tap(_removeControlIn(_noLongerAvailable));
      await tester.pumpAndSettle();
      expect(repo.unsaveCalls, [goneId]);
      expect(_inSheet(find.text(_noLongerAvailable)), findsNothing);
      expect(_inSheet(find.text('Kept')), findsOneWidget);
    });

    testWidgets('quote mode: a hit that is no longer available keeps the '
        'sheet open, shows the copy failure and re-renders the row as «No '
        'longer available» with a remove button', (tester) async {
      const hitId = 'Fhitgone00001';
      const hitText = 'Old ladder spot';
      final repo = _Repo(
        saved: [_saved(hitId, hitText)],
        hits: [_hit(hitId, hitText, saved: true)],
      )..copyError = const BeaconFactCopySourceUnavailableException();
      final cubit = await _openQuote(tester, repo);
      await _openTab(tester, _tabAll);
      await _search(tester, 'ladder');
      await tester.tap(_inSheet(find.text(hitText)));
      await tester.pumpAndSettle();

      expect(find.byType(FactPickerSheet), findsOneWidget);
      expect(cubit.state.pendingQuotedFact, isNull);
      expect(
        _inSnackBar(
          factCopyFailureText(
            _l10n(tester),
            const BeaconFactCopySourceUnavailableException(),
          ),
        ),
        findsOneWidget,
      );
      expect(_inSheet(find.text(_noLongerAvailable)), findsOneWidget);
      expect(_removeControlIn(_noLongerAvailable), findsOneWidget);
    });

    testWidgets('bring mode: an unavailable source keeps the sheet open, '
        'shows the copy failure, marks the row and does not call onBrought', (
      tester,
    ) async {
      const id = 'Fsavgone00001';
      const text = 'Old ladder spot';
      final repo = _Repo(saved: [_saved(id, text)])
        ..copyError = const BeaconFactCopySourceUnavailableException();
      final brought = await _openBring(tester, repo);
      await tester.tap(_inSheet(find.text(text)));
      await tester.pumpAndSettle();

      expect(repo.copyCalls, [(source: id, destination: _bringBeacon)]);
      expect(find.byType(FactPickerSheet), findsOneWidget);
      expect(brought.calls, 0);
      expect(
        _inSnackBar(
          factCopyFailureText(
            _l10n(tester),
            const BeaconFactCopySourceUnavailableException(),
          ),
        ),
        findsOneWidget,
      );
      expect(_inSheet(find.text(_noLongerAvailable)), findsOneWidget);
      expect(_removeControlIn(_noLongerAvailable), findsOneWidget);
    });

    testWidgets('bring mode: a rate-limited copy keeps the sheet open, shows '
        'the copy failure text and does not call onBrought', (tester) async {
      const id = 'Fsavrate00001';
      const text = 'Bike lock 2210';
      const error = BeaconFactRateLimitedException();
      final repo = _Repo(saved: [_saved(id, text)])..copyError = error;
      final brought = await _openBring(tester, repo);
      await tester.tap(_inSheet(find.text(text)));
      await tester.pumpAndSettle();

      expect(find.byType(FactPickerSheet), findsOneWidget);
      expect(brought.calls, 0);
      expect(
        _inSnackBar(factCopyFailureText(_l10n(tester), error)),
        findsOneWidget,
      );
    });

    testWidgets('an unavailable saved row does nothing on tap; its remove '
        'button unsaves it once and the row disappears', (tester) async {
      const goneId = 'Fgone00000001';
      final repo = _Repo(
        saved: [_gone(goneId), _saved('Fkept0000001', 'Kept')],
      );
      final brought = await _openBring(tester, repo);

      expect(_inSheet(find.text(_noLongerAvailable)), findsOneWidget);
      await tester.tap(_inSheet(find.text(_noLongerAvailable)));
      await tester.pumpAndSettle();
      expect(repo.copyCalls, isEmpty);
      expect(brought.calls, 0);
      expect(find.byType(FactPickerSheet), findsOneWidget);

      await tester.tap(_removeControlIn(_noLongerAvailable));
      await tester.pumpAndSettle();
      expect(repo.unsaveCalls, [goneId]);
      expect(_inSheet(find.text(_noLongerAvailable)), findsNothing);
      expect(_inSheet(find.text('Kept')), findsOneWidget);
    });
  });

  group('bring mode', () {
    testWidgets('shows only «Saved» and «All my facts», opens on Saved and is '
        'titled «Pick a fact»', (tester) async {
      await _openBring(tester, _Repo(saved: _savedN(1)));

      final tabs = _tabs(tester);
      expect(tabs, isNotNull);
      expect(tabs!.tabs, hasLength(2));
      expect(tabs.tabs[0], contains(_tabSaved));
      expect(tabs.tabs[1], _tabAll);
      expect(tabs.selectedIndex, 0, reason: 'opens on Saved');
      expect(_inSheet(find.text(_titlePick)), findsOneWidget);
      expect(_inSheet(find.text(_tabRequest)), findsNothing);
      expect(_inSheet(find.text(_tabPost)), findsNothing);
      expect(_inSheet(find.text('Kept 0')), findsOneWidget);
    });

    testWidgets('hides saved facts of the destination and searches «All my '
        'facts» without them', (tester) async {
      final repo = _Repo(
        saved: [
          _saved('Fhere00000001', 'Already in B1', beaconId: _bringBeacon),
          _saved('Fother0000001', 'From elsewhere'),
        ],
      );
      await _openBring(tester, repo);
      expect(_inSheet(find.text('From elsewhere')), findsOneWidget);
      expect(_inSheet(find.text('Already in B1')), findsNothing);

      await _openTab(tester, _tabAll);
      await _search(tester, 'from');
      expect(repo.searchCalls, isNotEmpty);
      expect(repo.searchCalls.last.excludeBeaconId, _bringBeacon);
    });

    testWidgets('a tap copies the fact here, calls onBrought once, closes and '
        'says «Fact added»', (tester) async {
      const id = 'Fother0000001';
      final repo = _Repo(saved: [_saved(id, 'Shed code 4471')]);
      final brought = await _openBring(tester, repo);

      await tester.tap(_inSheet(find.text('Shed code 4471')));
      await tester.pumpAndSettle();

      expect(repo.copyCalls, [(source: id, destination: _bringBeacon)]);
      expect(brought.calls, 1);
      expect(find.byType(FactPickerSheet), findsNothing);
      expect(_inSnackBar(_factAdded), findsOneWidget);
    });

    testWidgets('a hit from «All my facts» that is already there says '
        '«Already there»', (tester) async {
      const id = 'Fhitother0001';
      final repo = _Repo(hits: [_hit(id, 'Shed code 4471')])
        ..copyOutcome = BeaconFactCopyOutcome.alreadyThere;
      final brought = await _openBring(tester, repo);
      await _openTab(tester, _tabAll);
      await _search(tester, 'shed');
      await tester.tap(_inSheet(find.text('Shed code 4471')));
      await tester.pumpAndSettle();

      expect(repo.copyCalls, [(source: id, destination: _bringBeacon)]);
      expect(brought.calls, 1);
      expect(find.byType(FactPickerSheet), findsNothing);
      expect(_inSnackBar(_alreadyThere), findsOneWidget);
    });
  });

  group('strings and phone layout', () {
    const newStrings = {
      _tabAll: 'Все мои факты',
      _titlePick: 'Выберите факт',
      _searchHint: 'Поиск фактов',
      _typeMore: 'Введите хотя бы 2 буквы',
      _nothingFound: 'Ничего не найдено',
      _factAdded: 'Факт добавлен',
    };

    test('every new picker string exists in English and Russian', () {
      Map<String, dynamic> arb(String path) =>
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      final en = arb('l10n/app_en.arb');
      final ru = arb('l10n/app_ru.arb');
      for (final MapEntry(key: enText, value: ruText) in newStrings.entries) {
        final keys = [
          for (final e in en.entries)
            if (!e.key.startsWith('@') && e.value == enText) e.key,
        ];
        expect(keys, hasLength(1), reason: 'app_en.arb has «$enText»');
        final key = keys.single;
        expect(en[key], enText, reason: 'app_en.arb $key');
        expect(ru[key], ruText, reason: 'app_ru.arb $key');
      }
    });

    for (final (locale, labels) in [
      (
        const Locale('en'),
        (here: _tabRequest, saved: _tabSaved, all: _tabAll, hint: _searchHint),
      ),
      (
        const Locale('ru'),
        (
          here: _ruL10n.beaconRoomFactPickerTabRequest,
          saved: _ruL10n.beaconRoomFactPickerTabSaved,
          all: 'Все мои факты',
          hint: 'Поиск фактов',
        ),
      ),
    ]) {
      testWidgets('at 375x667 in ${locale.languageCode} the quote picker '
          'shows all three scopes without overflow and no internal words', (
        tester,
      ) async {
        await _openQuote(
          tester,
          _Repo(saved: _savedN(1)),
          locale: locale,
          size: const Size(375, 667),
        );
        _expectNoOverflow(tester, width: 375);
        final tabs = _tabs(tester);
        expect(tabs, isNotNull);
        expect(tabs!.tabs, [
          labels.here,
          predicate<String>((t) => t.contains(labels.saved)),
          labels.all,
        ]);
        expect(_searchField(labels.hint), findsOneWidget);

        await _openTab(tester, labels.all);
        await tester.enterText(_searchField(labels.hint), 'x');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        _expectNoOverflow(tester, width: 375);

        for (final s in _sheetStrings(tester)) {
          final lower = s.toLowerCase();
          for (final word in ['beacon', 'room', 'episode']) {
            expect(lower, isNot(contains(word)), reason: '«$s»');
          }
        }
      });

      testWidgets('at 375x667 in ${locale.languageCode} the bring picker '
          'shows Saved and All without overflow', (tester) async {
        await _openBring(
          tester,
          _Repo(saved: _savedN(2)),
          locale: locale,
          size: const Size(375, 667),
        );
        _expectNoOverflow(tester, width: 375);
        final tabs = _tabs(tester);
        expect(tabs, isNotNull);
        expect(tabs!.tabs, [
          predicate<String>((t) => t.contains(labels.saved)),
          labels.all,
        ]);
        expect(_searchField(labels.hint), findsOneWidget);
        for (final s in _sheetStrings(tester)) {
          final lower = s.toLowerCase();
          for (final word in ['beacon', 'room', 'episode']) {
            expect(lower, isNot(contains(word)), reason: '«$s»');
          }
        }
      });
    }
  });
}
