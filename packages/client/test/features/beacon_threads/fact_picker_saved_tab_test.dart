// The composer's fact picker has two tabs (plan D19, D20, §6.3): «In this
// Request» (or «In this Post») lists this episode's facts as before, and
// «Saved» lists the viewer's saved facts with their current text and a
// search field. Picking a saved fact that lives in this episode quotes it;
// picking one from elsewhere copies it here (BeaconFactCardCopy), reloads
// the room's facts and quotes the copy (alreadyThere behaves the same). Each
// row's ⋮ offers «Remove from saved»; an unavailable row reads «No longer
// available» and offers only removal. The Saved tab is absent in a read-only
// room. Copy failures show the §6.2 snackbars, and a row that fails as
// unavailable re-renders as «No longer available».
//
// The picker is opened through `showFactPickerSheet` over a real RoomCubit
// whose BeaconThreadsCase (also registered in GetIt) wraps a fake fact
// repository; the real-path test swaps that repository for the production
// one over a stubbed HTTP transport (HTTP -> Ferry -> repository mapping ->
// RoomCubit -> picker).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/exception/server_error_copy.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/message/discussion_read_only_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_picker_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'fact_origin_test_support.dart';
import 'room_cubit_fakes.dart';

const _room = kRoomCubitFakeBeaconId;
const _otherBeacon = 'Bother0000001';

const _tabRequest = 'In this Request';
const _tabPost = 'In this Post';
const _tabSaved = 'Saved';
const _removeFromSaved = 'Remove from saved';
const _noLongerAvailable = 'No longer available';
const _snackUnavailable = 'This fact is no longer available';
const _snackAttachmentGone = 'An attachment is no longer available';
const _snackUnauthorized = "You can't add facts there";

const _roomFactId = 'Froom00000001';
const _roomFactText = 'Meet at the north gate';

const _hereSavedId = 'Fhere00000001';
const _hereSavedText = 'Key is under the mat, blue door';

const _elsewhereId = 'Fother0000001';
const _elsewhereText = 'Shed code 4471';

const _goneId = 'Fgone00000001';

const _copiedId = 'Fcopied000001';

BeaconFactCard _card(String id, String text, {String beaconId = _room}) =>
    BeaconFactCard(
      id: id,
      beaconId: beaconId,
      factText: text,
      visibility: BeaconFactCardVisibilityBits.public,
      pinnedBy: 'Ubob',
      pinnedByTitle: 'Bob',
      createdAt: DateTime.utc(2026, 11),
      status: BeaconFactCardStatusBits.active,
      revisionSeq: 2,
    );

BeaconSavedFact _saved(
  String id,
  String text, {
  String beaconId = _otherBeacon,
}) => (
  factCardId: id,
  available: true,
  beaconId: beaconId,
  beaconKind: 0,
  factText: text,
  attachmentsJson: '[]',
);

BeaconSavedFact _gone(String id) => (
  factCardId: id,
  available: false,
  beaconId: null,
  beaconKind: null,
  factText: null,
  attachmentsJson: null,
);

/// Server-side fake: the room's fact list, the viewer's saved list and the
/// copy mutation. A successful copy puts the copy into the room's list (it
/// is not in the cubit until the facts are reloaded).
class _SavedRepo extends FakeBeaconFactCardRepository {
  _SavedRepo({
    List<BeaconFactCard>? roomFacts,
    List<BeaconSavedFact>? saved,
    this.copyOutcome = BeaconFactCopyOutcome.created,
  }) : roomFacts = roomFacts ?? [_card(_roomFactId, _roomFactText)],
       saved = saved ?? [];

  final List<BeaconFactCard> roomFacts;
  final List<BeaconSavedFact> saved;
  BeaconFactCopyOutcome copyOutcome;

  /// Calls in order: `list:<beaconId>`, `copy:<source>-><dest>`, `saved`,
  /// `unsave:<id>`.
  final log = <String>[];
  final copyCalls = <({String sourceFactCardId, String destinationBeaconId})>[];
  final unsaveCalls = <String>[];

  int get listCalls => log.where((e) => e.startsWith('list:')).length;

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
      sourceFactCardId: sourceFactCardId,
      destinationBeaconId: destinationBeaconId,
    ));
    final source = saved.firstWhere((s) => s.factCardId == sourceFactCardId);
    if (!roomFacts.any((f) => f.id == _copiedId)) {
      roomFacts.add(_card(_copiedId, source.factText!));
    }
    return (factCardId: _copiedId, outcome: copyOutcome);
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

/// A loaded real RoomCubit over the registered BeaconThreadsCase.
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

/// The page context the last picker was opened from.
late BuildContext _openerContext;

Future<RoomCubit> _openPicker(
  WidgetTester tester,
  BeaconFactCardRepository repo, {
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
    open: (ctx) {
      _openerContext = ctx;
      unawaited(showFactPickerSheet(ctx, cubit: cubit, isPost: isPost));
    },
  );
  expect(find.byType(FactPickerSheet), findsOneWidget);
  return cubit;
}

/// The row's remove action: an icon button whose tooltip says «remove», or
/// a button whose own label says it. The row's title text is not a control,
/// so a fact text containing «remove» never matches.
Finder _removeControlIn(String text) => _inRow(
  text,
  find.byWidgetPredicate((w) {
    bool says(String? s) => (s ?? '').toLowerCase().contains('remove');
    return switch (w) {
      IconButton(:final tooltip) => says(tooltip),
      ButtonStyleButton(:final child) => child is Text && says(child.data),
      _ => false,
    };
  }),
);

/// The unavailable row offers removal only: no ⋮ menu (so no «Remove from
/// saved» menu path, no copy or quote), just its remove action.
void _expectUnavailableRowOffersOnlyRemove() {
  expect(
    _inRow(_noLongerAvailable, find.byIcon(Icons.more_vert)),
    findsNothing,
    reason: 'an unavailable row has no ⋮ menu',
  );
  expect(
    _inRow(
      _noLongerAvailable,
      find.byWidgetPredicate((w) => w is PopupMenuButton),
    ),
    findsNothing,
    reason: 'an unavailable row has no menu',
  );
  expect(
    _removeControlIn(_noLongerAvailable),
    findsOneWidget,
    reason: 'an unavailable row has exactly one remove action',
  );
}

/// Taps the unavailable row's remove action.
Future<void> _removeUnavailableRow(
  WidgetTester tester, {
  bool realAsync = false,
}) async {
  _expectUnavailableRowOffersOnlyRemove();
  await tester.tap(_removeControlIn(_noLongerAvailable));
  if (realAsync) {
    await pumpRealAsync(tester);
  } else {
    await tester.pumpAndSettle();
  }
}

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(FactPickerSheet), matching: f);

Finder _tab(String label) => find.descendant(
  of: find.byType(TenturaUnderlineTabs),
  matching: find.text(label),
);

Future<void> _openSavedTab(
  WidgetTester tester, {
  String label = _tabSaved,
}) async {
  expect(
    _tab(label),
    findsOneWidget,
    reason: 'the picker has a «$label» tab (TenturaUnderlineTabs)',
  );
  await tester.tap(_tab(label));
  await tester.pumpAndSettle();
}

/// The picker row (ListTile) that shows [text].
Finder _row(String text) => find
    .ancestor(of: _inSheet(find.text(text)), matching: find.byType(ListTile))
    .first;

Finder _inRow(String text, Finder what) =>
    find.descendant(of: _row(text), matching: what);

Finder _inSnackBar(String text) => find.descendant(
  of: find.byType(SnackBar),
  matching: find.text(text, findRichText: true),
);

/// Records, for the first state that carries a pending quote, whether the
/// quoted fact was already in the room's fact list.
class _QuoteWatch {
  _QuoteWatch(RoomCubit cubit) {
    final sub = cubit.stream.listen((s) {
      final q = s.pendingQuotedFact;
      if (q != null && quotedFactWasListed == null) {
        quotedFactWasListed = s.factCards.any((f) => f.id == q.factCardId);
      }
    });
    addTearDown(() async {
      await sub.cancel();
    });
  }

  bool? quotedFactWasListed;
}

void main() {
  group('tabs', () {
    testWidgets('a Request room shows «In this Request» and «Saved» tabs; the '
        'first lists this episode’s facts and a tap still quotes one', (
      tester,
    ) async {
      final repo = _SavedRepo(saved: [_saved(_elsewhereId, _elsewhereText)]);
      final cubit = await _openPicker(tester, repo);

      expect(_tab(_tabRequest), findsOneWidget);
      expect(_tab(_tabSaved), findsOneWidget);
      expect(_tab(_tabPost), findsNothing);
      expect(_inSheet(find.text(_roomFactText)), findsOneWidget);

      await tester.tap(_inSheet(find.text(_roomFactText)));
      await tester.pumpAndSettle();

      expect(cubit.state.pendingQuotedFact?.factCardId, _roomFactId);
      expect(repo.copyCalls, isEmpty);
    });

    testWidgets('a Post room’s first tab reads «In this Post»', (tester) async {
      final repo = _SavedRepo(saved: [_saved(_elsewhereId, _elsewhereText)]);
      await _openPicker(tester, repo, isPost: true);

      expect(_tab(_tabPost), findsOneWidget);
      expect(_tab(_tabSaved), findsOneWidget);
      expect(_tab(_tabRequest), findsNothing);
    });

    testWidgets('a Post room’s «In this Post» tab lists the Post’s facts and '
        'a tap quotes one without a copy', (tester) async {
      final repo = _SavedRepo(saved: [_saved(_elsewhereId, _elsewhereText)]);
      final cubit = await _openPicker(tester, repo, isPost: true);

      expect(_tab(_tabPost), findsOneWidget);
      expect(_inSheet(find.text(_roomFactText)), findsOneWidget);
      expect(_inSheet(find.text(_elsewhereText)), findsNothing);

      await tester.tap(_inSheet(find.text(_roomFactText)));
      await tester.pumpAndSettle();

      expect(cubit.state.pendingQuotedFact?.factCardId, _roomFactId);
      expect(repo.copyCalls, isEmpty);
    });

    testWidgets('the Saved tab is shown in a writable room and absent once '
        'the room is read-only', (tester) async {
      final repo = _SavedRepo(saved: [_saved(_elsewhereId, _elsewhereText)]);
      final writableCubit = await _openPicker(tester, repo);
      expect(_tab(_tabSaved), findsOneWidget);

      // Same room, now closed: reopen the picker.
      Navigator.of(tester.element(find.byType(FactPickerSheet))).pop();
      await tester.pumpAndSettle();
      writableCubit.syncBeaconStatus(BeaconStatus.closed);
      expect(writableCubit.state.canWriteDiscussion, isFalse);
      unawaited(showFactPickerSheet(_openerContext, cubit: writableCubit));
      await tester.pumpAndSettle();

      expect(find.byType(FactPickerSheet), findsOneWidget);
      expect(_inSheet(find.text(_tabSaved)), findsNothing);
      expect(_inSheet(find.text(_elsewhereText)), findsNothing);
      expect(
        _inSheet(find.text(_roomFactText)),
        findsOneWidget,
        reason: 'this episode’s facts stay listed in a read-only room',
      );
    });
  });

  group('Saved tab list', () {
    final six = [
      _saved(_elsewhereId, _elsewhereText),
      _saved('Fsaved0000002', 'Gate code is 9 1 2'),
      _saved('Fsaved0000003', 'Bring gloves'),
      _saved('Fsaved0000004', 'Ladder in the garage'),
      _saved('Fsaved0000005', 'Wifi password tentura'),
      _saved('Fsaved0000006', 'Quiet hours after ten'),
    ];

    testWidgets('lists every saved fact with its current text, not this '
        'episode’s own facts', (tester) async {
      final repo = _SavedRepo(saved: List.of(six));
      await _openPicker(tester, repo);
      await _openSavedTab(tester);

      for (final s in six) {
        await tester.dragUntilVisible(
          _inSheet(find.text(s.factText!)),
          _inSheet(find.byType(Scrollable)).last,
          const Offset(0, -80),
        );
        expect(_inSheet(find.text(s.factText!)), findsOneWidget);
      }
      expect(_inSheet(find.text(_roomFactText)), findsNothing);
    });

    testWidgets('search filters the saved facts by text', (tester) async {
      final repo = _SavedRepo(saved: List.of(six));
      await _openPicker(tester, repo);
      await _openSavedTab(tester);

      final field = _inSheet(find.byType(TextField));
      expect(field, findsOneWidget, reason: 'the Saved tab has a search field');
      await tester.enterText(field, 'code');
      await tester.pumpAndSettle();

      expect(_inSheet(find.text(_elsewhereText)), findsOneWidget);
      expect(_inSheet(find.text('Gate code is 9 1 2')), findsOneWidget);
      expect(_inSheet(find.text('Bring gloves')), findsNothing);
      expect(_inSheet(find.text('Ladder in the garage')), findsNothing);
      expect(_inSheet(find.text('Quiet hours after ten')), findsNothing);
    });

    testWidgets('⋮ «Remove from saved» unsaves that fact and drops its row', (
      tester,
    ) async {
      final repo = _SavedRepo(
        saved: [
          _saved(_elsewhereId, _elsewhereText),
          _saved('Fsaved0000003', 'Bring gloves'),
        ],
      );
      await _openPicker(tester, repo);
      await _openSavedTab(tester);

      final menu = _inRow(_elsewhereText, find.byIcon(Icons.more_vert));
      expect(menu, findsOneWidget, reason: 'an available row has a ⋮ menu');
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(find.text(_removeFromSaved), findsOneWidget);
      await tester.tap(find.text(_removeFromSaved));
      await tester.pumpAndSettle();

      expect(repo.unsaveCalls, [_elsewhereId]);
      expect(_inSheet(find.text(_elsewhereText)), findsNothing);
      expect(_inSheet(find.text('Bring gloves')), findsOneWidget);
      expect(repo.copyCalls, isEmpty);
    });

    testWidgets('an unavailable row reads «No longer available», cannot be '
        'picked and can only be removed', (tester) async {
      final repo = _SavedRepo(
        saved: [_saved(_elsewhereId, _elsewhereText), _gone(_goneId)],
      );
      final cubit = await _openPicker(tester, repo);
      await _openSavedTab(tester);

      expect(_inSheet(find.text(_noLongerAvailable)), findsOneWidget);

      await tester.tap(_inSheet(find.text(_noLongerAvailable)));
      await tester.pumpAndSettle();
      expect(repo.copyCalls, isEmpty);
      expect(cubit.state.pendingQuotedFact, isNull);
      expect(find.byType(FactPickerSheet), findsOneWidget);

      await _removeUnavailableRow(tester);

      expect(repo.unsaveCalls, [_goneId]);
      expect(_inSheet(find.text(_noLongerAvailable)), findsNothing);
      expect(_inSheet(find.text(_elsewhereText)), findsOneWidget);
    });
  });

  group('picking a saved fact', () {
    testWidgets('a saved fact of this episode is quoted without a copy', (
      tester,
    ) async {
      final repo = _SavedRepo(
        roomFacts: [
          _card(_roomFactId, _roomFactText),
          _card(_hereSavedId, _hereSavedText),
        ],
        saved: [_saved(_hereSavedId, _hereSavedText, beaconId: _room)],
      );
      final cubit = await _openPicker(tester, repo);
      await _openSavedTab(tester);

      await tester.tap(_inSheet(find.text(_hereSavedText)));
      await tester.pumpAndSettle();

      expect(repo.copyCalls, isEmpty);
      expect(cubit.state.pendingQuotedFact?.factCardId, _hereSavedId);
      expect(cubit.state.pendingQuotedFact?.factText, _hereSavedText);
    });

    for (final outcome in BeaconFactCopyOutcome.values) {
      testWidgets('a saved fact from elsewhere is copied into this room '
          '(${outcome.name}), the facts reload and the copy becomes the '
          'quote', (tester) async {
        final repo = _SavedRepo(
          saved: [_saved(_elsewhereId, _elsewhereText)],
          copyOutcome: outcome,
        );
        final cubit = await _openPicker(tester, repo);
        await _openSavedTab(tester);
        final watch = _QuoteWatch(cubit);
        final listsBefore = repo.listCalls;
        final generic = (await L10n.delegate.load(
          const Locale('en'),
        )).errorGenericAction;

        await tester.tap(_inSheet(find.text(_elsewhereText)));
        await tester.pumpAndSettle();

        expect(repo.copyCalls, [
          (sourceFactCardId: _elsewhereId, destinationBeaconId: _room),
        ]);
        final copyAt = repo.log.indexOf('copy:$_elsewhereId->$_room');
        expect(
          repo.log.skip(copyAt + 1).any((e) => e == 'list:$_room'),
          isTrue,
          reason: 'the room’s facts are reloaded after the copy',
        );
        expect(repo.listCalls, greaterThan(listsBefore));
        expect(cubit.state.factCards.map((f) => f.id), contains(_copiedId));
        expect(cubit.state.pendingQuotedFact?.factCardId, _copiedId);
        expect(cubit.state.pendingQuotedFact?.factText, _elsewhereText);
        expect(
          watch.quotedFactWasListed,
          isTrue,
          reason: 'the quote is set only after the reloaded list has the copy',
        );
        expect(find.byType(SnackBar), findsNothing);
        expect(find.text(generic, findRichText: true), findsNothing);
      });
    }
  });

  group('copy failures (server error -> repository mapping -> snackbar)', () {
    // Each case is a GraphQL error on BeaconFactCardCopy as the server sends
    // it, mapped by the production repository; the expected text is the
    // app's existing string for that error.
    final cases = <(String, int, String, FutureOr<String> Function())>[
      (
        'not allowed: the server UnauthorizedException (1102)',
        1102,
        'User is not authorized',
        () => _snackUnauthorized,
      ),
      (
        'room read-only (1301)',
        1301,
        'Discussion is read-only for this request',
        () => const DiscussionReadOnlyMessage().toEn,
      ),
      (
        'fact rate limit (1320)',
        1320,
        'rate limited',
        () async =>
            (await L10n.delegate.load(const Locale('en'))).planErrorRateLimited,
      ),
      (
        'daily upload cap (1005)',
        1005,
        'Daily upload limit reached, try again tomorrow',
        () => kServerErrorCopy['1005']!.en,
      ),
    ];

    for (final (name, code, message, expected) in cases) {
      testWidgets('$name shows its existing message and sets no quote', (
        tester,
      ) async {
        final wire = await _SavedWire.start(
          tester,
          copyErrorCode: code,
          copyErrorMessage: message,
        );
        final cubit = await _openWirePicker(tester, wire);
        final text = await expected();
        final generic = (await L10n.delegate.load(
          const Locale('en'),
        )).errorGenericAction;

        await tester.tap(_inSheet(find.text(_elsewhereText)));
        await pumpRealAsync(tester);

        expect(wire.copyVariables, hasLength(1));
        expect(_inSnackBar(text), findsOneWidget);
        expect(find.text(generic, findRichText: true), findsNothing);
        expect(cubit.state.pendingQuotedFact, isNull);
      });
    }

    testWidgets('source unavailable (1352) shows «This fact is no longer '
        'available», the row re-renders as «No longer available» and no '
        'quote is set', (tester) async {
      final wire = await _SavedWire.start(
        tester,
        copyErrorCode: 1352,
        copyErrorMessage: 'Fact source unavailable',
      );
      final cubit = await _openWirePicker(tester, wire);

      await tester.tap(_inSheet(find.text(_elsewhereText)));
      await pumpRealAsync(tester);

      expect(wire.copyVariables, hasLength(1));
      expect(_inSnackBar(_snackUnavailable), findsOneWidget);
      expect(cubit.state.pendingQuotedFact, isNull);
      expect(find.byType(FactPickerSheet), findsOneWidget);
      expect(_inSheet(find.text(_elsewhereText)), findsNothing);
      expect(_inSheet(find.text(_noLongerAvailable)), findsOneWidget);
      _expectUnavailableRowOffersOnlyRemove();
    });

    testWidgets('Russian locale: source unavailable (1352) shows the Russian '
        '«This fact is no longer available» and the row reads the Russian '
        '«No longer available»', (tester) async {
      final wire = await _SavedWire.start(
        tester,
        copyErrorCode: 1352,
        copyErrorMessage: 'Fact source unavailable',
      );
      final cubit = await _openWirePicker(
        tester,
        wire,
        locale: const Locale('ru'),
      );

      await tester.tap(_inSheet(find.text(_elsewhereText)));
      await pumpRealAsync(tester);

      expect(wire.copyVariables, hasLength(1));
      expect(_inSnackBar(russianFor(_snackUnavailable)), findsOneWidget);
      expect(_inSnackBar(_snackUnavailable), findsNothing);
      expect(
        _inSheet(find.text(russianFor(_noLongerAvailable))),
        findsOneWidget,
      );
      expect(_inSheet(find.text(_noLongerAvailable)), findsNothing);
      expect(cubit.state.pendingQuotedFact, isNull);
    });

    testWidgets('an attachment that is gone (1354) shows «an attachment is no '
        'longer available», not the whole-fact message, and the row stays '
        'copyable', (tester) async {
      final wire = await _SavedWire.start(
        tester,
        copyErrorCode: 1354,
        copyErrorMessage: 'Fact attachment no longer available',
      );
      final cubit = await _openWirePicker(tester, wire);
      final generic = (await L10n.delegate.load(
        const Locale('en'),
      )).errorGenericAction;

      await tester.tap(_inSheet(find.text(_elsewhereText)));
      await pumpRealAsync(tester);

      expect(wire.copyVariables, hasLength(1));
      expect(_inSnackBar(_snackAttachmentGone), findsOneWidget);
      expect(_inSnackBar(_snackUnavailable), findsNothing);
      expect(find.text(generic, findRichText: true), findsNothing);
      expect(cubit.state.pendingQuotedFact, isNull);
      expect(_inSheet(find.text(_elsewhereText)), findsOneWidget);
      expect(_inSheet(find.text(_noLongerAvailable)), findsNothing);
    });

    testWidgets('Russian locale: an attachment that is gone (1354) shows the '
        'Russian attachment message, not the whole-fact one', (tester) async {
      final wire = await _SavedWire.start(
        tester,
        copyErrorCode: 1354,
        copyErrorMessage: 'Fact attachment no longer available',
      );
      final cubit = await _openWirePicker(
        tester,
        wire,
        locale: const Locale('ru'),
      );
      final generic = (await L10n.delegate.load(
        const Locale('ru'),
      )).errorGenericAction;

      await tester.tap(_inSheet(find.text(_elsewhereText)));
      await pumpRealAsync(tester);

      expect(wire.copyVariables, hasLength(1));
      expect(russianFor(_snackAttachmentGone), isNot(russianFor(_snackUnavailable)));
      expect(_inSnackBar(russianFor(_snackAttachmentGone)), findsOneWidget);
      expect(_inSnackBar(russianFor(_snackUnavailable)), findsNothing);
      expect(find.text(generic, findRichText: true), findsNothing);
      expect(cubit.state.pendingQuotedFact, isNull);
      expect(
        _inSheet(find.text(russianFor(_noLongerAvailable))),
        findsNothing,
      );
      expect(_inSheet(find.text(_elsewhereText)), findsOneWidget);
    });

    testWidgets('Russian locale: read-only (1301) shows the Russian '
        'read-only message', (tester) async {
      final wire = await _SavedWire.start(
        tester,
        copyErrorCode: 1301,
        copyErrorMessage: 'Discussion is read-only for this request',
      );
      await _openWirePicker(tester, wire, locale: const Locale('ru'));

      await tester.tap(_inSheet(find.text(_elsewhereText)));
      await pumpRealAsync(tester);

      final ru = const DiscussionReadOnlyMessage().toL10n('ru');
      expect(hasCyrillic(ru), isTrue);
      expect(_inSnackBar(ru), findsOneWidget);
      expect(
        _inSnackBar(const DiscussionReadOnlyMessage().toEn),
        findsNothing,
      );
    });
  });

  group('Russian locale', () {
    testWidgets('375×667: tabs, rows, menu and «No longer available» are '
        'Russian and nothing overflows', (tester) async {
      final repo = _SavedRepo(
        saved: [
          _saved(
            _elsewhereId,
            'Код от сарая 4471, ключ под ковриком у синей двери, '
            'не забудьте закрыть',
          ),
          _gone(_goneId),
        ],
      );
      await _openPicker(
        tester,
        repo,
        locale: const Locale('ru'),
        size: const Size(375, 667),
      );

      expect(_tab(russianFor(_tabRequest)), findsOneWidget);
      final savedRu = russianValuesFor(_tabSaved);
      final savedTab = [
        for (final ru in savedRu)
          if (_tab(ru).evaluate().isNotEmpty) ru,
      ];
      expect(savedTab, hasLength(1), reason: 'the Saved tab is in Russian');
      expect(hasCyrillic(savedTab.single), isTrue);
      await _openSavedTab(tester, label: savedTab.single);

      expect(
        _inSheet(find.text(russianFor(_noLongerAvailable))),
        findsOneWidget,
      );
      expect(_inSheet(find.text(_noLongerAvailable)), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(
        _inRow(
          'Код от сарая 4471, ключ под ковриком у синей двери, '
          'не забудьте закрыть',
          find.byIcon(Icons.more_vert),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(russianFor(_removeFromSaved)), findsOneWidget);
      expect(find.text(_removeFromSaved), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a Post room’s first tab reads the Russian «In this Post»', (
      tester,
    ) async {
      await _openPicker(
        tester,
        _SavedRepo(saved: [_saved(_elsewhereId, _elsewhereText)]),
        isPost: true,
        locale: const Locale('ru'),
        size: const Size(375, 667),
      );
      final shown = [
        for (final ru in russianValuesFor(_tabPost))
          if (_tab(ru).evaluate().isNotEmpty) ru,
      ];
      expect(shown, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    test('every new picker string has an English and a Russian ARB entry', () {
      for (final en in [_tabRequest, _removeFromSaved, _noLongerAvailable]) {
        expect(
          hasCyrillic(russianFor(en)),
          isTrue,
          reason: 'app_ru.arb translates «$en»',
        );
      }
      for (final en in [_tabSaved, _tabPost]) {
        expect(russianValuesFor(en), isNotEmpty);
        expect(russianValuesFor(en).every(hasCyrillic), isTrue);
      }
    });
  });

  group('real path (HTTP -> Ferry -> repository -> RoomCubit -> picker)', () {
    for (final outcome in ['created', 'alreadyThere']) {
      testWidgets('picking a saved fact from another Request ($outcome) '
          'quotes the copy here without an error', (tester) async {
        final wire = await _SavedWire.start(tester, copyOutcome: outcome);
        final generic = (await L10n.delegate.load(
          const Locale('en'),
        )).errorGenericAction;
        final cubit = await _openWirePicker(tester, wire);

        await tester.tap(_inSheet(find.text(_elsewhereText)));
        await pumpRealAsync(tester);
        await pumpRealAsync(tester);

        expect(wire.copyVariables, [
          {'sourceFactCardId': _elsewhereId, 'destinationBeaconId': _room},
        ]);
        final copyAt = wire.sent.indexOf('BeaconFactCardCopy');
        expect(
          wire.sent.skip(copyAt + 1),
          contains('BeaconFactCardList'),
          reason: 'the facts are reloaded after the copy',
        );
        expect(cubit.state.factCards.map((f) => f.id), contains(_copiedId));
        expect(cubit.state.pendingQuotedFact?.factCardId, _copiedId);
        expect(cubit.state.pendingQuotedFact?.factText, _elsewhereText);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.text(generic, findRichText: true), findsNothing);
      });
    }

    testWidgets('an available:false SavedList row reads «No longer '
        'available», cannot be picked, and removing it sends '
        'BeaconFactCardUnsave', (tester) async {
      final wire = await _SavedWire.start(tester, withUnavailableRow: true);
      final cubit = await _openWirePicker(tester, wire);

      expect(_inSheet(find.text(_noLongerAvailable)), findsOneWidget);
      await tester.tap(_inSheet(find.text(_noLongerAvailable)));
      await pumpRealAsync(tester);
      expect(wire.copyVariables, isEmpty);
      expect(cubit.state.pendingQuotedFact, isNull);

      await _removeUnavailableRow(tester, realAsync: true);

      expect(wire.unsaveVariables, [
        {'factCardId': _goneId},
      ]);
      expect(_inSheet(find.text(_noLongerAvailable)), findsNothing);
      expect(_inSheet(find.text(_elsewhereText)), findsOneWidget);
    });
  });
}

/// Opens the picker over [wire] (real repository and RoomCubit) and shows
/// the Saved tab as answered by BeaconFactCardSavedList.
Future<RoomCubit> _openWirePicker(
  WidgetTester tester,
  _SavedWire wire, {
  Locale locale = const Locale('en'),
}) async {
  _registerLogger();
  registerFactRepository(wire.repository);
  late RoomCubit cubit;
  await tester.runAsync(() async {
    cubit = await _roomCubit(writable: true);
  });
  expect(cubit.state.factCards.map((f) => f.id), [_roomFactId]);

  await pumpOpener(
    tester,
    locale: locale,
    open: (ctx) => unawaited(showFactPickerSheet(ctx, cubit: cubit)),
  );
  final savedLabels = locale.languageCode == 'en'
      ? {_tabSaved}
      : russianValuesFor(_tabSaved);
  final savedTab = [
    for (final label in savedLabels)
      if (_tab(label).evaluate().isNotEmpty) label,
  ];
  expect(savedTab, hasLength(1), reason: 'the picker has a Saved tab');
  await tester.tap(_tab(savedTab.single));
  await pumpRealAsync(tester);
  expect(wire.sent, contains('BeaconFactCardSavedList'));
  expect(_inSheet(find.text(_elsewhereText)), findsOneWidget);
  return cubit;
}

/// The production fact repository over a stubbed HTTP transport. The room
/// lists [_roomFactId] until BeaconFactCardCopy runs, then also the copy.
final class _SavedWire {
  _SavedWire._(this.repository);

  final BeaconFactCardRepository repository;
  final sent = <String>[];
  final copyVariables = <Map<String, dynamic>>[];
  final unsaveVariables = <Map<String, dynamic>>[];
  var _copied = false;
  int? copyErrorCode;
  String copyErrorMessage = 'failed';
  bool withUnavailableRow = false;
  String copyOutcome = 'created';
  final _unsaved = <String>{};

  static Map<String, Object?> _row(String id, String text) => {
    '__typename': 'v2_BeaconFactCardRow',
    'id': id,
    'beaconId': _room,
    'factText': text,
    'visibility': BeaconFactCardVisibilityBits.public,
    'pinnedBy': 'Ubob',
    'pinnedByTitle': 'Bob',
    'sourceMessageId': null,
    'status': BeaconFactCardStatusBits.active,
    'createdAt': '2026-11-01T00:00:00.000Z',
    'updatedAt': null,
    'attachmentsJson': '[]',
    'revisionSeq': 1,
    'lastEditedBy': null,
    'lastEditedByTitle': null,
    'lastEditedAt': null,
    'otherEditorCount': 0,
    'historyTruncated': false,
    'originBeaconKind': id == _copiedId ? 0 : null,
    'savedByMe': false,
  };

  static Future<_SavedWire> start(
    WidgetTester tester, {
    int? copyErrorCode,
    String copyErrorMessage = 'failed',
    bool withUnavailableRow = false,
    String copyOutcome = 'created',
  }) async {
    late _SavedWire wire;
    late RemoteApiService remote;
    await tester.runAsync(() async {
      await http.runWithClient(
        () async {
          remote = RemoteApiService(
            const Env(),
            const WebSocketClientRealtimeSocketFactory(),
          );
          await remote.setSessionAuth();
          await remote.getAuthToken();
          wire = _SavedWire._(BeaconFactCardRepository(remote))
            ..copyErrorCode = copyErrorCode
            ..copyErrorMessage = copyErrorMessage
            ..withUnavailableRow = withUnavailableRow
            ..copyOutcome = copyOutcome;
        },
        () => MockClient((request) async {
          http.Response json(Object body) => http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
          );
          if (request.url.path.endsWith('/session/access-token')) {
            return json({
              'subject': 'Uviewer000001',
              'access_token': 'test-token',
              'expires_in': 3600,
            });
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final name = body['operationName'] as String;
          final vars = (body['variables'] as Map).cast<String, dynamic>();
          wire.sent.add(name);
          if (name == 'BeaconFactCardCopy') {
            wire.copyVariables.add(vars);
            final code = wire.copyErrorCode;
            if (code != null) {
              return json({
                'data': null,
                'errors': [
                  {
                    'message': wire.copyErrorMessage,
                    'extensions': {'code': code},
                  },
                ],
              });
            }
            wire._copied = true;
          }
          if (name == 'BeaconFactCardUnsave') {
            wire
              ..unsaveVariables.add(vars)
              .._unsaved.add(vars['factCardId'] as String);
          }
          return json({
            'data': switch (name) {
              'BeaconFactCardList' => {
                '__typename': 'query_root',
                'BeaconFactCardList': [
                  _row(_roomFactId, _roomFactText),
                  if (wire._copied) _row(_copiedId, _elsewhereText),
                ],
              },
              'BeaconFactCardSavedList' => {
                '__typename': 'query_root',
                'BeaconFactCardSavedList': [
                  if (wire.withUnavailableRow &&
                      !wire._unsaved.contains(_goneId))
                    {
                      '__typename': 'v2_BeaconFactCardSavedRow',
                      'factCardId': _goneId,
                      'available': false,
                      'beaconId': null,
                      'beaconKind': null,
                      'factText': null,
                      'attachmentsJson': null,
                    },
                  {
                    '__typename': 'v2_BeaconFactCardSavedRow',
                    'factCardId': _elsewhereId,
                    'available': true,
                    'beaconId': _otherBeacon,
                    'beaconKind': 0,
                    'factText': _elsewhereText,
                    'attachmentsJson': '[]',
                  },
                ],
              },
              'BeaconFactCardUnsave' => {
                '__typename': 'mutation_root',
                'BeaconFactCardUnsave': true,
              },
              'BeaconFactCardCopy' => {
                '__typename': 'mutation_root',
                'BeaconFactCardCopy': {
                  '__typename': 'v2_BeaconFactCardCopyResult',
                  'factCardId': _copiedId,
                  'outcome': wire.copyOutcome,
                },
              },
              _ => null,
            },
          });
        }),
      );
    });
    addTearDown(() => tester.runAsync(remote.close));
    return wire;
  }
}
