// Wording of the fact picker and the «Add fact» menu: every key exists in EN
// and RU with a documented EN entry, follows the terminology (Request / Post,
// never beacon / room / episode), and the picker and menu lay out at
// 375x667 in both languages with every scope label un-truncated.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_facts_sheet.dart';
import 'package:tentura/features/post_view/ui/bloc/post_view_cubit.dart';
import 'package:tentura/features/post_view/ui/widget/post_info_sheet.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_picker_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_view/beacon_view_case_test_support.dart';
import 'fact_origin_test_support.dart';
import 'room_cubit_fakes.dart';

const _keys = [
  'factPickerTabAll',
  'factPickerTitleBring',
  'factPickerSearchHint',
  'factPickerTypeMore',
  'factPickerFactAdded',
  'beaconFactsAddMenuNew',
  'beaconFactsAddMenuPick',
  'beaconRoomFactPickerTabRequest',
  'beaconRoomFactPickerTitlePost',
  'beaconRoomFactPickerTabSaved',
  'capabilitySearchEmpty',
];

const _expectedEn = {
  'beaconRoomFactPickerTabRequest': 'In this Request',
  'beaconRoomFactPickerTabSaved': 'Saved',
  'beaconRoomFactPickerTitlePost': 'In this Post',
  'factPickerTabAll': 'All my facts',
  'beaconFactsAddMenuNew': 'New fact',
  'beaconFactsAddMenuPick': 'Pick from available',
  'factPickerTitleBring': 'Pick a fact',
  'factPickerSearchHint': 'Search facts',
  'factPickerTypeMore': 'Type 2 or more letters',
  'capabilitySearchEmpty': 'Nothing found',
  'factPickerFactAdded': 'Fact added',
};

const _expectedRu = {
  'beaconRoomFactPickerTabRequest': 'В запросе',
  'beaconRoomFactPickerTabSaved': 'Сохранённые',
  'beaconRoomFactPickerTitlePost': 'В посте',
  'factPickerTabAll': 'Все мои факты',
  'beaconFactsAddMenuNew': 'Новый факт',
  'beaconFactsAddMenuPick': 'Выбрать из доступных',
  'factPickerTitleBring': 'Выберите факт',
  'factPickerSearchHint': 'Поиск фактов',
  'factPickerTypeMore': 'Введите хотя бы 2 буквы',
  'capabilitySearchEmpty': 'Ничего не найдено',
  'factPickerFactAdded': 'Факт добавлен',
};

const _forbidden = [
  'episode',
  'эпизод',
  'beacon',
  'room',
  'маяк',
  'комнат',
];

Map<String, dynamic> _arb(String file) =>
    jsonDecode(File('l10n/$file').readAsStringSync()) as Map<String, dynamic>;

Map<String, String> _values(L10n l10n) => {
  'factPickerTabAll': l10n.factPickerTabAll,
  'factPickerTitleBring': l10n.factPickerTitleBring,
  'factPickerSearchHint': l10n.factPickerSearchHint,
  'factPickerTypeMore': l10n.factPickerTypeMore,
  'factPickerFactAdded': l10n.factPickerFactAdded,
  'beaconFactsAddMenuNew': l10n.beaconFactsAddMenuNew,
  'beaconFactsAddMenuPick': l10n.beaconFactsAddMenuPick,
  'beaconRoomFactPickerTabRequest': l10n.beaconRoomFactPickerTabRequest,
  'beaconRoomFactPickerTitlePost': l10n.beaconRoomFactPickerTitlePost,
  'beaconRoomFactPickerTabSaved': l10n.beaconRoomFactPickerTabSaved,
  'capabilitySearchEmpty': l10n.capabilitySearchEmpty,
};

void _registerLogger() {
  final getIt = GetIt.instance;
  if (getIt.isRegistered<Logger>()) return;
  getIt.registerSingleton<Logger>(Logger('test'));
  addTearDown(() {
    // ignore: discarded_futures -- best-effort unregister.
    getIt.unregister<Logger>();
  });
}

Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final weight in const ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('fonts/Inter-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// The texts under [root] that are cut (ellipsis / line limit). Measured
/// with the app font (Inter, loaded in `setUpAll`): the default test font's
/// 1 em glyphs are far wider than any real label.
List<String> _cutTexts(Finder root) => [
  for (final e
      in find.descendant(of: root, matching: find.byType(RichText)).evaluate())
    if (e.renderObject case final RenderParagraph ro
        when ro.hasSize && ro.didExceedMaxLines)
      ro.text.toPlainText(),
];

/// Each of [labels] is found once under [root] and is not cut.
void _expectWhole(Finder root, Iterable<String> labels) {
  for (final label in labels) {
    final text = find.descendant(of: root, matching: find.text(label));
    expect(text, findsOneWidget, reason: '«$label» is not shown');
    expect(
      _cutTexts(text),
      isEmpty,
      reason: '«$label» is cut with an ellipsis',
    );
  }
}

// --- the real hosts of the «Add fact» menu ---------------------------------

const _postId = 'Bpostinfo001';
const _viewer = Profile(id: kRoomCubitFakeMyUserId, displayName: 'Maria');
final _t0 = DateTime.utc(2026, 11, 14, 12);

class _PostRepository implements BeaconRepository {
  @override
  Stream<RepositoryEvent<Beacon>> get changes => const Stream.empty();

  @override
  Future<Beacon> fetchBeaconById(String id) async => Beacon(
    id: _postId,
    kind: BeaconKind.post,
    createdAt: _t0,
    updatedAt: _t0,
    expiresAt: _t0.add(const Duration(hours: 20)),
    author: _viewer,
    viewerCanForward: true,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _app(Locale locale, Widget home) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: locale,
  home: TenturaResponsiveScope(child: Scaffold(body: home)),
);

/// Opens the real Post info sheet of a writable Post (no facts).
Future<void> _openPostInfoSheet(WidgetTester tester, Locale locale) async {
  _registerLogger();
  registerFactRepository(FakeBeaconFactCardRepository());
  registerRoomCubitProfileCubit(_viewer.id);
  final threads = FakeBeaconThreadsRepository(userId: _viewer.id);
  addTearDown(threads.dispose);
  final room = RoomCubit(
    beaconId: _postId,
    beaconRoomCase: GetIt.I<BeaconThreadsCase>(),
    coordinationItemRoomSync: CoordinationItemRoomSync(),
    presenceRepository: roomCubitFakePresenceRepository(),
    effects: FakeUiEffectPort(),
    capabilities: const RoomCapabilities.post(),
  );
  final host = ThreadHostCubit(
    beaconId: _postId,
    capabilities: const RoomCapabilities.post(),
    roomCubitFactory:
        ({
          required beaconId,
          threadItemId,
          initialUnreadAnchorAt,
          capabilities = const RoomCapabilities.request(),
        }) => room,
  )..syncBeaconStatus(BeaconStatus.open, authorId: _viewer.id);
  final cubit = PostViewCubit(
    id: _postId,
    myProfile: _viewer,
    beaconRepository: _PostRepository(),
    effects: FakeUiEffectPort(),
    clock: () => _t0,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await cubit.close();
    await host.close();
  });
  await tester.runAsync(cubit.fetch);
  await tester.runAsync(
    () => host.select(
      RequestThread(
        threadId: RequestThread.generalId,
        kind: RequestThreadKind.general,
        lastSeenAt: _t0,
      ),
    ),
  );
  await _settle(tester);

  await tester.binding.setSurfaceSize(const Size(375, 667));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _app(
      locale,
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () =>
              unawaited(showPostInfoSheet(ctx, cubit: cubit, host: host)),
          child: const Text('open-info'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open-info'));
  await _settle(tester);
  expect(find.byType(PostInfoSheet), findsOneWidget);
}

/// Opens the real Request pinned-facts sheet for its author.
Future<void> _openRequestFactsSheet(WidgetTester tester, Locale locale) async {
  const author = Profile(id: 'Uauthor', displayName: 'Author');
  final cubit = (await tester.runAsync(() async {
    final case_ = buildTestBeaconViewCase(
      beaconRepo: TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => Beacon(
          id: 'Bsheet01',
          title: 'Facts beacon',
          createdAt: _t0,
          updatedAt: _t0,
          author: author,
        ),
      factCardsRepo: FakeBeaconViewFactCardRepository(),
      roomRepo: FakeBeaconViewRoomRepository(),
    );
    final c = BeaconViewCubit(
      id: 'Bsheet01',
      myProfile: author,
      beaconViewCase: case_,
      effects: FakeUiEffectPort(),
    );
    await c.stream
        .timeout(const Duration(seconds: 5))
        .firstWhere((s) => s.beaconContextLoaded);
    return c;
  }))!;
  addTearDown(cubit.close);
  await tester.binding.setSurfaceSize(const Size(375, 667));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _app(
      locale,
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () =>
              unawaited(showBeaconPinnedFactsSheet(ctx, cubit: cubit)),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  final en = _arb('app_en.arb');
  final ru = _arb('app_ru.arb');
  final enL10n = lookupL10n(const Locale('en'));
  final ruL10n = lookupL10n(const Locale('ru'));

  setUpAll(_loadInter);

  testWidgets('the cut-label check sees an ellipsised label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: const Scaffold(
          body: SizedBox(
            width: 60,
            child: Text(
              'Все мои факты',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
    expect(_cutTexts(find.byType(Scaffold)), ['Все мои факты']);
  });

  group('fact picker strings in the ARB files', () {
    for (final key in _keys) {
      test('$key is documented in EN and has a different RU value', () {
        expect(en[key], isA<String>(), reason: 'EN has $key');
        expect((en[key] as String).trim(), isNotEmpty);
        final meta = en['@$key'];
        expect(meta, isA<Map<String, dynamic>>(), reason: '@$key is missing');
        expect(
          ((meta as Map<String, dynamic>)['description'] as String? ?? '')
              .trim(),
          isNotEmpty,
          reason: '@$key needs a description',
        );
        expect(ru[key], isA<String>(), reason: 'RU has $key');
        expect((ru[key] as String).trim(), isNotEmpty);
        expect(ru[key], isNot(en[key]), reason: 'RU is translated');
      });

      test('$key avoids internal terms in EN and RU', () {
        for (final v in [en[key], ru[key]].whereType<String>()) {
          for (final bad in _forbidden) {
            expect(
              v.toLowerCase(),
              isNot(contains(bad)),
              reason: '«$v» must not say «$bad»',
            );
          }
        }
      });
    }
  });

  group('fact picker wording', () {
    test('EN strings', () {
      final v = _values(enL10n);
      _expectedEn.forEach((k, want) => expect(v[k], want, reason: k));
    });

    test('RU strings', () {
      final v = _values(ruL10n);
      _expectedRu.forEach((k, want) => expect(v[k], want, reason: k));
    });

    test('scope labels name Request and Post', () {
      expect(enL10n.beaconRoomFactPickerTabRequest, contains('Request'));
      expect(enL10n.beaconRoomFactPickerTitlePost, contains('Post'));
      expect(
        ruL10n.beaconRoomFactPickerTabRequest.toLowerCase(),
        contains('запрос'),
      );
      expect(
        ruL10n.beaconRoomFactPickerTitlePost.toLowerCase(),
        contains('пост'),
      );
    });
  });

  for (final locale in const [Locale('ru'), Locale('en')]) {
    final l10n = lookupL10n(locale);
    const size = Size(375, 667);
    final lang = locale.languageCode;

    Finder picker() => find.byType(FactPickerSheet);
    Finder tabs() => find.descendant(
      of: picker(),
      matching: find.byType(TenturaUnderlineTabs),
    );

    group('375x667 layout in $lang', () {
      testWidgets('bring picker shows its title and both scope labels', (
        tester,
      ) async {
        _registerLogger();
        registerFactRepository(FakeBeaconFactCardRepository());
        await pumpOpener(
          tester,
          locale: locale,
          size: size,
          open: (ctx) => unawaited(
            showFactPickFromAvailableSheet(
              ctx,
              beaconId: 'B1',
              isPost: false,
              onBrought: () async {},
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text(l10n.factPickerTitleBring), findsOneWidget);
        // Plan #1288 P10: bring mode has no «In this …» scope, only Saved
        // and All my facts (the criteria's third label, «In this Request»,
        // belongs to quote mode and is checked there).
        _expectWhole(find.byType(FactPickerSheet), [
          l10n.factPickerTitleBring,
        ]);
        _expectWhole(tabs(), [
          l10n.beaconRoomFactPickerTabSaved,
          l10n.factPickerTabAll,
        ]);
        expect(
          find.descendant(
            of: picker(),
            matching: find.text(l10n.beaconRoomFactPickerTabRequest),
          ),
          findsNothing,
          reason: 'bring mode offers no «In this Request» scope',
        );
      });

      for (final isPost in [false, true]) {
        testWidgets('quote picker in a ${isPost ? 'Post' : 'Request'} shows '
            'every scope label in full', (tester) async {
          _registerLogger();
          registerFactRepository(FakeBeaconFactCardRepository());
          registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
          final fakeRoom = FakeBeaconThreadsRepository(
            userId: kRoomCubitFakeMyUserId,
          );
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
            locale: locale,
            size: size,
            open: (ctx) => unawaited(
              showFactPickerSheet(ctx, cubit: cubit, isPost: isPost),
            ),
          );
          expect(tester.takeException(), isNull);
          final here = isPost
              ? l10n.beaconRoomFactPickerTitlePost
              : l10n.beaconRoomFactPickerTabRequest;
          // The header names the action; «In this Post» / «In this
          // Request» is the first scope tab, next to Saved and All my facts.
          _expectWhole(find.byType(FactPickerSheet), [
            l10n.beaconRoomFactPickerTitle,
          ]);
          _expectWhole(tabs(), [
            here,
            l10n.beaconRoomFactPickerTabSaved,
            l10n.factPickerTabAll,
          ]);
        });
      }

      testWidgets('All my facts scope shows the search hint and the '
          'two-letter prompt', (tester) async {
        _registerLogger();
        registerFactRepository(FakeBeaconFactCardRepository());
        await pumpOpener(
          tester,
          locale: locale,
          size: size,
          open: (ctx) => unawaited(
            showFactPickFromAvailableSheet(
              ctx,
              beaconId: 'B1',
              isPost: false,
              onBrought: () async {},
            ),
          ),
        );
        await tester.tap(
          find.descendant(
            of: tabs(),
            matching: find.text(l10n.factPickerTabAll),
          ),
        );
        await tester.pumpAndSettle();
        final field = find.descendant(
          of: picker(),
          matching: find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                w.decoration?.hintText == l10n.factPickerSearchHint,
          ),
        );
        expect(field, findsOneWidget);
        await tester.enterText(field, 'a');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(find.text(l10n.factPickerTypeMore), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      for (final host in const ['Post info sheet', 'Request facts sheet']) {
        testWidgets('Add fact menu opened from the $host shows both items '
            'in full', (tester) async {
          if (host == 'Post info sheet') {
            await _openPostInfoSheet(tester, locale);
          } else {
            await _openRequestFactsSheet(tester, locale);
          }
          await tester.tap(find.byKey(TestIds.key(TestIds.beaconFactsAdd)));
          await _settle(tester);
          expect(tester.takeException(), isNull);
          _expectWhole(find.byType(MenuItemButton), [
            l10n.beaconFactsAddMenuNew,
            l10n.beaconFactsAddMenuPick,
          ]);
        });
      }
    });
  }
}
