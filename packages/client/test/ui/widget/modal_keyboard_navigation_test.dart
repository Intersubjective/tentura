import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_history_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_attachment_widgets.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_fact_card.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_facts_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/tentura_fullscreen_image_viewer.dart';

import '../../features/beacon_view/beacon_view_case_test_support.dart';
import '../../features/beacon_view/beacon_view_initial_load_test.dart';
import '../../support/remote_wire_harness.dart';
import '../effect/fake_ui_effect_port.dart';

// These tests exercise Flutter key dispatch. Desktop browser focus admission
// still needs the web integration runner; widget dispatch cannot prove it.
class _Page {
  late BuildContext context;
  bool completed = false;

  void watch(Future<void> closed) {
    unawaited(closed.then((_) => completed = true));
  }
}

Future<_Page> _page(
  WidgetTester tester, {
  double width = 1280,
  bool nestedNavigator = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 667);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final navigator = GlobalKey<NavigatorState>();
  final page = _Page();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: TenturaTheme.light().copyWith(platform: TargetPlatform.windows),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('ru'),
      home: const Scaffold(body: Text('Home')),
    ),
  );
  final workspace = TenturaResponsiveScope(
    child: Builder(
      builder: (context) {
        page.context = context;
        return const Scaffold(body: Text('Workspace'));
      },
    ),
  );
  navigator.currentState!.push<void>(
    MaterialPageRoute<void>(
      builder: (_) => nestedNavigator
          ? Navigator(
              onGenerateRoute: (_) =>
                  MaterialPageRoute<void>(builder: (_) => workspace),
            )
          : workspace,
    ),
  );
  await tester.pumpAndSettle();
  return page;
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void _expectButtonFocus(Finder button) {
  final focused = FocusManager.instance.primaryFocus!.context!;
  expect(ModalRoute.of(focused)!.isCurrent, isTrue);
  expect(
    find.ancestor(of: find.byWidget(focused.widget), matching: button),
    findsOneWidget,
  );
}

Future<void> _tabToButton(WidgetTester tester, Finder button) async {
  // Pointer clicks do not focus IconButtons on every Flutter test platform.
  // Reach the control through public keyboard traversal, as a user can.
  for (var i = 0; i < 4; i++) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null &&
        find
            .ancestor(of: find.byWidget(focused.widget), matching: button)
            .evaluate()
            .isNotEmpty) {
      _expectButtonFocus(button);
      return;
    }
    await _key(tester, LogicalKeyboardKey.tab);
  }
  _expectButtonFocus(button);
}

Future<_Page> _album(WidgetTester tester, {int initialIndex = 0}) async {
  final page = await _page(tester);
  page.watch(
    openRoomAttachmentImageAlbum(page.context, [
      for (var i = 0; i < 3; i++)
        RoomMessageAttachment(
          id: 'attachment-$i',
          kind: BeaconRoomMessageAttachmentKind.image,
          position: i,
          mime: 'image/png',
          sizeBytes: 100,
          imageId: 'image-$i',
          imageAuthorId: 'author',
        ),
    ], initialIndex),
  );
  await tester.pumpAndSettle();
  expect(find.byType(RoomAttachmentFullscreenGallery), findsOneWidget);
  expect(find.text('${initialIndex + 1} / 3'), findsOneWidget);
  expect(page.completed, isFalse);
  return page;
}

Future<_Page> _viewer(WidgetTester tester, {int count = 3}) async {
  final page = await _page(tester);
  page.watch(
    TenturaFullscreenImageViewer.show(
      page.context,
      images: [
        for (var i = 0; i < count; i++)
          TenturaGalleryImage(url: 'https://example.com/photo-$i.png'),
      ],
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(TenturaFullscreenImageViewer), findsOneWidget);
  expect(page.completed, isFalse);
  return page;
}

void _closed(_Page page, Finder content) {
  expect(content, findsNothing);
  expect(find.text('Workspace'), findsOneWidget);
  expect(find.text('Home'), findsNothing);
  expect(page.completed, isTrue);
}

final _old = DateTime.utc(2026);
final _new = DateTime.utc(2026, 1, 2);

// This fixture records the passing pre-change run, its exact command/output,
// and production-source hashes. Compare with those captured observations;
// do not infer dismissal policy from the current scaffold configuration.
final _focusedEditorEscapeBaselines =
    ((jsonDecode(
                  File(
                    'test/ui/widget/fixtures/focused_editor_escape_baseline.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>)['observations']
            as List<dynamic>)
        .map((raw) {
          final observation = raw as Map<String, dynamic>;
          return (
            showSnackBars: observation['showSnackBars'] as bool,
            closesOnEscape: observation['closesOnEscape'] as bool,
            textAfterEscape: observation['textAfterEscape'] as String,
          );
        })
        .toList();

Future<BeaconViewCubit> _factsCubit({
  FakeBeaconViewFactCardRepository? factCardsRepo,
}) async {
  BeaconFactCard fact(String id, DateTime at) => BeaconFactCard(
    id: id,
    beaconId: 'Bfacts01',
    factText: 'Закреплённый факт',
    pinnedBy: 'author',
    visibility: BeaconFactCardVisibilityBits.public,
    status: BeaconFactCardStatusBits.active,
    createdAt: at,
  );
  final case_ =
      buildTestBeaconViewCase(
        beaconRepo: TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => Beacon(
            id: 'Bfacts01',
            title: 'Request',
            createdAt: _old,
            updatedAt: _new,
            author: const Profile(id: 'author'),
          ),
        factCardsRepo:
            factCardsRepo ??
            FakeBeaconViewFactCardRepository(
              cards: [fact('active', _new)],
            ),
      )..baselinePinnedFactsIfNeeded(
        beaconId: 'Bfacts01',
        userId: 'reader',
        facts: [fact('baseline', _old)],
      );
  final cubit = BeaconViewCubit(
    id: 'Bfacts01',
    myProfile: const Profile(id: 'reader'),
    beaconViewCase: case_,
    effects: FakeUiEffectPort(),
  );
  await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);
  return cubit;
}

class _WireFactList extends FakeBeaconViewFactCardRepository {
  _WireFactList(this.repository);

  final BeaconFactCardRepository repository;

  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) =>
      repository.list(beaconId: beaconId);
}

const _factText = 'Закреплённый факт';

Future<void> _withPinnedFacts(
  WidgetTester tester,
  double width,
  Future<void> Function(_Page page, L10n l10n) check,
) => withRemoteWire(
  {
    'BeaconFactCardList': {
      '__typename': 'query_root',
      'BeaconFactCardList': [
        {
          '__typename': 'v2_BeaconFactCardRow',
          'id': 'Factive00001',
          'beaconId': 'Bfacts01',
          'factText': _factText,
          'visibility': BeaconFactCardVisibilityBits.public,
          'pinnedBy': 'author',
          'pinnedByTitle': 'Автор',
          'sourceMessageId': null,
          'status': BeaconFactCardStatusBits.active,
          'createdAt': _new.toIso8601String(),
          'updatedAt': null,
          'attachmentsJson': '[]',
          'revisionSeq': 1,
          'lastEditedBy': null,
          'lastEditedByTitle': null,
          'lastEditedAt': null,
          'otherEditorCount': 0,
          'historyTruncated': false,
          'savedByMe': false,
        },
      ],
    },
    'BeaconFactCardRevisions': {
      '__typename': 'query_root',
      'BeaconFactCardRevisions': {
        '__typename': 'v2_BeaconFactCardRevisionsPage',
        'entries': [
          {
            '__typename': 'v2_BeaconFactHistoryEntryRow',
            'entry': 'revision',
            'entryKey': 'r0000000001',
            'id': null,
            'seq': 1,
            'kind': BeaconFactCardRevisionKindBits.created,
            'type': null,
            'factText': _factText,
            'restoredFromSeq': null,
            'visibilityFrom': null,
            'visibilityTo': null,
            'actorId': 'author',
            'actorTitle': 'Автор',
            'createdAt': _new.toIso8601String(),
          },
        ],
        'nextCursor': null,
      },
    },
  },
  [],
  (remote) async {
    final repository = BeaconFactCardRepository(remote);
    GetIt.I.registerSingleton<BeaconFactCardRepository>(repository);
    addTearDown(() => GetIt.I.unregister<BeaconFactCardRepository>());
    final cubit = (await tester.runAsync(
      () => _factsCubit(factCardsRepo: _WireFactList(repository)),
    ))!;
    addTearDown(cubit.close);
    // The Request workspace has a nested navigator. Its fact menus open on
    // the root navigator above the pinned facts sheet.
    final page = await _page(tester, width: width, nestedNavigator: true);
    final l10n = L10n.of(page.context)!;
    page.watch(showBeaconPinnedFactsSheet(page.context, cubit: cubit));
    await tester.pumpAndSettle();
    expect(find.text(l10n.beaconFactsSheetTitle), findsOneWidget);
    expect(find.text(_factText), findsOneWidget);
    expect(page.completed, isFalse);

    await tester.tapAt(
      tester.getTopLeft(find.byType(BeaconPinnedFactCard)) +
          const Offset(12, 12),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.beaconRoomFactManageSheetTitle), findsOneWidget);
    await check(page, l10n);
  },
);

Future<(_Page, _Page)> _stackSheets(
  WidgetTester tester, {
  required double width,
  bool bottomSnackBars = false,
  bool topSnackBars = false,
  bool topDismissible = true,
  WidgetBuilder? topBuilder,
}) async {
  // Use the same navigator arrangement as the Request's fact sheets.
  final bottom = await _page(tester, width: width, nestedNavigator: true);
  bottom.watch(
    showTenturaAdaptiveSheet<void>(
      context: bottom.context,
      showSnackBars: bottomSnackBars,
      builder: (_) => const Text('Bottom sheet'),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Bottom sheet'), findsOneWidget);

  final top = await _openTopSheet(
    tester,
    showSnackBars: topSnackBars,
    isDismissible: topDismissible,
    builder: topBuilder,
  );
  expect(bottom.completed, isFalse);
  return (bottom, top);
}

Future<_Page> _openTopSheet(
  WidgetTester tester, {
  bool showSnackBars = false,
  bool isDismissible = true,
  WidgetBuilder? builder,
}) async {
  final bottomContent = find.text('Bottom sheet');
  final top = _Page()
    ..watch(
      showTenturaAdaptiveSheet<void>(
        context: tester.element(bottomContent),
        showSnackBars: showSnackBars,
        useRootNavigator: true,
        isDismissible: isDismissible,
        builder: builder ?? (_) => const Text('Top sheet'),
      ),
    );
  await tester.pumpAndSettle();
  expect(bottomContent, findsOneWidget);
  expect(top.completed, isFalse);
  return top;
}

void _expectOnlyTopClosed(
  _Page bottom,
  _Page top,
  Finder topContent, {
  required double width,
}) {
  expect(topContent, findsNothing);
  expect(find.text('Bottom sheet'), findsOneWidget);
  expect(find.byType(Dialog), width == 1280 ? findsOneWidget : findsNothing);
  expect(top.completed, isTrue);
  expect(bottom.completed, isFalse);
}

_Page _watchSheetDismissal(WidgetTester tester, Finder content) {
  // The UI callbacks launch sheets without returning their futures to the
  // caller. Watch the route's pop future, which the adaptive sheet awaits.
  final route = ModalRoute.of(tester.element(content))!;
  final sheet = _Page()..watch(route.popped);
  expect(sheet.completed, isFalse);
  return sheet;
}

Future<void> _tapSheetBarrier(WidgetTester tester) async {
  await tester.tapAt(const Offset(10, 10), kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void _stackedSheetTests() {
  group('Stacked sheets dismiss one layer at a time', () {
    for (final width in [375.0, 1280.0]) {
      for (final bottomSnackBars in [false, true]) {
        for (final topSnackBars in [false, true]) {
          testWidgets(
            'Escape leaves the lower sheet open at width $width '
            '(lower snackbar $bottomSnackBars, upper snackbar $topSnackBars)',
            (tester) async {
              final (bottom, top) = await _stackSheets(
                tester,
                width: width,
                bottomSnackBars: bottomSnackBars,
                topSnackBars: topSnackBars,
              );
              final topContent = find.text('Top sheet');
              expect(topContent, findsOneWidget);
              await _key(tester, LogicalKeyboardKey.escape);
              _expectOnlyTopClosed(bottom, top, topContent, width: width);
            },
          );
        }
      }

      testWidgets('A second Escape returns to Workspace at width $width', (
        tester,
      ) async {
        final (bottom, top) = await _stackSheets(tester, width: width);
        final topContent = find.text('Top sheet');
        expect(topContent, findsOneWidget);

        await _key(tester, LogicalKeyboardKey.escape);
        _expectOnlyTopClosed(bottom, top, topContent, width: width);
        await _key(tester, LogicalKeyboardKey.escape);
        _closed(bottom, find.text('Bottom sheet'));
        expect(top.completed, isTrue);
      });

      testWidgets(
        'Escape and a barrier click dismiss the same layer at width $width',
        (
          tester,
        ) async {
          final topContent = find.text('Top sheet');
          final (bottom, clickedTop) = await _stackSheets(tester, width: width);
          expect(topContent, findsOneWidget);
          await _tapSheetBarrier(tester);
          _expectOnlyTopClosed(bottom, clickedTop, topContent, width: width);

          final escapedTop = await _openTopSheet(tester);
          expect(topContent, findsOneWidget);
          expect(bottom.completed, isFalse);
          await _key(tester, LogicalKeyboardKey.escape);
          _expectOnlyTopClosed(bottom, escapedTop, topContent, width: width);
        },
      );

      testWidgets(
        'A locked upper sheet blocks barrier clicks and Escape at width $width',
        (
          tester,
        ) async {
          final (bottom, top) = await _stackSheets(
            tester,
            width: width,
            topDismissible: false,
          );
          void expectBothOpen() {
            expect(find.text('Top sheet'), findsOneWidget);
            expect(find.text('Bottom sheet'), findsOneWidget);
            expect(top.completed, isFalse);
            expect(bottom.completed, isFalse);
          }

          expectBothOpen();
          await _tapSheetBarrier(tester);
          expectBothOpen();
          await _key(tester, LogicalKeyboardKey.escape);
          expectBothOpen();
        },
      );

      testWidgets(
        'Escape from a tab-focused action leaves the lower sheet open at width $width',
        (
          tester,
        ) async {
          final (bottom, top) = await _stackSheets(
            tester,
            width: width,
            topSnackBars: true,
            topBuilder: (_) =>
                TextButton(onPressed: () {}, child: const Text('Top action')),
          );
          final action = find.widgetWithText(TextButton, 'Top action');
          expect(action, findsOneWidget);
          await _tabToButton(tester, action);
          await _key(tester, LogicalKeyboardKey.escape);
          _expectOnlyTopClosed(bottom, top, action, width: width);
        },
      );

      testWidgets(
        'Escape from a focused editor leaves the lower sheet open at width $width',
        (
          tester,
        ) async {
          final (bottom, top) = await _stackSheets(
            tester,
            width: width,
            topSnackBars: true,
            topBuilder: (_) => const TextField(),
          );
          final field = find.byType(TextField);
          await tester.enterText(field, 'Текст остаётся');
          await tester.pump();
          final editor = tester.widget<EditableText>(find.byType(EditableText));
          expect(editor.focusNode.hasPrimaryFocus, isTrue);
          expect(ModalRoute.of(editor.focusNode.context!)!.isCurrent, isTrue);
          expect(find.text('Текст остаётся'), findsOneWidget);
          await _key(tester, LogicalKeyboardKey.escape);
          _expectOnlyTopClosed(bottom, top, field, width: width);
        },
      );

      testWidgets(
        'Escape from fact management leaves pinned facts open at width $width',
        (
          tester,
        ) => _withPinnedFacts(tester, width, (page, l10n) async {
          final actionsTitle = find.text(l10n.beaconRoomFactManageSheetTitle);
          final actions = _watchSheetDismissal(tester, actionsTitle);

          await _key(tester, LogicalKeyboardKey.escape);
          expect(actionsTitle, findsNothing);
          expect(actions.completed, isTrue);
          expect(find.text(l10n.beaconFactsSheetTitle), findsOneWidget);
          expect(find.text(_factText), findsOneWidget);
          expect(page.completed, isFalse);
        }),
      );

      testWidgets(
        'Escape from fact history leaves pinned facts open at width $width',
        (
          tester,
        ) => _withPinnedFacts(tester, width, (page, l10n) async {
          final actionsTitle = find.text(l10n.beaconRoomFactManageSheetTitle);
          final historyAction = find.text(
            l10n.beaconRoomFactCardActionEditHistory,
          );
          final pinnedTitle = find.text(l10n.beaconFactsSheetTitle);
          final pinnedFact = find.descendant(
            of: find.byType(BeaconPinnedFactCard),
            matching: find.text(_factText),
          );
          expect(actionsTitle, findsOneWidget);
          await tester.ensureVisible(historyAction);
          await tester.tap(historyAction);
          await tester.pumpAndSettle();
          final historyTitle = find.text(l10n.beaconRoomFactHistorySheetTitle);
          final historyFact = find.descendant(
            of: find.byType(FactHistorySheet),
            matching: find.text(_factText),
          );
          expect(historyTitle, findsOneWidget);
          expect(historyFact, findsOneWidget);
          final history = _watchSheetDismissal(tester, historyTitle);
          // Opening history replaces the actions sheet. Pinned facts is the
          // sheet directly beneath history when Escape is pressed.
          expect(actionsTitle, findsNothing);
          expect(pinnedTitle, findsOneWidget);
          expect(pinnedFact, findsOneWidget);
          expect(page.completed, isFalse);

          await _key(tester, LogicalKeyboardKey.escape);
          expect(historyTitle, findsNothing);
          expect(historyFact, findsNothing);
          expect(history.completed, isTrue);
          expect(pinnedTitle, findsOneWidget);
          expect(pinnedFact, findsOneWidget);
          expect(page.completed, isFalse);
        }),
      );
    }
  });
}

void main() {
  _stackedSheetTests();

  group('Chat photo album keyboard navigation', () {
    testWidgets(
      'Escape dismisses an untouched album and completes its future',
      (tester) async {
        final page = await _album(tester);
        await _key(tester, LogicalKeyboardKey.escape);
        _closed(page, find.byType(RoomAttachmentFullscreenGallery));
      },
    );

    testWidgets('Right advances through photos and stops at the last photo', (
      tester,
    ) async {
      await _album(tester);
      for (final title in ['2 / 3', '3 / 3', '3 / 3']) {
        await _key(tester, LogicalKeyboardKey.arrowRight);
        expect(find.text(title), findsOneWidget);
      }
    });

    testWidgets('Left goes back through photos and stops at the first photo', (
      tester,
    ) async {
      await _album(tester, initialIndex: 2);
      for (final title in ['2 / 3', '1 / 3', '1 / 3']) {
        await _key(tester, LogicalKeyboardKey.arrowLeft);
        expect(find.text(title), findsOneWidget);
      }
    });

    testWidgets('Left still changes photos after clicking the next control', (
      tester,
    ) async {
      await _album(tester);
      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.chevron_right),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      await _tabToButton(
        tester,
        find.widgetWithIcon(IconButton, Icons.chevron_right),
      );
      await _key(tester, LogicalKeyboardKey.arrowLeft);
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('Escape still dismisses after clicking the next control', (
      tester,
    ) async {
      final page = await _album(tester);
      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.chevron_right),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      await _tabToButton(
        tester,
        find.widgetWithIcon(IconButton, Icons.chevron_right),
      );
      await _key(tester, LogicalKeyboardKey.escape);
      _closed(page, find.byType(RoomAttachmentFullscreenGallery));
    });
  });

  group('Shared photo viewer keyboard navigation', () {
    for (final count in [1, 3]) {
      testWidgets('Escape dismisses an untouched $count photo viewer', (
        tester,
      ) async {
        final page = await _viewer(tester, count: count);
        await _key(tester, LogicalKeyboardKey.escape);
        _closed(page, find.byType(TenturaFullscreenImageViewer));
      });
    }

    testWidgets('Arrows traverse photos and clamp at both ends', (
      tester,
    ) async {
      final page = await _viewer(tester);
      expect(find.text('1 / 3'), findsOneWidget);
      for (final title in ['2 / 3', '3 / 3', '3 / 3']) {
        await _key(tester, LogicalKeyboardKey.arrowRight);
        expect(find.text(title), findsOneWidget);
      }
      for (final title in ['2 / 3', '1 / 3', '1 / 3']) {
        await _key(tester, LogicalKeyboardKey.arrowLeft);
        expect(find.text(title), findsOneWidget);
      }
      expect(page.completed, isFalse);
    });

    testWidgets('Arrows leave a single photo visible without dismissing it', (
      tester,
    ) async {
      final page = await _viewer(tester, count: 1);
      for (final key in [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
      ]) {
        await _key(tester, key);
        expect(find.byType(TenturaFullscreenImageViewer), findsOneWidget);
        expect(find.byType(InteractiveViewer), findsOneWidget);
        expect(page.completed, isFalse);
      }
    });
  });

  group('Pinned facts sheet keyboard dismissal', () {
    for (final width in [375.0, 1280.0]) {
      for (final tabToControl in [false, true]) {
        testWidgets(
          'Escape closes only the facts sheet at width $width with tab focus $tabToControl',
          (tester) async {
            final cubit = (await tester.runAsync(_factsCubit))!;
            addTearDown(cubit.close);
            expect(cubit.state.pinnedFactsSeenAt, _old);
            final page = await _page(tester, width: width);
            page.watch(showBeaconPinnedFactsSheet(page.context, cubit: cubit));
            await tester.pumpAndSettle();
            final title = L10n.of(page.context)!.beaconFactsSheetTitle;
            expect(find.text(title), findsOneWidget);
            expect(find.text('Закреплённый факт'), findsOneWidget);
            expect(page.completed, isFalse);
            expect(cubit.state.pinnedFactsSeenAt, _old);
            expect(
              find.byType(Dialog),
              width >= 600 ? findsOneWidget : findsNothing,
            );
            if (tabToControl) {
              await _key(tester, LogicalKeyboardKey.tab);
              final focusContext = FocusManager.instance.primaryFocus!.context!;
              expect(ModalRoute.of(focusContext)!.isCurrent, isTrue);
              expect(
                find.ancestor(
                  of: find.byWidget(focusContext.widget),
                  matching: find.byType(IconButton),
                ),
                findsOneWidget,
              );
            }
            await _key(tester, LogicalKeyboardKey.escape);
            _closed(page, find.text(title));
            // The real markPinnedFactsSeen() emits this watermark from the
            // active facts. Assert its observable effect, retaining the real
            // cubit and use case rather than replacing the method with a spy.
            expect(cubit.state.pinnedFactsSeenAt, _new);
          },
        );
      }
    }
  });

  group('Shared adaptive sheet keyboard dismissal', () {
    testWidgets(
      'Escape on a tab focused button closes only the desktop sheet',
      (tester) async {
        final page = await _page(tester);
        page.watch(
          showTenturaAdaptiveSheet<void>(
            context: page.context,
            showSnackBars: true,
            builder: (_) =>
                TextButton(onPressed: () {}, child: const Text('Sheet action')),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Sheet action'), findsOneWidget);
        await _key(tester, LogicalKeyboardKey.tab);
        _expectButtonFocus(find.widgetWithText(TextButton, 'Sheet action'));
        await _key(tester, LogicalKeyboardKey.escape);
        _closed(page, find.text('Sheet action'));
      },
    );

    for (final baseline in _focusedEditorEscapeBaselines) {
      testWidgets(
        'Escape preserves focused editor text and dismissal with snackbar host ${baseline.showSnackBars}',
        (tester) async {
          final controller = TextEditingController();
          addTearDown(controller.dispose);
          final page = await _page(tester);
          page.watch(
            showTenturaAdaptiveSheet<void>(
              context: page.context,
              showSnackBars: baseline.showSnackBars,
              builder: (_) => TextField(controller: controller),
            ),
          );
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'Текст остаётся');
          await tester.pump();
          expect(find.byType(EditableText), findsOneWidget);
          await _key(tester, LogicalKeyboardKey.escape);
          expect(controller.text, baseline.textAfterEscape);
          // Compare with the captured pre-change outcome, independently of
          // whatever dismissal handling the implementation later adopts.
          if (!baseline.closesOnEscape) {
            expect(find.byType(TextField), findsOneWidget);
            expect(find.text('Текст остаётся'), findsOneWidget);
            expect(page.completed, isFalse);
          } else {
            _closed(page, find.byType(TextField));
          }
        },
      );
    }
  });
}
