// tentura-617.32: edit-sheet "Pinned by …" banner + revision-conflict sheet
// fed by RoomCubit.factEditConflict (issue #181, plan §4 / §5 / §14.6).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_actions_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'room_cubit_fakes.dart';

const _kMe = kRoomCubitFakeMyUserId;
const _kFactId = 'f1';
const _kOpenSeq = 3;
const _kServerSeq = 5;
const _kOriginalText = 'Gate code is 4821';
const _kServerText = 'Gate code is 9999';
const _kMyText = 'Gate code is 1234';

const _kSaveMine = 'Save mine';
const _kKeepTheirs = 'Keep theirs';
const _kKeepEditing = 'Keep editing';

BeaconFactCard _fact({
  String pinnedBy = 'Uanna',
  String pinnedByTitle = 'Anna',
  String text = _kOriginalText,
  int seq = _kOpenSeq,
}) => BeaconFactCard(
  id: _kFactId,
  beaconId: kRoomCubitFakeBeaconId,
  factText: text,
  visibility: BeaconFactCardVisibilityBits.public,
  pinnedBy: pinnedBy,
  pinnedByTitle: pinnedByTitle,
  createdAt: DateTime.utc(2026),
  status: BeaconFactCardStatusBits.corrected,
  revisionSeq: seq,
);

typedef _CorrectCall = ({String factCardId, String newText, int baseSeq});

/// Records correctFact / clearFactEditConflict and simulates a revision
/// conflict the way [RoomCubit] does (facts refresh, then factEditConflict).
class _FactEditRoomCubit extends Mock implements RoomCubit {
  _FactEditRoomCubit(RoomState initial)
    : _state = initial,
      _controller = StreamController<RoomState>.broadcast();

  RoomState _state;
  final StreamController<RoomState> _controller;

  final correctCalls = <_CorrectCall>[];
  int clearConflictCalls = 0;

  /// When non-null, the next correctFact call ends in a conflict with this
  /// refreshed server card.
  BeaconFactCard? conflictOnNextCorrect;

  @override
  RoomState get state => _state;

  @override
  Stream<RoomState> get stream => _controller.stream;

  @override
  bool get isClosed => false;

  void _emit(RoomState next) {
    _state = next;
    _controller.add(next);
  }

  @override
  Future<void> correctFact({
    required String factCardId,
    required String newText,
    required int baseRevisionSeq,
  }) async {
    correctCalls.add((
      factCardId: factCardId,
      newText: newText,
      baseSeq: baseRevisionSeq,
    ));
    final conflict = conflictOnNextCorrect;
    conflictOnNextCorrect = null;
    if (conflict != null) {
      _emit(
        _state.copyWith(factCards: [conflict], factEditConflict: conflict),
      );
    } else {
      _emit(_state.copyWith(factEditConflict: null));
    }
  }

  @override
  void clearFactEditConflict() {
    clearConflictCalls++;
    if (_state.factEditConflict != null) {
      _emit(_state.copyWith(factEditConflict: null));
    }
  }

  @override
  Future<void> close() => _controller.close();
}

Future<_FactEditRoomCubit> _pumpHost(
  WidgetTester tester, {
  required BeaconFactCard fact,
}) async {
  registerRoomCubitProfileCubit(_kMe);
  await tester.binding.setSurfaceSize(const Size(375, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final cubit = _FactEditRoomCubit(
    RoomState(
      beaconId: kRoomCubitFakeBeaconId,
      myUserId: _kMe,
      factCards: [fact],
      beaconStatus: BeaconStatus.open,
    ),
  );
  addTearDown(cubit.close);

  await tester.pumpWidget(
    BlocProvider<RoomCubit>.value(
      value: cubit,
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showFactActionsSheet(
                  ctx,
                  cubit: cubit,
                  fact: fact,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return cubit;
}

/// Opens the manage sheet, then the edit sheet.
Future<L10n> _openEditor(WidgetTester tester) async {
  final l10n = await L10n.delegate.load(const Locale('en'));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.beaconRoomFactCardActionEdit));
  await tester.pumpAndSettle();
  expect(find.text(l10n.beaconRoomFactCardEditTitle), findsOneWidget);
  return l10n;
}

Finder _editorField() => find.byType(TextField);

/// Non-editable text (Text / Text.rich / SelectableText) containing [s].
Finder _staticTextContaining(String s) => find.byWidgetPredicate((w) {
  if (w is Text) {
    final plain = w.data ?? w.textSpan?.toPlainText() ?? '';
    return plain.contains(s);
  }
  if (w is SelectableText) {
    final plain = w.data ?? w.textSpan?.toPlainText() ?? '';
    return plain.contains(s);
  }
  return false;
});

/// Opens the editor, types [_kMyText], saves, and lands in the conflict sheet.
Future<_FactEditRoomCubit> _reachConflict(WidgetTester tester) async {
  final cubit = await _pumpHost(tester, fact: _fact());
  cubit.conflictOnNextCorrect = _fact(text: _kServerText, seq: _kServerSeq);
  await _openEditor(tester);

  await tester.enterText(_editorField(), _kMyText);
  await tester.pump();
  await tester.tap(
    find.text(
      MaterialLocalizations.of(
        tester.element(_editorField()),
      ).saveButtonLabel,
    ),
  );
  await tester.pumpAndSettle();

  expect(cubit.correctCalls, hasLength(1));
  expect(cubit.correctCalls.single.baseSeq, _kOpenSeq);
  expect(cubit.state.factEditConflict?.revisionSeq, _kServerSeq);
  return cubit;
}

void main() {
  group('edit sheet "Pinned by …" banner (tentura-617.32)', () {
    testWidgets("is shown when editing another user's fact", (tester) async {
      await _pumpHost(tester, fact: _fact());
      final l10n = await _openEditor(tester);

      expect(
        find.text(l10n.beaconRoomFactCardPinnedByLabel('Anna')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets("is hidden when editing one's own fact", (tester) async {
      await _pumpHost(
        tester,
        fact: _fact(pinnedBy: _kMe, pinnedByTitle: 'Me'),
      );
      final l10n = await _openEditor(tester);

      expect(
        find.text(l10n.beaconRoomFactCardPinnedByLabel('Me')),
        findsNothing,
      );
      expect(find.textContaining('Pinned by'), findsNothing);
    });
  });

  group('revision conflict sheet (tentura-617.32)', () {
    testWidgets(
      'a factEditConflict opens the sheet showing current and my text',
      (tester) async {
        await _reachConflict(tester);

        expect(find.text(_kSaveMine), findsOneWidget);
        expect(find.text(_kKeepTheirs), findsOneWidget);
        expect(find.text(_kKeepEditing), findsOneWidget);
        expect(_staticTextContaining(_kServerText), findsWidgets);
        expect(_staticTextContaining(_kMyText), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '"Save mine" calls correctFact with my text and the conflict seq',
      (tester) async {
        final cubit = await _reachConflict(tester);

        await tester.tap(find.text(_kSaveMine));
        await tester.pumpAndSettle();

        expect(cubit.correctCalls, hasLength(2));
        final retry = cubit.correctCalls.last;
        expect(retry.factCardId, _kFactId);
        expect(retry.newText, _kMyText);
        expect(
          retry.baseSeq,
          _kServerSeq,
          reason: 'retry must use factEditConflict.revisionSeq, not the '
              'seq the edit sheet opened with',
        );
        expect(find.text(_kSaveMine), findsNothing);
      },
    );

    testWidgets('"Keep theirs" closes without calling correctFact', (
      tester,
    ) async {
      final cubit = await _reachConflict(tester);

      await tester.tap(find.text(_kKeepTheirs));
      await tester.pumpAndSettle();

      expect(cubit.correctCalls, hasLength(1));
      expect(cubit.clearConflictCalls, greaterThan(0));
      expect(cubit.state.factEditConflict, isNull);
      expect(find.text(_kKeepTheirs), findsNothing);
      expect(_editorField(), findsNothing);
    });

    testWidgets('"Keep editing" returns to the editor with my text intact', (
      tester,
    ) async {
      final cubit = await _reachConflict(tester);
      final l10n = await L10n.delegate.load(const Locale('en'));

      await tester.tap(find.text(_kKeepEditing));
      await tester.pumpAndSettle();

      expect(cubit.correctCalls, hasLength(1));
      expect(find.text(_kKeepEditing), findsNothing);
      expect(find.text(l10n.beaconRoomFactCardEditTitle), findsOneWidget);
      final field = tester.widget<TextField>(_editorField());
      expect(field.controller?.text, _kMyText);
    });
  });
}
