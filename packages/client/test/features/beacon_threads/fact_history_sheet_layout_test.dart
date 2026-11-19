import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_fact_history_entry.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_history_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import 'fact_origin_test_support.dart';

const _title = 'История факта';
const _restoreLabel = 'Восстановить эту версию';
const _desktopSurface = Size(1280, 800);
const _footer = 'Более ранняя история — там, откуда пришёл факт';
const _openOrigin = 'Открыть';
final _maxSheetHeight = 0.9 * kPhoneSurface.height;

class _HistoryRepository extends Fake implements BeaconFactCardRepository {
  _HistoryRepository(this.page);

  _HistoryRepository.withEntries(List<BeaconFactTimelineEntry> entries)
    : page = Future.value((entries: entries, nextCursor: null));

  final Future<BeaconFactHistoryPage> page;

  @override
  Future<BeaconFactHistoryPage> revisions({
    required String beaconId,
    required String factCardId,
    String? before,
  }) => page;
}

BeaconFactHistoryEdited _revision(int seq, String author, String body) =>
    BeaconFactHistoryEdited(
      id: 'revision-$seq',
      factCardId: 'Fcopy0000001',
      seq: seq,
      factText: body,
      actorId: 'Ueditor$seq',
      actorTitle: author,
      createdAt: DateTime.utc(2026, 1, seq),
    );

final _shortHistory = [
  _revision(2, 'Анна', 'Ключ у двери'),
  _revision(1, 'Борис', 'Ключ'),
];

final _longHistory = [
  for (var seq = 6; seq > 0; seq--)
    _revision(
      seq,
      'Автор $seq',
      'Дверь\nЗамок\nКлюч\nЭтаж\nДом\nВерсия $seq',
    ),
];

Future<void> _openHistory(
  WidgetTester tester,
  BeaconFactCardRepository repository, {
  Size surface = kPhoneSurface,
  bool canMutate = false,
  bool hasOrigin = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = surface;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      locale: const Locale('ru'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                showFactHistorySheet(
                  context,
                  beaconId: 'Bcopy0000001',
                  factCardId: 'Fcopy0000001',
                  baseRevisionSeq: 6,
                  canMutate: canMutate,
                  originBeaconKind: hasOrigin ? BeaconKind.request.value : null,
                  repository: repository,
                ),
              ),
              child: const Text('Показать историю'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Показать историю'));
  await tester.pumpAndSettle();
}

Finder _author(String name) => find.textContaining('$name · ');

Finder get _originButton => find.widgetWithText(TextButton, _openOrigin);

Rect _sheetRect(WidgetTester tester, {bool desktop = false}) {
  final sheet = find.ancestor(
    of: find.byType(FactHistorySheet),
    matching: desktop ? find.byType(Dialog) : find.byType(BottomSheet),
  );
  expect(sheet, findsOneWidget, reason: 'The history must stay open');
  if (!desktop) return tester.getRect(sheet);
  final dialogContent = tester.element(find.byType(FactHistorySheet));
  final dialogMaterial = dialogContent
      .findAncestorWidgetOfExactType<Material>()!;
  return tester.getRect(find.byWidget(dialogMaterial));
}

bool _inside(Rect widget, Rect sheet) =>
    widget.left >= sheet.left &&
    widget.top >= sheet.top &&
    widget.right <= sheet.right &&
    widget.bottom <= sheet.bottom;

void _expectFullyVisible(WidgetTester tester, Finder finder, Rect sheet) {
  expect(finder, findsOneWidget);
  final rect = tester.getRect(finder);
  expect(
    _inside(rect, sheet),
    isTrue,
    reason: '$finder at $rect inside $sheet',
  );
}

Future<void> _wheel(WidgetTester tester, Offset position, double dy) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: position,
      scrollDelta: Offset(0, dy),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _reachOrigin(
  WidgetTester tester, {
  bool wheel = false,
  bool desktop = false,
}) async {
  for (var attempt = 0; attempt < 8; attempt++) {
    final sheet = _sheetRect(tester, desktop: desktop);
    if (_originButton.hitTestable().evaluate().isNotEmpty &&
        _inside(tester.getRect(_originButton), sheet)) {
      break;
    }
    if (wheel) {
      await _wheel(tester, sheet.center, 220);
    } else {
      await tester.dragFrom(sheet.center, const Offset(0, -220));
      await tester.pumpAndSettle();
    }
  }
  final sheet = _sheetRect(tester, desktop: desktop);
  _expectFullyVisible(tester, find.text(_footer), sheet);
  _expectFullyVisible(tester, _originButton.hitTestable(), sheet);
}

Finder _body(String text) => find.text(text, findRichText: true);

void _expectShortHistory(WidgetTester tester, Rect sheet) {
  expect(sheet.height, greaterThan(110));
  for (final finder in [
    find.text(_title),
    _author('Анна'),
    _body('Ключ у двери'),
    _author('Борис'),
    _body('Ключ'),
    find.text(_footer),
    _originButton.hitTestable(),
  ]) {
    _expectFullyVisible(tester, finder, sheet);
  }
}

Future<void> _dragUntilVisible(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 8; attempt++) {
    final sheet = _sheetRect(tester);
    if (finder.evaluate().length == 1 &&
        _inside(tester.getRect(finder), sheet)) {
      break;
    }
    await tester.dragFrom(sheet.center, const Offset(0, -64));
    await tester.pumpAndSettle();
  }
  _expectFullyVisible(tester, finder, _sheetRect(tester));
}

Future<void> _expectPhoneHistoryScrollsByWheel(WidgetTester tester) async {
  final sheet = _sheetRect(tester);
  final firstAuthor = _author('Автор 6');
  _expectFullyVisible(tester, find.text(_title), sheet);
  _expectFullyVisible(tester, firstAuthor, sheet);
  expect(_originButton.hitTestable(), findsNothing);
  final before = tester.getTopLeft(firstAuthor).dy;

  await _wheel(tester, tester.getCenter(firstAuthor), 90);

  expect(tester.getTopLeft(firstAuthor).dy, lessThan(before));
  await _reachOrigin(tester, wheel: true);
  expect(sheet.height, lessThanOrEqualTo(_maxSheetHeight));
}

void main() {
  testWidgets('two short revisions and the origin fit on a phone', (
    tester,
  ) async {
    await _openHistory(tester, _HistoryRepository.withEntries(_shortHistory));

    _expectShortHistory(tester, _sheetRect(tester));
  });

  testWidgets(
    'the open sheet grows to show both delayed revisions and the origin',
    (
      tester,
    ) async {
      final response = Completer<BeaconFactHistoryPage>();
      await _openHistory(tester, _HistoryRepository(response.future));
      final loadingHeight = _sheetRect(tester).height;
      expect(_author('Анна'), findsNothing);
      expect(_author('Борис'), findsNothing);

      response.complete((entries: _shortHistory, nextCursor: null));
      await tester.pumpAndSettle();

      final loaded = _sheetRect(tester);
      expect(loaded.height, greaterThan(loadingHeight));
      _expectShortHistory(tester, loaded);
    },
  );

  testWidgets(
    'an editor can reach the two older restore actions and the origin',
    (
      tester,
    ) async {
      await _openHistory(
        tester,
        _HistoryRepository.withEntries([
          _revision(3, 'Вера', 'Ключ у двери справа'),
          ..._shortHistory,
        ]),
        canMutate: true,
      );

      _expectFullyVisible(tester, find.text(_title), _sheetRect(tester));
      final actions = find.widgetWithText(TextButton, _restoreLabel);
      expect(actions, findsNWidgets(2));
      expect(
        tester.getBottomLeft(_author('Анна')).dy,
        lessThan(tester.getTopLeft(actions.first).dy),
      );
      expect(
        tester.getBottomLeft(actions.first).dy,
        lessThan(tester.getTopLeft(_author('Борис')).dy),
      );
      expect(
        tester.getBottomLeft(_author('Борис')).dy,
        lessThan(tester.getTopLeft(actions.last).dy),
      );

      for (final finder in [
        _author('Вера'),
        _author('Анна'),
        actions.first.hitTestable(),
        _author('Борис'),
        actions.last.hitTestable(),
        find.text(_footer),
        _originButton.hitTestable(),
      ]) {
        await _dragUntilVisible(tester, finder);
      }
    },
  );

  testWidgets(
    'a single revision without an origin fits in a short phone sheet',
    (
      tester,
    ) async {
      await _openHistory(
        tester,
        _HistoryRepository.withEntries([_shortHistory.last]),
        hasOrigin: false,
      );

      final sheet = _sheetRect(tester);
      expect(sheet.height, lessThan(_maxSheetHeight));
      _expectFullyVisible(tester, find.text(_title), sheet);
      _expectFullyVisible(tester, _author('Борис'), sheet);
      _expectFullyVisible(tester, _body('Ключ'), sheet);
      expect(find.text(_footer), findsNothing);
      expect(_originButton, findsNothing);
    },
  );

  testWidgets('a bounded desktop dialog reaches the origin by drag and wheel', (
    tester,
  ) async {
    await _openHistory(
      tester,
      _HistoryRepository.withEntries(_longHistory),
      surface: _desktopSurface,
    );

    final dialog = _sheetRect(tester, desktop: true);
    expect(dialog.height, lessThanOrEqualTo(0.9 * _desktopSurface.height));
    _expectFullyVisible(tester, find.text(_title), dialog);
    expect(_originButton.hitTestable(), findsNothing);
    await _reachOrigin(tester, desktop: true);

    final firstAuthor = _author('Автор 6');
    for (var attempt = 0; attempt < 8; attempt++) {
      await _wheel(tester, dialog.center, -220);
      if (firstAuthor.hitTestable().evaluate().isNotEmpty) break;
    }
    _expectFullyVisible(tester, firstAuthor, dialog);
    expect(_originButton.hitTestable(), findsNothing);
    await _reachOrigin(tester, desktop: true, wheel: true);
  });

  testWidgets('an upward drag reaches the origin in a bounded phone sheet', (
    tester,
  ) async {
    await _openHistory(tester, _HistoryRepository.withEntries(_longHistory));

    final sheet = _sheetRect(tester);
    final firstAuthor = _author('Автор 6');
    _expectFullyVisible(tester, find.text(_title), sheet);
    _expectFullyVisible(tester, firstAuthor, sheet);
    expect(_originButton.hitTestable(), findsNothing);
    final before = tester.getTopLeft(firstAuthor).dy;

    await tester.drag(firstAuthor, const Offset(0, -110));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(firstAuthor).dy, lessThan(before));
    await _reachOrigin(tester);
    expect(sheet.height, lessThanOrEqualTo(_maxSheetHeight));
  });

  testWidgets('the wheel reaches the origin in a bounded phone sheet', (
    tester,
  ) async {
    await _openHistory(tester, _HistoryRepository.withEntries(_longHistory));

    await _expectPhoneHistoryScrollsByWheel(tester);
  });

  testWidgets(
    'copied history loaded over GraphQL scrolls by wheel in a bounded phone sheet',
    (
      tester,
    ) async {
      final wire = (await tester.runAsync(
        () => OriginWire.start(
          origin: const {},
          revisions: [
            for (final entry in _longHistory)
              {
                ...wireRevisionRow(entry.seq),
                'kind': entry.seq == 1
                    ? BeaconFactCardRevisionKindBits.copied
                    : BeaconFactCardRevisionKindBits.edited,
                'actorTitle': entry.actorTitle,
                'factText': entry.factText,
              },
          ],
        ),
      ))!;
      addTearDown(wire.close);

      await _openHistory(tester, wire.repository);
      final firstAuthor = _author('Автор 6');
      for (var attempt = 0; attempt < 10; attempt++) {
        if (firstAuthor.evaluate().isNotEmpty) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
      }

      expect(wire.sent, ['BeaconFactCardRevisions']);
      await _expectPhoneHistoryScrollsByWheel(tester);
    },
  );
}
