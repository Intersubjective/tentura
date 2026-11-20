import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_fact_history_entry.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_actions_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_history_sheet.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_fact_card.dart';
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

Future<void> _openPinnedFact(
  BuildContext context,
  VoidCallback openHistory,
) {
  final fact = copiedFact(factText: _editedBody);
  return showTenturaAdaptiveSheet<void>(
    context: context,
    builder: (sheetContext) => BeaconPinnedFactCard(
      fact: fact,
      l10n: L10n.of(sheetContext)!,
      onManage: () => unawaited(
        showFactActionsHostSheet(
          context,
          fact: fact,
          canMutate: false,
          onCorrect:
              ({
                required factCardId,
                required newText,
                attachmentsJson,
              }) async {},
          onRemove: ({required factCardId}) async {},
          onSetVisibility:
              ({required factCardId, required visibility}) async {},
          onEditHistory: (_) => openHistory(),
        ),
      ),
    ),
  );
}

Future<void> _openHistory(
  WidgetTester tester,
  BeaconFactCardRepository repository, {
  Size surface = kPhoneSurface,
  bool canMutate = false,
  bool hasOrigin = true,
  int baseRevisionSeq = 6,
  bool fromPinnedFacts = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = surface;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final page = TenturaResponsiveScope(
    child: Scaffold(
      body: Builder(
        builder: (context) {
          void openHistory() => unawaited(
            showFactHistorySheet(
              context,
              beaconId: 'Bcopy0000001',
              factCardId: 'Fcopy0000001',
              baseRevisionSeq: baseRevisionSeq,
              canMutate: canMutate,
              originBeaconKind: hasOrigin ? BeaconKind.request.value : null,
              repository: repository,
            ),
          );

          return TextButton(
            onPressed: fromPinnedFacts
                ? () => unawaited(_openPinnedFact(context, openHistory))
                : openHistory,
            child: const Text('Показать историю'),
          );
        },
      ),
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: fromPinnedFacts
          ? TenturaTheme.light().copyWith(platform: TargetPlatform.linux)
          : TenturaTheme.light(),
      locale: const Locale('ru'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: fromPinnedFacts
          ? Navigator(
              onGenerateRoute: (_) =>
                  MaterialPageRoute<void>(builder: (_) => page),
            )
          : page,
    ),
  );
  await tester.tap(find.text('Показать историю'));
  await tester.pumpAndSettle();
  if (fromPinnedFacts) {
    final card = find.byType(BeaconPinnedFactCard);
    final cardRect = tester.getRect(card);
    await tester.tapAt(
      Offset(cardRect.center.dx, cardRect.top + 12),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('История изменений'));
    await tester.pumpAndSettle();
  }
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
  PointerDeviceKind dragKind = PointerDeviceKind.touch,
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
      await tester.dragFrom(
        sheet.center,
        const Offset(0, -220),
        kind: dragKind,
      );
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

const _copyAuthor = 'QA-FX Anna 1104';
const _sourceBody = 'A 1293';
const _editedBody = 'A 1293 F-mixQ';
const _copiedLabel = '$_copyAuthor принёс(ла) это сюда';

List<BeaconFactHistoryEntry> _copiedHistory({String olderBody = _sourceBody}) {
  final now = DateTime.now();
  return [
    BeaconFactHistoryEdited(
      id: 'revision-2',
      factCardId: 'Fcopy0000001',
      seq: 2,
      factText: _editedBody,
      actorId: 'Ueditor',
      actorTitle: _copyAuthor,
      createdAt: now.subtract(const Duration(seconds: 10)),
    ),
    BeaconFactHistoryCopied(
      id: 'revision-1',
      factCardId: 'Fcopy0000001',
      seq: 1,
      factText: olderBody,
      actorId: 'Ueditor',
      actorTitle: _copyAuthor,
      createdAt: now.subtract(const Duration(hours: 2, minutes: 30)),
    ),
  ];
}

typedef _HistorySurface = ({Size size, bool desktop, double clippedHeight});

Future<void> _openCopyHistory(
  WidgetTester tester,
  BeaconFactCardRepository repository,
  _HistorySurface surface,
) => _openHistory(
  tester,
  repository,
  surface: surface.size,
  baseRevisionSeq: 2,
);

Future<void> _reachCopyContent(
  WidgetTester tester,
  _HistorySurface surface,
  List<Finder> targets, {
  bool wheel = false,
}) async {
  for (final target in targets) {
    for (var attempt = 0; attempt < 12; attempt++) {
      final sheet = _sheetRect(tester, desktop: surface.desktop);
      if (target.evaluate().length == 1 &&
          _inside(tester.getRect(target), sheet)) {
        break;
      }
      if (wheel) {
        await _wheel(tester, sheet.center, 48);
      } else {
        await tester.timedDragFrom(
          sheet.center,
          const Offset(0, -56),
          const Duration(milliseconds: 400),
        );
        await tester.pumpAndSettle();
      }
    }
    _expectFullyVisible(
      tester,
      target,
      _sheetRect(tester, desktop: surface.desktop),
    );
  }
}

void _expectCopyHead(
  WidgetTester tester,
  _HistorySurface surface, {
  required Finder author,
}) {
  final sheet = _sheetRect(tester, desktop: surface.desktop);
  expect(find.text(_restoreLabel), findsNothing);
  for (final finder in [find.text(_title), author, _body(_editedBody)]) {
    _expectFullyVisible(tester, finder, sheet);
  }
  expect(sheet.height, greaterThan(surface.clippedHeight));
  expect(sheet.height, lessThanOrEqualTo(surface.size.height * 0.9));
}

List<Finder> _originContent() => [
  find.text(_footer),
  _originButton.hitTestable(),
];

void _testReadOnlyCopiedHistory() {
  const phone = (size: kPhoneSurface, desktop: false, clippedHeight: 135.0);
  const desktop = (size: _desktopSurface, desktop: true, clippedHeight: 113.0);

  group('read-only history of a copied fact', () {
    for (final (label, surface) in [('phone', phone), ('desktop', desktop)]) {
      testWidgets('$label copied history from pinned facts uses one viewport', (
        tester,
      ) async {
        await _openHistory(
          tester,
          _HistoryRepository.withEntries(_copiedHistory()),
          surface: surface.size,
          baseRevisionSeq: 2,
          fromPinnedFacts: true,
        );
        final older = _body(_sourceBody);
        final before = _sheetRect(tester, desktop: surface.desktop);
        await _wheel(tester, before.center, 112);
        final after = _sheetRect(tester, desktop: surface.desktop);
        _expectFullyVisible(tester, older, after);
        _expectFullyVisible(tester, _originButton.hitTestable(), after);
        expect(after.height, greaterThan(surface.clippedHeight));
        expect(after.height, lessThanOrEqualTo(surface.size.height * 0.9));
        expect(
          find.descendant(
            of: find.byType(FactHistorySheet),
            matching: find.byType(Scrollable),
          ),
          findsOneWidget,
        );
      });

      for (final wheel in [false, true]) {
        final gesture = wheel ? 'wheel' : 'drag';
        testWidgets('$label $gesture reaches the earlier revision and origin', (
          tester,
        ) async {
          await _openCopyHistory(
            tester,
            _HistoryRepository.withEntries(_copiedHistory()),
            surface,
          );
          final authors = _author(_copyAuthor);
          expect(authors, findsNWidgets(2));
          _expectCopyHead(tester, surface, author: authors.first);
          await _reachCopyContent(
            tester,
            surface,
            [
              authors.last,
              find.text('$_copyAuthor · 2 ч назад'),
              _body(_sourceBody),
              ..._originContent(),
            ],
            wheel: wheel,
          );
        });
      }

      for (final wheel in [false, true]) {
        final gesture = wheel ? 'wheel' : 'drag';
        testWidgets(
          '$label history grows on load and reaches the earlier revision and origin by $gesture',
          (tester) async {
            final response = Completer<BeaconFactHistoryPage>();
            await _openCopyHistory(
              tester,
              _HistoryRepository(response.future),
              surface,
            );
            final loading = _sheetRect(tester, desktop: surface.desktop);
            final authors = _author(_copyAuthor);
            expect(authors, findsNothing);
            expect(_body(_sourceBody), findsNothing);

            response.complete((entries: _copiedHistory(), nextCursor: null));
            await tester.pumpAndSettle();

            final loaded = _sheetRect(tester, desktop: surface.desktop);
            expect(loaded.height, greaterThan(loading.height));
            expect(authors, findsNWidgets(2));
            _expectCopyHead(tester, surface, author: authors.first);
            await _reachCopyContent(
              tester,
              surface,
              [
                authors.last,
                find.text('$_copyAuthor · 2 ч назад'),
                _body(_sourceBody),
                ..._originContent(),
              ],
              wheel: wheel,
            );
          },
        );
      }

      for (final variant in [
        'empty copied revision',
        'visibility event',
        'imported revision',
      ]) {
        testWidgets('$label history reaches the $variant and origin', (
          tester,
        ) async {
          final [head, copy] = _copiedHistory(olderBody: '');
          final (
            BeaconFactTimelineEntry older,
            String label,
          ) = switch (variant) {
            'empty copied revision' => (copy, _copiedLabel),
            'visibility event' => (
              BeaconFactHistoryEvent(
                id: 'visibility',
                actorId: copy.actorId,
                actorTitle: copy.actorTitle,
                createdAt: copy.createdAt,
                type: BeaconActivityEventTypeBits.factVisibilityChanged,
                visibilityTo: BeaconFactCardVisibilityBits.public,
              ),
              '$_copyAuthor изменил(а) видимость на «Публичный»',
            ),
            _ => (
              BeaconFactHistoryImported(
                id: copy.id,
                factCardId: copy.factCardId,
                seq: copy.seq,
                factText: _sourceBody,
                actorId: copy.actorId,
                actorTitle: copy.actorTitle,
                createdAt: copy.createdAt,
              ),
              'Более ранняя история не сохранилась',
            ),
          };

          await _openCopyHistory(
            tester,
            _HistoryRepository.withEntries([head, older]),
            surface,
          );
          final sheet = _sheetRect(tester, desktop: surface.desktop);
          final firstBody = _body(_editedBody);
          for (final finder in [
            find.text(_title),
            _author(_copyAuthor).first,
            firstBody,
          ]) {
            _expectFullyVisible(tester, finder, sheet);
          }
          expect(sheet.bottom, greaterThan(tester.getRect(firstBody).bottom));
          expect(sheet.height, lessThanOrEqualTo(surface.size.height * 0.9));
          expect(find.text(_restoreLabel), findsNothing);
          await _reachCopyContent(
            tester,
            surface,
            [
              find.text(label),
              if (older is BeaconFactHistoryImported) _body(_sourceBody),
              ..._originContent(),
            ],
          );
        });
      }
    }

    testWidgets('phone wheel reaches the copied revision loaded over GraphQL', (
      tester,
    ) async {
      final wire = (await tester.runAsync(
        () => OriginWire.start(
          origin: const {},
          revisions: [
            for (final entry in _copiedHistory())
              {
                ...wireRevisionRow(entry.seq),
                'kind': entry.kind,
                'actorId': entry.actorId,
                'actorTitle': entry.actorTitle,
                'factText': entry.factText,
                'createdAt': entry.createdAt.toUtc().toIso8601String(),
              },
          ],
        ),
      ))!;
      addTearDown(wire.close);

      await _openCopyHistory(tester, wire.repository, phone);
      for (var attempt = 0; attempt < 20; attempt++) {
        if (_author(_copyAuthor).evaluate().length == 2) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
      }

      expect(wire.sent, ['BeaconFactCardRevisions']);
      final authors = _author(_copyAuthor);
      expect(authors, findsNWidgets(2));
      _expectCopyHead(tester, phone, author: authors.first);
      await _reachCopyContent(
        tester,
        phone,
        [
          authors.last,
          find.text('$_copyAuthor · 2 ч назад'),
          find.text(_copiedLabel),
          _body(_sourceBody),
          ..._originContent(),
        ],
        wheel: true,
      );
    });
  });
}

void main() {
  _testReadOnlyCopiedHistory();

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
    await _reachOrigin(
      tester,
      desktop: true,
      dragKind: PointerDeviceKind.mouse,
    );

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
