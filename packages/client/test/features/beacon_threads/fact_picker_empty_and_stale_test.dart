// The fact picker sheet: every scope says so when no row is visible (instead
// of a blank list under the search field), and hits of an old query are not
// shown or tappable while the answer for a changed query is pending.
//
// Run over the production BeaconThreadsCase (GetIt) wrapping a fake fact
// repository, as the other picker sheet tests do.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_picker_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'fact_origin_test_support.dart';
import 'room_cubit_fakes.dart';

const _room = kRoomCubitFakeBeaconId;
const _other = 'Bother0000001';
const _bringBeacon = 'B1';

final _en = lookupL10n(const Locale('en'));

BeaconFactCard _card(String id, String text) => BeaconFactCard(
  id: id,
  beaconId: _room,
  factText: text,
  visibility: BeaconFactCardVisibilityBits.public,
  pinnedBy: 'Ubob',
  pinnedByTitle: 'Bob',
  createdAt: DateTime.utc(2026, 11),
  status: BeaconFactCardStatusBits.active,
  revisionSeq: 2,
);

BeaconSavedFact _saved(String id, String text, {String beaconId = _other}) => (
  factCardId: id,
  available: true,
  beaconId: beaconId,
  beaconKind: 0,
  factText: text,
  attachmentsJson: '[]',
);

BeaconFactSearchHit _hit(String id, String text) => (
  factCardId: id,
  beaconId: _other,
  beaconKind: 0,
  factText: text,
  attachmentsJson: '[]',
  saved: false,
);

class _Repo extends FakeBeaconFactCardRepository {
  _Repo({this.roomFacts = const [], this.saved = const []});

  final List<BeaconFactCard> roomFacts;
  final List<BeaconSavedFact> saved;
  Future<List<BeaconFactSearchHit>> Function(String query)? onSearch;
  final copyCalls = <String>[];
  final searchCalls = <String>[];

  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) async =>
      roomFacts.where((f) => f.beaconId == beaconId).toList();

  @override
  Future<List<BeaconSavedFact>> savedList() async => List.of(saved);

  @override
  Future<List<BeaconFactSearchHit>> search({
    required String query,
    String? excludeBeaconId,
  }) {
    searchCalls.add(query);
    return onSearch?.call(query) ?? Future.value(const []);
  }

  @override
  Future<BeaconFactCopyResult> copy({
    required String sourceFactCardId,
    required String destinationBeaconId,
  }) async {
    copyCalls.add(sourceFactCardId);
    return (
      factCardId: '$sourceFactCardId-copy',
      outcome: BeaconFactCopyOutcome.created,
    );
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

Future<void> _openBring(WidgetTester tester, _Repo repo) async {
  _registerLogger();
  registerFactRepository(repo);
  await pumpOpener(
    tester,
    open: (ctx) => unawaited(
      showFactPickFromAvailableSheet(
        ctx,
        beaconId: _bringBeacon,
        isPost: false,
        onBrought: () async {},
      ),
    ),
  );
  expect(find.byType(FactPickerSheet), findsOneWidget);
}

Future<void> _openQuote(WidgetTester tester, _Repo repo) async {
  _registerLogger();
  registerFactRepository(repo);
  registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
  final fakeRoom = FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId);
  addTearDown(fakeRoom.dispose);
  final cubit = roomCubitForTest(
    fakeRoom,
    beaconRoomCase: GetIt.instance<BeaconThreadsCase>(),
  );
  addTearDown(cubit.close);
  await awaitRoomCubitLoad(cubit);
  cubit.syncBeaconStatus(BeaconStatus.open);
  await pumpOpener(
    tester,
    open: (ctx) => unawaited(showFactPickerSheet(ctx, cubit: cubit)),
  );
  expect(find.byType(FactPickerSheet), findsOneWidget);
}

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(FactPickerSheet), matching: f);

Finder _searchField() => _inSheet(
  find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == _en.factPickerSearchHint,
  ),
);

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: _inSheet(find.byType(TenturaUnderlineTabs)),
      matching: find.textContaining(label),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_searchField(), text);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  group('FactPickerSheet empty states', () {
    testWidgets("Saved scope with only this Request's facts saved shows the "
        'Saved empty text, not a blank list', (tester) async {
      await _openBring(
        tester,
        _Repo(saved: [_saved('F1', 'own fact', beaconId: _bringBeacon)]),
      );
      expect(
        _inSheet(find.text(_en.beaconRoomFactPickerSavedEmpty)),
        findsOneWidget,
      );
      expect(_inSheet(find.text('own fact')), findsNothing);
      expect(_inSheet(find.byType(ListTile)), findsNothing);
    });

    testWidgets(
      'Saved scope with a query matching nothing says Nothing found',
      (tester) async {
        await _openBring(
          tester,
          _Repo(saved: [_saved('F1', 'see banana')]),
        );
        expect(_inSheet(find.text('see banana')), findsOneWidget);
        await _type(tester, 'zzz');
        expect(_inSheet(find.text('see banana')), findsNothing);
        expect(_inSheet(find.text(_en.capabilitySearchEmpty)), findsOneWidget);
      },
    );

    testWidgets('In-this-Request scope with a query matching nothing says '
        'Nothing found', (tester) async {
      await _openQuote(
        tester,
        _Repo(roomFacts: [_card('H1', 'see banana')]),
      );
      expect(_inSheet(find.text('see banana')), findsOneWidget);
      await _type(tester, 'zzz');
      expect(_inSheet(find.text('see banana')), findsNothing);
      expect(_inSheet(find.text(_en.capabilitySearchEmpty)), findsOneWidget);
    });

    testWidgets('In-this-Request scope with no facts and no query shows its '
        'empty text and no rows', (tester) async {
      await _openQuote(tester, _Repo());
      expect(_inSheet(find.text(_en.beaconFactsSheetEmpty)), findsOneWidget);
      expect(_inSheet(find.byType(ListTile)), findsNothing);
    });

    testWidgets('All scope with no server hits says Nothing found', (
      tester,
    ) async {
      await _openBring(tester, _Repo());
      await _openTab(tester, _en.factPickerTabAll);
      await _type(tester, 'anna');
      expect(_inSheet(find.text(_en.capabilitySearchEmpty)), findsOneWidget);
    });
  });

  group('FactPickerSheet All scope query length', () {
    testWidgets('@a shows the type-more hint and asks the server nothing', (
      tester,
    ) async {
      final repo = _Repo();
      await _openBring(tester, repo);
      await _openTab(tester, _en.factPickerTabAll);
      await _type(tester, '@a');
      expect(_inSheet(find.text(_en.factPickerTypeMore)), findsOneWidget);
      expect(repo.searchCalls, isEmpty);
    });
  });

  group('FactPickerSheet stale hits', () {
    testWidgets('a settled hit can be picked (control)', (tester) async {
      final repo = _Repo()
        ..onSearch = (_) => Future.value([_hit('H1', 'Anna fact')]);
      await _openBring(tester, repo);
      await _openTab(tester, _en.factPickerTabAll);
      await _type(tester, 'anna');
      await tester.tap(_inSheet(find.text('Anna fact')));
      await tester.pumpAndSettle();
      expect(repo.copyCalls, ['H1']);
    });

    testWidgets('after the query changes the old hit is gone or cannot be '
        'picked, before and after the debounce', (tester) async {
      final second = Completer<List<BeaconFactSearchHit>>();
      final repo = _Repo()
        ..onSearch = (q) => q == 'anna'
            ? Future.value([_hit('H1', 'Anna fact')])
            : second.future;
      await _openBring(tester, repo);
      await _openTab(tester, _en.factPickerTabAll);
      await _type(tester, 'anna');
      expect(_inSheet(find.text('Anna fact')), findsOneWidget);

      Future<void> tapOldIfShown() async {
        final old = _inSheet(find.text('Anna fact'));
        // Absent counts as cleared; a shown row must ignore taps.
        if (old.evaluate().isNotEmpty) {
          await tester.tap(old);
          await tester.pump();
        }
      }

      await tester.enterText(_searchField(), 'annab');
      await tester.pump();
      await tapOldIfShown();
      expect(repo.copyCalls, isEmpty);

      await tester.pump(const Duration(milliseconds: 400));
      await tapOldIfShown();
      expect(repo.copyCalls, isEmpty);

      second.complete([_hit('H2', 'Annab fact')]);
      await tester.pumpAndSettle();
      expect(_inSheet(find.text('Annab fact')), findsOneWidget);
    });
  });
}
