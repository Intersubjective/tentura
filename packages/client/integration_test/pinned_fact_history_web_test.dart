import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web/web.dart' as web;

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_window_class.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_history_sheet.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_fact_card.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

const _original = 'A 1293';
const _edited = 'A 1293 F-mixQ';
const _title = 'История факта';
const _footer = 'Более ранняя история — там, откуда пришёл факт';

Finder get _history => find.byType(FactHistorySheet);
Finder _inHistory(Finder finder) =>
    find.descendant(of: _history, matching: finder);
Finder get _originAction =>
    _inHistory(find.widgetWithText(TextButton, 'Открыть'));

Future<void> _openHistory(WidgetTester tester, String factId, L10n l10n) async {
  final heading = find.text(l10n.beaconFactsSheetTitle).hitTestable();
  await pumpUntilVisible(tester, heading);
  expect(heading, findsOneWidget);
  final pinnedFacts = find.ancestor(
    of: heading,
    matching: find.byWidgetPredicate(
      (widget) => widget is Dialog || widget is BottomSheet,
    ),
  );
  final card = find.descendant(
    of: pinnedFacts,
    matching: find.byWidgetPredicate(
      (widget) => widget is BeaconPinnedFactCard && widget.fact.id == factId,
    ),
  );
  await pumpUntilVisible(tester, card);
  final visibleCard = card.hitTestable().last;
  // Desktop browsers open a read-only card's menu with a secondary click.
  final cardBounds = tester.getRect(visibleCard);
  await tester.tapAt(
    Offset(cardBounds.center.dx, cardBounds.top + 12),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  final historyAction = find.widgetWithText(
    ListTile,
    l10n.beaconRoomFactCardActionEditHistory,
  );
  await pumpUntilVisible(tester, historyAction);
  await tapAndSettle(tester, historyAction);
  await pumpUntilVisible(tester, _inHistory(find.text(_title)));
}

Future<void> _openRequestPinnedFacts(
  WidgetTester tester,
  String beaconId,
) async {
  await goToPath(tester, '$kPathBeaconView/$beaconId');
  await tapAndSettle(tester, find.byKey(TestIds.key(TestIds.beaconTabNow)));
  final pinnedFactsAction = find.byKey(TestIds.key(TestIds.beaconFactsOpen));
  await tapAndSettle(tester, pinnedFactsAction.hitTestable());
}

Future<void> _closeHistory(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await pumpSettleBounded(tester);
  expect(_history, findsNothing);
}

Rect _surface(WidgetTester tester, Size viewport) {
  if (windowClassForWidth(viewport.width) == WindowClass.compact) {
    return tester.getRect(
      find.ancestor(of: _history, matching: find.byType(BottomSheet)),
    );
  }
  expect(
    find.ancestor(of: _history, matching: find.byType(Dialog)),
    findsOneWidget,
  );
  final material = tester
      .element(_history)
      .findAncestorWidgetOfExactType<Material>()!;
  return tester.getRect(find.byWidget(material));
}

bool _fullyVisible(WidgetTester tester, Finder finder, Rect surface) {
  if (finder.evaluate().length != 1) return false;
  final bounds = tester.getRect(finder);
  return bounds.top >= surface.top &&
      bounds.left >= surface.left &&
      bounds.right <= surface.right &&
      bounds.bottom <= surface.bottom;
}

/// Send a browser wheel event through Flutter Web's DOM input listener.
Future<void> _wheel(WidgetTester tester, Offset point, double deltaY) async {
  final binding = tester.binding;
  final previous = binding.shouldPropagateDevicePointerEvents;
  // Live integration tests drop engine-delivered pointer events by default.
  binding.shouldPropagateDevicePointerEvents = true;
  try {
    web.document
        .querySelector('flutter-view')!
        .dispatchEvent(
          web.WheelEvent(
            'wheel',
            web.WheelEventInit(
              bubbles: true,
              cancelable: true,
              composed: true,
              clientX: point.dx.round(),
              clientY: point.dy.round(),
              deltaY: deltaY,
            ),
          ),
        );
    await pumpSettleBounded(tester);
  } finally {
    binding.shouldPropagateDevicePointerEvents = previous;
  }
}

Future<void> _reach(
  WidgetTester tester,
  Size viewport,
  Finder target, {
  required bool wheel,
  PointerDeviceKind dragKind = PointerDeviceKind.touch,
}) async {
  Rect? targetBounds() =>
      target.evaluate().length == 1 ? tester.getRect(target) : null;
  final before = targetBounds();
  for (var attempt = 0; attempt < 12; attempt++) {
    final surface = _surface(tester, viewport);
    if (_fullyVisible(tester, target, surface)) return;
    if (wheel) {
      await _wheel(tester, surface.center, 112);
    } else if (dragKind == PointerDeviceKind.mouse) {
      await tester.dragFrom(
        surface.center,
        const Offset(0, -240),
        kind: PointerDeviceKind.mouse,
      );
      await pumpSettleBounded(tester);
    } else {
      await tester.timedDragFrom(
        surface.center,
        const Offset(0, -112),
        const Duration(milliseconds: 400),
      );
      await pumpSettleBounded(tester);
    }
  }
  final surface = _surface(tester, viewport);
  expect(
    _fullyVisible(tester, target, surface),
    isTrue,
    reason:
        '${wheel ? 'Wheel' : '${dragKind.name} drag'} must reach $target in the $viewport history. '
        'Target bounds before and after scrolling: $before, ${targetBounds()}. '
        'History bounds: $surface.',
  );
}

Future<({String beaconId, String factId})> _createReadOnlyCopy(
  BeaconFactCardRepository repository, {
  required String sourceFactId,
  required String editedText,
}) async {
  final destination = await createPublishedBeacon(
    title: uniqueRequestTitle('Копия факта'),
  );
  final copy = await repository.copy(
    sourceFactCardId: sourceFactId,
    destinationBeaconId: destination,
  );
  expect(
    await repository.correct(
      beaconId: destination,
      factCardId: copy.factCardId,
      newText: editedText,
      baseRevisionSeq: 1,
    ),
    2,
  );
  await GetIt.I<ClosureRepository>().beaconCancel(destination);
  return (beaconId: destination, factId: copy.factCardId);
}

Future<void> _expandLatestRevision(
  WidgetTester tester,
  L10n l10n,
  String text,
) async {
  final expand = _inHistory(find.text(l10n.beaconRoomFactHistoryShowFull));
  await tapAndSettle(tester, expand);
  await pumpUntilVisible(
    tester,
    _inHistory(find.text(text, findRichText: true)),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'read-only copied history reaches the earlier revision and origin even with expanded text',
    (
      tester,
    ) async {
      final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
      // Chrome may enforce a wider outer window on the phone run. The
      // content viewport controls both Flutter layout and browser input.
      expect(
        viewport,
        isIn(const [Size(375, 667), Size(1280, 800), Size(1600, 885)]),
        reason: 'Use a phone, desktop, or default integration runner viewport.',
      );
      expect(
        viewport,
        Size(
          web.window.innerWidth.toDouble(),
          web.window.innerHeight.toDouble(),
        ),
      );

      final l10n = await L10n.delegate.load(const Locale('ru'));
      await launchApp(app.main);
      final fixture = await bootstrapFixture(
        runId: uniqueRunId('pinned-copy-history'),
      );
      await loginAs(tester, fixture.authorEmail);
      await GetIt.I<SettingsCubit>().setLocalePreference(kLocalePreferenceRu);

      final repository = GetIt.I<BeaconFactCardRepository>();
      final source = await createPublishedBeacon(
        title: uniqueRequestTitle('Источник факта'),
      );
      await repository.pin(
        beaconId: source,
        factText: _original,
        visibility: BeaconFactCardVisibilityBits.public,
      );
      final sourceFact = (await repository.list(
        beaconId: source,
      )).singleWhere((fact) => fact.factText == _original);
      final copy = await _createReadOnlyCopy(
        repository,
        sourceFactId: sourceFact.id,
        editedText: _edited,
      );
      final author = sourceFact.pinnedByTitle;
      expect(author, isNotEmpty);
      final authorLine = _inHistory(find.textContaining('$author · '));

      await _openRequestPinnedFacts(tester, copy.beaconId);

      for (final wheel in [true, false]) {
        await _openHistory(tester, copy.factId, l10n);
        expect(MediaQuery.sizeOf(tester.element(_history)), viewport);
        final head = _inHistory(find.text(_edited, findRichText: true));
        await pumpUntilVisible(tester, head);
        expect(authorLine, findsNWidgets(2));
        expect(
          _inHistory(find.text(l10n.beaconRoomFactHistoryRestoreAction)),
          findsNothing,
        );
        final sheet = _surface(tester, viewport);
        expect(sheet.height, greaterThan(viewport.width < 600 ? 135 : 113));
        expect(sheet.height, lessThanOrEqualTo(viewport.height * 0.9));
        for (final target in [
          _inHistory(find.text(_title)),
          authorLine.first,
          head,
        ]) {
          expect(
            _fullyVisible(tester, target, sheet),
            isTrue,
            reason: '$target in $sheet',
          );
        }
        final olderAuthor = authorLine.last;
        await _reach(tester, viewport, olderAuthor, wheel: wheel);
        expect(
          tester.widget<Text>(olderAuthor).data,
          '$author · ${l10n.relativeTimeJustNow}',
        );
        for (final target in [
          _inHistory(find.text(l10n.beaconRoomFactHistoryBroughtHere(author))),
          _inHistory(find.text(_original, findRichText: true)),
          _inHistory(find.text(_footer)),
          _originAction.hitTestable(),
        ]) {
          await _reach(tester, viewport, target, wheel: wheel);
        }
        await _closeHistory(tester);
      }

      final expandedText = [
        _edited,
        for (var line = 1; line <= 48; line++) 'Уточнение $line',
      ].join('\n');
      final expandedCopy = await _createReadOnlyCopy(
        repository,
        sourceFactId: sourceFact.id,
        editedText: expandedText,
      );
      await _openRequestPinnedFacts(tester, expandedCopy.beaconId);

      final dragKind =
          windowClassForWidth(viewport.width) == WindowClass.compact
          ? PointerDeviceKind.touch
          : PointerDeviceKind.mouse;
      final olderBody = _inHistory(find.text(_original, findRichText: true));
      final footer = _inHistory(find.text(_footer));
      for (final wheel in [true, false]) {
        await _openHistory(tester, expandedCopy.factId, l10n);
        await _expandLatestRevision(tester, l10n, expandedText);
        final surface = _surface(tester, viewport);
        expect(surface.height, lessThanOrEqualTo(viewport.height * 0.9));
        expect(
          _fullyVisible(tester, olderBody, surface),
          isFalse,
          reason:
              'The expanded revision takes more room than the history can show',
        );
        for (final target in [olderBody, footer, _originAction.hitTestable()]) {
          await _reach(
            tester,
            viewport,
            target,
            wheel: wheel,
            dragKind: dragKind,
          );
        }
        await _closeHistory(tester);
      }
    },
  );
}
