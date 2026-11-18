import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_attachment_widgets.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_facts_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/tentura_fullscreen_image_viewer.dart';

import '../../features/beacon_view/beacon_view_case_test_support.dart';
import '../../features/beacon_view/beacon_view_initial_load_test.dart';
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

Future<_Page> _page(WidgetTester tester, {double width = 1280}) async {
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
  navigator.currentState!.push<void>(
    MaterialPageRoute<void>(
      builder: (_) => TenturaResponsiveScope(
        child: Builder(
          builder: (context) {
            page.context = context;
            return const Scaffold(body: Text('Workspace'));
          },
        ),
      ),
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

Future<BeaconViewCubit> _factsCubit() async {
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
        factCardsRepo: FakeBeaconViewFactCardRepository(
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

void main() {
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
