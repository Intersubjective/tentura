import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web/web.dart' as web;

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_history_sheet.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_fact_card.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

const _original = 'Ключ';
const _edited = 'Ключ у двери';
const _title = 'История факта';
const _footer = 'Более ранняя история — там, откуда пришёл факт';

Finder get _history => find.byType(FactHistorySheet);
Finder get _sheet =>
    find.ancestor(of: _history, matching: find.byType(BottomSheet));
Finder _inHistory(Finder finder) =>
    find.descendant(of: _history, matching: finder);
Finder get _originAction =>
    _inHistory(find.widgetWithText(TextButton, 'Открыть'));

Future<void> _openHistory(WidgetTester tester, String factId, L10n l10n) async {
  final card = find.byWidgetPredicate(
    (widget) => widget is BeaconPinnedFactCard && widget.fact.id == factId,
  );
  await pumpUntilVisible(tester, card);
  final visibleCard = card.hitTestable().last;
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: tester.getCenter(visibleCard));
  final more = find.descendant(
    of: visibleCard,
    matching: find.widgetWithIcon(IconButton, Icons.more_horiz),
  );
  await tapAndSettle(tester, more);
  await mouse.removePointer();
  final historyAction = find.widgetWithText(
    ListTile,
    l10n.beaconRoomFactCardActionEditHistory,
  );
  await pumpUntilVisible(tester, historyAction);
  await tapAndSettle(tester, historyAction);
  await pumpUntilVisible(tester, _inHistory(find.text(_title)));
}

void _expectFullyVisible(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final surface = tester.getRect(_sheet);
  final bounds = tester.getRect(finder);
  expect(bounds.top, greaterThanOrEqualTo(surface.top));
  expect(bounds.bottom, lessThanOrEqualTo(surface.bottom));
  expect(bounds.left, greaterThanOrEqualTo(surface.left));
  expect(bounds.right, lessThanOrEqualTo(surface.right));
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'copied fact history fits short revisions and scrolls longer ones '
    'by mouse wheel',
    (tester) async {
      final l10n = await L10n.delegate.load(const Locale('ru'));
      await launchApp(app.main);
      final fixture = await bootstrapFixture(
        runId: uniqueRunId('fact-history'),
      );
      await loginAs(tester, fixture.authorEmail);
      await GetIt.I<SettingsCubit>().setLocalePreference(kLocalePreferenceRu);

      final repository = GetIt.I<BeaconFactCardRepository>();
      final source = await createPublishedBeacon(
        title: uniqueRequestTitle('Источник факта'),
      );
      final destination = await createPublishedBeacon(
        title: uniqueRequestTitle('Копия факта'),
      );
      await repository.pin(
        beaconId: source,
        factText: _original,
        visibility: BeaconFactCardVisibilityBits.public,
      );
      final sourceFact = (await repository.list(
        beaconId: source,
      )).singleWhere((fact) => fact.factText == _original);
      final copy = await repository.copy(
        sourceFactCardId: sourceFact.id,
        destinationBeaconId: destination,
      );
      var seq = await repository.correct(
        beaconId: destination,
        factCardId: copy.factCardId,
        newText: _edited,
        baseRevisionSeq: 1,
      );
      expect(seq, 2);

      await goToPath(tester, '$kPathBeaconView/$destination');
      await tapAndSettle(tester, find.byKey(TestIds.key(TestIds.beaconTabNow)));
      final facts = find.byKey(TestIds.key(TestIds.beaconFactsOpen));
      await pumpUntilVisible(tester, facts);
      await tapAndSettle(tester, facts);

      await _openHistory(tester, copy.factCardId, l10n);
      final viewport = MediaQuery.sizeOf(tester.element(_history));
      expect(viewport, const Size(375, 667));
      final originalBody = _inHistory(find.text(_original, findRichText: true));
      await pumpUntilVisible(tester, originalBody);
      for (final finder in [
        _inHistory(find.text(_title)),
        _inHistory(find.text(_edited, findRichText: true)),
        originalBody,
        _inHistory(find.text(_footer)),
        _originAction.hitTestable(),
      ]) {
        _expectFullyVisible(tester, finder);
      }
      expect(tester.getSize(_sheet).height, greaterThan(110));
      await tapAndSettle(
        tester,
        _inHistory(find.byTooltip(l10n.buttonClose)),
      );

      const lines = 'Ключ\nДверь\nЗамок\nЭтаж\nПодъезд';
      for (var revision = 3; revision <= 8; revision++) {
        seq = await repository.correct(
          beaconId: destination,
          factCardId: copy.factCardId,
          newText: '$lines\nВерсия $revision',
          baseRevisionSeq: seq,
        );
      }
      expect(seq, 8);

      await _openHistory(tester, copy.factCardId, l10n);
      final firstBody = _inHistory(
        find.textContaining(lines, findRichText: true),
      ).first;
      await pumpUntilVisible(tester, firstBody);
      expect(_originAction.hitTestable(), findsNothing);
      final before = tester.getTopLeft(firstBody).dy;
      await _wheel(tester, tester.getCenter(firstBody), 96);
      expect(tester.getTopLeft(firstBody).dy, lessThan(before));

      for (var attempt = 0; attempt < 10; attempt++) {
        if (_originAction.hitTestable().evaluate().isNotEmpty) break;
        await _wheel(tester, tester.getCenter(_sheet), 220);
      }
      _expectFullyVisible(tester, _inHistory(find.text(_footer)));
      _expectFullyVisible(tester, _originAction.hitTestable());
      expect(
        tester.getSize(_sheet).height,
        lessThanOrEqualTo(viewport.height * 0.9),
      );
    },
  );
}
