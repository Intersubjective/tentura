import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_field_patches.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field_search_result.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field_hidden_item.dart';
import 'package:tentura/features/constellation/domain/port/constellation_field_hide_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_field_search_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_targeted_read_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_hide_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_search_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/screen/constellation_screen.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_person_search.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_visibility_bar.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_field_test_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');
final _loadedAt = DateTime.utc(2026, 11, 5, 12);

final class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);
  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

final class _MutableFieldRepository implements ConstellationRepositoryPort {
  _MutableFieldRepository(this.field);

  ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

final class _FakeSearchPort implements ConstellationFieldSearchPort {
  _FakeSearchPort(this.result, {this.fail = false, this.delay = Duration.zero});

  final ConstellationFieldSearchResult result;
  final bool fail;
  final Duration delay;
  final queries = <String>[];

  @override
  Future<ConstellationFieldSearchResult> search({
    required String query,
    required String context,
  }) async {
    queries.add(query);
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (fail) {
      throw StateError('offline');
    }
    return result;
  }
}

final class _QueryKeyedFakeSearchPort implements ConstellationFieldSearchPort {
  _QueryKeyedFakeSearchPort(this.resultsByQuery, {this.delay = Duration.zero});

  final Map<String, ConstellationFieldSearchResult> resultsByQuery;
  final Duration delay;
  final queries = <String>[];

  @override
  Future<ConstellationFieldSearchResult> search({
    required String query,
    required String context,
  }) async {
    queries.add(query);
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return resultsByQuery[query] ?? emptyConstellationFieldSearchResult;
  }
}

final class _RecordingHidePort implements ConstellationFieldHidePort {
  final unhideCalls = <({int targetKind, String targetId})>[];

  @override
  Future<void> hide({
    required int targetKind,
    required String targetId,
  }) async {}

  @override
  Future<void> unhide({
    required int targetKind,
    required String targetId,
  }) async {
    unhideCalls.add((targetKind: targetKind, targetId: targetId));
  }

  @override
  Future<List<ConstellationFieldHiddenItem>> fetchHiddenItems({
    String? cursor,
  }) async => const [];
}

final class _StubTargetedReadPort implements ConstellationTargetedReadPort {
  @override
  Future<List<ConstellationRequest>> fetchRequests(
    Set<String> beaconIds, {
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
  }) async => const [];

  @override
  Future<List<ConstellationViewerRelation>> readViewerRelations(
    Set<String> personIds,
  ) async => const [];
}

ConstellationField _fieldWithFilteredRequest() => ConstellationField(
  loadedAt: _loadedAt,
  context: 'ctx',
  peers: const [
    ConstellationPerson(id: 'ego', displayName: 'Ego'),
    ConstellationPerson(id: 'am', displayName: 'Alex'),
  ],
  edges: const [
    ConstellationTrustEdgeEntity(src: 'ego', dst: 'am', tier: 1),
  ],
  directContactIds: const ['am'],
  requests: [
    ConstellationRequest(
      id: 'req-hidden-filter',
      authorId: 'am',
      title: 'Need boxes',
      status: 0,
      needs: const ['moving'],
      primaryNeedSlug: 'moving',
      lastActivityAt: _loadedAt,
    ),
  ],
);

ConstellationField _emptyFieldBase() => ConstellationField(
  loadedAt: _loadedAt,
  context: 'ctx',
  peers: const [
    ConstellationPerson(id: 'ego', displayName: 'Ego'),
    ConstellationPerson(id: 'am', displayName: 'Alex'),
  ],
  edges: const [
    ConstellationTrustEdgeEntity(src: 'ego', dst: 'am', tier: 1),
  ],
  directContactIds: const ['am'],
);

Future<ConstellationCubit> _loadCubit({
  required ConstellationField field,
  ConstellationFieldSearchCase? searchCase,
  ConstellationFieldHideCase? hideCase,
  _RecordingHidePort? hidePortForCase,
  ConstellationRepositoryPort? repositoryOverride,
}) async {
  final fixture = ConstellationStoreFixture(
    repositoryOverride ?? _StubRepository(field),
    accountId: 'ego',
  );
  final resolvedHide =
      hideCase ??
      (hidePortForCase != null
          ? ConstellationFieldHideCase(
              hidePortForCase,
              fixture.store,
              _StubTargetedReadPort(),
              env: const Env.fromEnvironment(),
              logger: Logger('test'),
            )
          : null);
  final cubit = ConstellationCubit(
    case_: fixture.store,
    viewer: _ego,
    fieldSearchCase: searchCase,
    fieldHideCase: resolvedHide,
  );
  await cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
  cubit.updateLabelBudgetContext(
    viewport: const Size(1200, 900),
    textScaleFactor: 1,
  );
  return cubit;
}

ConstellationFieldSearchCase _searchCase(ConstellationFieldSearchPort port) =>
    ConstellationFieldSearchCase(
      port,
      env: const Env.fromEnvironment(),
      logger: Logger('test'),
    );

Widget _app(
  Widget child, {
  Locale locale = const Locale('en'),
  List<NavigatorObserver>? navigatorObservers,
}) => MaterialApp(
  locale: locale,
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  navigatorObservers: navigatorObservers ?? const [],
  home: TenturaResponsiveScope(child: child),
);

/// Drives search through the real [SearchAnchor] overlay (not a manual second
/// [SearchAnchor.suggestionsBuilder] call). Prior tests used a helper that
/// re-invoked `suggestionsBuilder` after completion, which masked #1046.
Future<void> _openFieldSearchOverlay(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('constellation.app_bar.search')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _typeFieldSearchQuery(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField).last, query);
  await tester.pump();
}

Future<void> _waitFieldSearchSettle(
  WidgetTester tester, {
  Duration afterDebounce = const Duration(milliseconds: 80),
}) async {
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(afterDebounce);
  await tester.pump();
}

Future<void> _searchInOpenOverlay(
  WidgetTester tester,
  String query, {
  Duration afterDebounce = const Duration(milliseconds: 80),
}) async {
  await _openFieldSearchOverlay(tester);
  await _typeFieldSearchQuery(tester, query);
  await _waitFieldSearchSettle(tester, afterDebounce: afterDebounce);
}

Future<ConstellationCubit> _pumpFieldMapScreen(
  WidgetTester tester,
  ConstellationCubit cubit, {
  Locale locale = const Locale('ru'),
  Size size = kPhoneSurface,
}) async {
  if (size == kPhoneSurface) {
    await usePhoneSurface(tester);
  } else {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  await tester.pumpPeopleTagsWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ConstellationCubit>.value(value: cubit),
              BlocProvider(create: (_) => HomeTabReselectCubit()),
              BlocProvider<GraphPersonContextCubit>(
                create: (_) => FieldBodyTestGraphPersonContextCubit(),
              ),
              BlocProvider<ScreenCubit>(
                create: (_) => ScreenCubit(FakeUiEffectPort()),
              ),
            ],
            child: const ConstellationScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await stabilizeConstellationFieldChromeForTests(tester, cubit);
  await tester.pumpAndSettle();
  return cubit;
}

Future<void> _waitForBeaconNode(
  WidgetTester tester,
  ConstellationCubit cubit,
  String beaconId,
) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    if (_fieldHasBeaconNode(cubit, beaconId)) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _expectComposedSearchBeacon(ConstellationCubit cubit, String beaconId) {
  final composition = cubit.state.composition;
  expect(composition, isNotNull);
  expect(composition!.eligibleRequestIds.contains(beaconId), isTrue);
  expect(
    composition.beaconNodes.any((node) => node.id == beaconId),
    isTrue,
  );
}

bool _fieldHasBeaconNode(ConstellationCubit cubit, String beaconId) {
  for (final node
      in cubit.graphController.renderSnapshot.topology.nodesById.values) {
    final payload = node.payload;
    if (payload is! FieldBeaconNode) {
      continue;
    }
    if (payload.request?.id == beaconId || payload.post?.id == beaconId) {
      return true;
    }
  }
  return false;
}

Future<void> _pickHiddenSearchHit(
  WidgetTester tester, {
  required String query,
  required String hitKey,
}) async {
  await _searchInOpenOverlay(tester, query);
  final hit = find.byKey(Key(hitKey));
  expect(hit, findsOneWidget);
  await tester.tap(hit);
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  group('Field search (#255)', () {
    test('searchField skips the port when the query is too short', () async {
      final port = _FakeSearchPort(emptyConstellationFieldSearchResult);
      final cubit = await _loadCubit(
        field: _fieldWithFilteredRequest(),
        searchCase: _searchCase(port),
      );
      addTearDown(cubit.close);

      await cubit.searchField('a');
      expect(port.queries, isEmpty);
    });

    test('searchField trims the query before calling the port', () async {
      final port = _FakeSearchPort(emptyConstellationFieldSearchResult);
      final cubit = await _loadCubit(
        field: _fieldWithFilteredRequest(),
        searchCase: _searchCase(port),
      );
      addTearDown(cubit.close);

      await cubit.searchField('  move ');
      expect(port.queries, ['move']);
    });

    testWidgets('groups People, Requests and Posts in suggestions', (
      tester,
    ) async {
      final port = _FakeSearchPort(
        ConstellationFieldSearchResult(
          people: const [
            ConstellationFieldSearchPersonHit(id: 'am', displayName: 'Alex'),
          ],
          requests: [
            ConstellationFieldSearchRequestHit(
              id: 'req-1',
              authorId: 'am',
              title: 'Moving help',
              status: 0,
              hidden: false,
              lastActivityAt: _loadedAt,
            ),
          ],
          posts: [
            ConstellationFieldSearchPostHit(
              id: 'post-1',
              authorId: 'am',
              rootExcerpt: 'Ladder?',
              status: 0,
              hidden: false,
              lastActivityAt: _loadedAt,
            ),
          ],
        ),
      );
      final cubit = await _loadCubit(
        field: _fieldWithFilteredRequest(),
        searchCase: _searchCase(port),
      );
      addTearDown(cubit.close);

      await tester.pumpPeopleTagsWidget(
        _app(
          BlocProvider.value(
            value: cubit,
            child: const Scaffold(body: ConstellationPersonSearchButton()),
          ),
        ),
      );

      await _searchInOpenOverlay(tester, 'move');

      expect(find.text('PEOPLE'), findsOneWidget);
      expect(find.text('REQUESTS'), findsOneWidget);
      expect(find.text('POSTS'), findsOneWidget);
      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('Moving help'), findsOneWidget);
      expect(find.text('Ladder?'), findsOneWidget);
      expect(port.queries, ['move']);
    });

    testWidgets('offline fallback lists local people when search fails', (
      tester,
    ) async {
      final port = _FakeSearchPort(
        emptyConstellationFieldSearchResult,
        fail: true,
      );
      final cubit = await _loadCubit(
        field: _fieldWithFilteredRequest(),
        searchCase: _searchCase(port),
      );
      addTearDown(cubit.close);

      await tester.pumpPeopleTagsWidget(
        _app(
          BlocProvider.value(
            value: cubit,
            child: const Scaffold(body: ConstellationPersonSearchButton()),
          ),
        ),
      );

      await _searchInOpenOverlay(tester, 'alex');

      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('Requests'), findsNothing);
    });

    test('hidden post pick keeps selection via injected post lookup', () async {
      final cubit = await _loadCubit(field: _emptyFieldBase());
      addTearDown(cubit.close);
      cubit.pickFieldSearchBeacon(
        hit: ConstellationFieldSearchRequestHit(
          id: 'post-h',
          authorId: 'am',
          title: 'Post about 1137',
          status: 0,
          hidden: true,
          lastActivityAt: _loadedAt,
        ),
        insets: EdgeInsets.zero,
        isPost: true,
      );
      expect(cubit.state.selectedRequestId, 'post-h');
      expect(cubit.postById('post-h'), isNotNull);
      expect(cubit.isPostId('post-h'), isTrue);
    });

    test('on-Field pick selects without temporary outline', () async {
      final field = ConstellationField(
        loadedAt: _loadedAt,
        context: '',
        peers: const [
          ConstellationPerson(id: 'ego', displayName: 'Ego'),
          ConstellationPerson(id: 'am', displayName: 'Alex'),
        ],
        edges: const [
          ConstellationTrustEdgeEntity(src: 'ego', dst: 'am', tier: 1),
        ],
        directContactIds: const ['am'],
        requests: [
          ConstellationRequest(
            id: 'req-visible',
            authorId: 'am',
            title: 'Visible',
            status: 0,
            lastActivityAt: _loadedAt,
          ),
        ],
      );
      final cubit = await _loadCubit(field: field);
      addTearDown(cubit.close);

      cubit.pickFieldSearchBeacon(
        hit: ConstellationFieldSearchRequestHit(
          id: 'req-visible',
          authorId: 'am',
          title: 'Visible',
          status: 0,
          hidden: false,
          lastActivityAt: _loadedAt,
        ),
        insets: EdgeInsets.zero,
        isPost: false,
      );

      expect(cubit.state.selectedRequestId, 'req-visible');
      expect(cubit.isSearchTemporaryOutlineBeacon('req-visible'), isFalse);
    });

    test('filtered-out pick uses temporary outline until cleared', () async {
      final cubit = await _loadCubit(field: _fieldWithFilteredRequest());
      addTearDown(cubit.close);
      cubit
        ..setFilterCapabilitySlugs({'nonexistent-capability'})
        ..pickFieldSearchBeacon(
          hit: ConstellationFieldSearchRequestHit(
            id: 'req-hidden-filter',
            authorId: 'am',
            title: 'Need boxes',
            status: 0,
            hidden: false,
            lastActivityAt: _loadedAt,
          ),
          insets: EdgeInsets.zero,
          isPost: false,
        );

      expect(cubit.state.selectedRequestId, 'req-hidden-filter');
      expect(cubit.isSearchTemporaryOutlineBeacon('req-hidden-filter'), isTrue);

      cubit.selectRequest(null);
      expect(
        cubit.isSearchTemporaryOutlineBeacon('req-hidden-filter'),
        isFalse,
      );
    });

    testWidgets(
      'hidden Request search pick on Field map (RU phone, real body path)',
      (tester) async {
        const requestId = 'req-h';
        final repo = _MutableFieldRepository(_emptyFieldBase());
        final hidePort = _RecordingHidePort();
        final searchPort = _QueryKeyedFakeSearchPort({
          '1137': ConstellationFieldSearchResult(
            requests: [
              ConstellationFieldSearchRequestHit(
                id: requestId,
                authorId: 'am',
                title: 'Move 1137 boxes',
                status: 0,
                hidden: true,
                lastActivityAt: _loadedAt,
              ),
            ],
          ),
        });
        final cubit = await _loadCubit(
          field: repo.field,
          repositoryOverride: repo,
          searchCase: _searchCase(searchPort),
          hidePortForCase: hidePort,
        );
        addTearDown(cubit.close);
        await _pumpFieldMapScreen(
          tester,
          cubit,
          locale: const Locale('ru'),
        );

        final controller = cubit.graphController;
        final cameraBeforePick = controller.viewportLocalToScene(Offset.zero);
        controller.jumpToPosition(const Offset(8000, 8000));
        await tester.pump();

        await _pickHiddenSearchHit(
          tester,
          query: '1137',
          hitKey: 'constellation.field_search.request.$requestId',
        );

        expect(
          find.byKey(const Key('constellation.selection_unavailable')),
          findsNothing,
        );
        expect(cubit.state.selectedRequestId, requestId);
        expect(cubit.isSearchTemporaryOutlineBeacon(requestId), isTrue);
        _expectComposedSearchBeacon(cubit, requestId);
        await _waitForBeaconNode(tester, cubit, requestId);
        final outline = find.byKey(
          Key(TestIds.constellationTemporaryOutline(requestId)),
        );
        if (outline.evaluate().isNotEmpty) {
          expect(outline, findsWidgets);
        }
        final onMap = find.byKey(TestIds.key(TestIds.graphNode(requestId)));
        if (_fieldHasBeaconNode(cubit, requestId)) {
          expect(onMap, findsOneWidget);
          expect(
            controller.viewportLocalToScene(Offset.zero),
            isNot(cameraBeforePick),
          );
        }
        expect(
          find.byKey(TestIds.key(TestIds.constellationShowAgain)),
          findsOneWidget,
        );

        repo.field = repo.field.copyWith(
          requests: [
            ConstellationRequest(
              id: requestId,
              authorId: 'am',
              title: 'Move 1137 boxes',
              status: 0,
              lastActivityAt: _loadedAt,
            ),
          ],
        );
        final showAgain = find.byKey(
          TestIds.key(TestIds.constellationShowAgain),
        );
        await tester.ensureVisible(showAgain);
        await tester.tap(showAgain);
        await tester.pumpAndSettle();

        expect(
          hidePort.unhideCalls.map((e) => e.targetId),
          contains(requestId),
        );
        expect(cubit.isSearchTemporaryOutlineBeacon(requestId), isFalse);

        cubit.setViewMode(ConstellationViewMode.text);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('constellation.selection_unavailable')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'hidden Request search pick on Field map (EN desktop, real body path)',
      (tester) async {
        const requestId = 'req-h';
        final repo = _MutableFieldRepository(_emptyFieldBase());
        final searchPort = _QueryKeyedFakeSearchPort({
          '1137': ConstellationFieldSearchResult(
            requests: [
              ConstellationFieldSearchRequestHit(
                id: requestId,
                authorId: 'am',
                title: 'Shipment 1137',
                status: 0,
                hidden: true,
                lastActivityAt: _loadedAt,
              ),
            ],
          ),
        });
        final cubit = await _loadCubit(
          field: repo.field,
          repositoryOverride: repo,
          searchCase: _searchCase(searchPort),
          hidePortForCase: _RecordingHidePort(),
        );
        addTearDown(cubit.close);
        await _pumpFieldMapScreen(
          tester,
          cubit,
          locale: const Locale('en'),
          size: const Size(1280, 800),
        );

        await _pickHiddenSearchHit(
          tester,
          query: '1137',
          hitKey: 'constellation.field_search.request.$requestId',
        );

        expect(
          find.byKey(const Key('constellation.selection_unavailable')),
          findsNothing,
        );
        expect(cubit.state.selectedRequestId, requestId);
        expect(find.text('Show again'), findsOneWidget);
      },
    );

    testWidgets(
      'hidden Post search pick on Field map (RU phone, real body path)',
      (tester) async {
        const postId = 'post-h';
        final repo = _MutableFieldRepository(_emptyFieldBase());
        final hidePort = _RecordingHidePort();
        final searchPort = _QueryKeyedFakeSearchPort({
          '1137': ConstellationFieldSearchResult(
            posts: [
              ConstellationFieldSearchPostHit(
                id: postId,
                authorId: 'am',
                rootExcerpt: 'Post about 1137',
                status: 0,
                hidden: true,
                lastActivityAt: _loadedAt,
              ),
            ],
          ),
        });
        final cubit = await _loadCubit(
          field: repo.field,
          repositoryOverride: repo,
          searchCase: _searchCase(searchPort),
          hidePortForCase: hidePort,
        );
        addTearDown(cubit.close);
        await _pumpFieldMapScreen(
          tester,
          cubit,
          locale: const Locale('ru'),
        );

        await _pickHiddenSearchHit(
          tester,
          query: '1137',
          hitKey: 'constellation.field_search.post.$postId',
        );

        expect(
          find.byKey(const Key('constellation.selection_unavailable')),
          findsNothing,
        );
        expect(cubit.state.selectedRequestId, postId);
        expect(cubit.isPostId(postId), isTrue);
        _expectComposedSearchBeacon(cubit, postId);
        await _waitForBeaconNode(tester, cubit, postId);
        expect(
          find.byKey(TestIds.key(TestIds.constellationShowAgain)),
          findsOneWidget,
        );

        repo.field = repo.field.copyWith(
          posts: [
            ConstellationPost(
              id: postId,
              authorId: 'am',
              rootExcerpt: 'Post about 1137',
              status: 0,
              lastActivityAt: _loadedAt,
            ),
          ],
        );
        final showAgain = find.byKey(
          TestIds.key(TestIds.constellationShowAgain),
        );
        await tester.ensureVisible(showAgain);
        await tester.tap(showAgain);
        await tester.pumpAndSettle();
        expect(hidePort.unhideCalls.map((e) => e.targetId), contains(postId));
      },
    );

    testWidgets('empty Field search query shows neutral prompt', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        field: _fieldWithFilteredRequest(),
        searchCase: _searchCase(
          _FakeSearchPort(emptyConstellationFieldSearchResult),
        ),
      );
      addTearDown(cubit.close);

      await tester.pumpPeopleTagsWidget(
        _app(
          BlocProvider.value(
            value: cubit,
            child: const Scaffold(body: ConstellationPersonSearchButton()),
          ),
        ),
      );

      final anchor = tester.widget<SearchAnchor>(find.byType(SearchAnchor));
      final anchorContext = tester.element(find.byType(SearchAnchor));
      final controller = SearchController();
      addTearDown(controller.dispose);
      controller.text = '';
      final widgets = await anchor.suggestionsBuilder(
        anchorContext,
        controller,
      );
      await tester.pumpPeopleTagsWidget(
        _app(Scaffold(body: ListView(children: widgets.toList()))),
      );

      expect(
        find.byKey(const Key('constellation.field_search.prompt')),
        findsOneWidget,
      );
      expect(find.text('Start typing to search your Field.'), findsOneWidget);
    });

    testWidgets(
      'whitespace-only Field search query shows neutral prompt (RU, phone)',
      (tester) async {
        await usePhoneSurface(tester);
        final cubit = await _loadCubit(
          field: _fieldWithFilteredRequest(),
          searchCase: _searchCase(
            _FakeSearchPort(emptyConstellationFieldSearchResult),
          ),
        );
        addTearDown(cubit.close);

        await tester.pumpPeopleTagsWidget(
          _app(
            BlocProvider.value(
              value: cubit,
              child: const Scaffold(body: ConstellationPersonSearchButton()),
            ),
            locale: const Locale('ru'),
          ),
        );

        final anchor = tester.widget<SearchAnchor>(find.byType(SearchAnchor));
        final anchorContext = tester.element(find.byType(SearchAnchor));
        final controller = SearchController();
        addTearDown(controller.dispose);
        controller.text = '   ';
        final widgets = await anchor.suggestionsBuilder(
          anchorContext,
          controller,
        );
        await tester.pumpPeopleTagsWidget(
          _app(
            Scaffold(body: ListView(children: widgets.toList())),
            locale: const Locale('ru'),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.text(
            'Начните вводить текст, чтобы искать по «Полю».',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'server search failure shows unavailable copy and ends loading (RU, phone)',
      (tester) async {
        await usePhoneSurface(tester);
        final l10nRu = lookupL10n(const Locale('ru'));
        final port = _FakeSearchPort(
          emptyConstellationFieldSearchResult,
          fail: true,
        );
        final cubit = await _loadCubit(
          field: _fieldWithFilteredRequest(),
          searchCase: _searchCase(port),
        );
        addTearDown(cubit.close);

        await tester.pumpPeopleTagsWidget(
          _app(
            BlocProvider.value(
              value: cubit,
              child: const Scaffold(body: ConstellationPersonSearchButton()),
            ),
            locale: const Locale('ru'),
          ),
        );

        await _searchInOpenOverlay(tester, 'zz');

        expect(tester.takeException(), isNull);
        expect(find.byType(TenturaCircularProgress), findsNothing);
        expect(
          find.byKey(const Key('constellation.field_search.error')),
          findsOneWidget,
        );
        expect(
          find.text(l10nRu.constellationFieldSearchUnavailable),
          findsOneWidget,
        );
        expect(port.queries, ['zz']);
      },
    );

    testWidgets(
      'one-character query shows minimum-length hint instead of spinner',
      (tester) async {
        final cubit = await _loadCubit(
          field: _fieldWithFilteredRequest(),
          searchCase: _searchCase(
            _FakeSearchPort(emptyConstellationFieldSearchResult),
          ),
        );
        addTearDown(cubit.close);

        await tester.pumpPeopleTagsWidget(
          _app(
            BlocProvider.value(
              value: cubit,
              child: const Scaffold(body: ConstellationPersonSearchButton()),
            ),
          ),
        );

        final anchor = tester.widget<SearchAnchor>(find.byType(SearchAnchor));
        final anchorContext = tester.element(find.byType(SearchAnchor));
        final controller = SearchController();
        addTearDown(controller.dispose);
        controller.text = 'a';
        final widgets = await anchor.suggestionsBuilder(
          anchorContext,
          controller,
        );
        await tester.pumpPeopleTagsWidget(
          _app(Scaffold(body: ListView(children: widgets.toList()))),
        );

        expect(
          find.byKey(const Key('constellation.field_search.short_query')),
          findsOneWidget,
        );
        expect(find.byType(TenturaCircularProgress), findsNothing);
      },
    );

    testWidgets(
      'server returns only the viewer — show self-only message (#1046)',
      (tester) async {
        final port = _FakeSearchPort(
          const ConstellationFieldSearchResult(
            people: [
              ConstellationFieldSearchPersonHit(
                id: 'ego',
                displayName: 'Bob Q1106',
              ),
            ],
          ),
        );
        final cubit = await _loadCubit(
          field: _fieldWithFilteredRequest(),
          searchCase: _searchCase(port),
        );
        addTearDown(cubit.close);

        await tester.pumpPeopleTagsWidget(
          _app(
            BlocProvider.value(
              value: cubit,
              child: const Scaffold(body: ConstellationPersonSearchButton()),
            ),
          ),
        );

        await _searchInOpenOverlay(tester, 'bo');

        expect(port.queries, ['bo']);
        expect(
          find.text(
            'Only your profile matches — others on the Field are listed on the map.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('RU 375×667 search suggestions do not overflow', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      final port = _FakeSearchPort(
        ConstellationFieldSearchResult(
          requests: [
            ConstellationFieldSearchRequestHit(
              id: 'req-long',
              authorId: 'am',
              title: 'Очень длинное название запроса на перемещение коробок',
              status: 0,
              hidden: false,
              lastActivityAt: _loadedAt,
            ),
          ],
        ),
      );
      final cubit = await _loadCubit(
        field: _fieldWithFilteredRequest(),
        searchCase: _searchCase(port),
      );
      addTearDown(cubit.close);

      await tester.pumpPeopleTagsWidget(
        _app(
          BlocProvider.value(
            value: cubit,
            child: const Scaffold(body: ConstellationPersonSearchButton()),
          ),
          locale: const Locale('ru'),
        ),
      );

      await _searchInOpenOverlay(tester, 'кор');

      expect(tester.takeException(), isNull);
      expect(find.textContaining('коробок'), findsOneWidget);
    });

    group('#1046 Field search spinner', () {
      testWidgets(
        'Boris query shows hits when search completes without another keystroke (RU, phone)',
        (tester) async {
          await usePhoneSurface(tester);
          final port = _FakeSearchPort(
            const ConstellationFieldSearchResult(
              people: [
                ConstellationFieldSearchPersonHit(
                  id: 'boris',
                  displayName: 'Boris',
                ),
              ],
            ),
            delay: const Duration(milliseconds: 80),
          );
          final cubit = await _loadCubit(
            field: _fieldWithFilteredRequest(),
            searchCase: _searchCase(port),
          );
          addTearDown(cubit.close);

          await tester.pumpPeopleTagsWidget(
            _app(
              BlocProvider.value(
                value: cubit,
                child: const Scaffold(body: ConstellationPersonSearchButton()),
              ),
              locale: const Locale('ru'),
            ),
          );

          await _searchInOpenOverlay(
            tester,
            'Boris',
            afterDebounce: const Duration(milliseconds: 120),
          );

          expect(tester.takeException(), isNull);
          expect(find.byType(TenturaCircularProgress), findsNothing);
          expect(
            find.byKey(const Key('constellation.field_search.person.boris')),
            findsOneWidget,
          );
          expect(port.queries, ['Boris']);
        },
      );

      testWidgets(
        'no-match query shows finished empty copy in the open overlay (EN, phone)',
        (tester) async {
          await usePhoneSurface(tester);
          final port = _FakeSearchPort(
            emptyConstellationFieldSearchResult,
            delay: const Duration(milliseconds: 50),
          );
          final cubit = await _loadCubit(
            field: _fieldWithFilteredRequest(),
            searchCase: _searchCase(port),
          );
          addTearDown(cubit.close);

          await tester.pumpPeopleTagsWidget(
            _app(
              BlocProvider.value(
                value: cubit,
                child: const Scaffold(body: ConstellationPersonSearchButton()),
              ),
            ),
          );

          await _searchInOpenOverlay(tester, 'zzqyx');

          expect(find.byType(TenturaCircularProgress), findsNothing);
          expect(
            find.byKey(const Key('constellation.field_search.empty')),
            findsOneWidget,
          );
          expect(find.text('No matches on your Field.'), findsOneWidget);
        },
      );

      testWidgets(
        'search failure shows error state without re-opening suggestions (RU, phone)',
        (tester) async {
          await usePhoneSurface(tester);
          final l10nRu = lookupL10n(const Locale('ru'));
          final port = _FakeSearchPort(
            emptyConstellationFieldSearchResult,
            fail: true,
            delay: const Duration(milliseconds: 40),
          );
          final cubit = await _loadCubit(
            field: _fieldWithFilteredRequest(),
            searchCase: _searchCase(port),
          );
          addTearDown(cubit.close);

          await tester.pumpPeopleTagsWidget(
            _app(
              BlocProvider.value(
                value: cubit,
                child: const Scaffold(body: ConstellationPersonSearchButton()),
              ),
              locale: const Locale('ru'),
            ),
          );

          await _searchInOpenOverlay(tester, 'zzq');

          expect(find.byType(TenturaCircularProgress), findsNothing);
          expect(
            find.byKey(const Key('constellation.field_search.error')),
            findsOneWidget,
          );
          expect(
            find.text(l10nRu.constellationFieldSearchUnavailable),
            findsOneWidget,
          );
        },
      );

      testWidgets('fast typing keeps only the last query results (RU, phone)', (
        tester,
      ) async {
        await usePhoneSurface(tester);
        final port = _QueryKeyedFakeSearchPort(
          {
            'Bori': const ConstellationFieldSearchResult(
              people: [
                ConstellationFieldSearchPersonHit(
                  id: 'stale',
                  displayName: 'Stale hit',
                ),
              ],
            ),
            'Boris': const ConstellationFieldSearchResult(
              people: [
                ConstellationFieldSearchPersonHit(
                  id: 'boris',
                  displayName: 'Boris',
                ),
              ],
            ),
          },
          delay: const Duration(milliseconds: 60),
        );
        final cubit = await _loadCubit(
          field: _fieldWithFilteredRequest(),
          searchCase: ConstellationFieldSearchCase(
            port,
            env: const Env.fromEnvironment(),
            logger: Logger('test'),
          ),
        );
        addTearDown(cubit.close);

        await tester.pumpPeopleTagsWidget(
          _app(
            BlocProvider.value(
              value: cubit,
              child: const Scaffold(body: ConstellationPersonSearchButton()),
            ),
            locale: const Locale('ru'),
          ),
        );

        await _openFieldSearchOverlay(tester);
        final field = find.byType(TextField).last;
        await tester.enterText(field, 'Bori');
        await tester.pump();
        await tester.enterText(field, 'Boris');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();

        expect(
          find.byKey(const Key('constellation.field_search.person.boris')),
          findsOneWidget,
        );
        expect(find.text('Stale hit'), findsNothing);
        expect(port.queries.last, 'Boris');
      });
    });

    testWidgets(
      '#1049 Field search overlay pop clears second-degree chip tooltip (RU phone)',
      (tester) async {
        await usePhoneSurface(tester);
        final l10nRu = lookupL10n(const Locale('ru'));
        final degreeHint = l10nRu.constellationShowDegreeSecondHint;
        final port = _FakeSearchPort(
          const ConstellationFieldSearchResult(
            people: [
              ConstellationFieldSearchPersonHit(id: 'am', displayName: 'Alex'),
            ],
          ),
        );
        final cubit = await _loadCubit(
          field: _fieldWithFilteredRequest(),
          searchCase: _searchCase(port),
        );
        addTearDown(cubit.close);

        await tester.pumpPeopleTagsWidget(
          _app(
            BlocProvider.value(
              value: cubit,
              child: const Scaffold(
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConstellationVisibilityBar(),
                    Expanded(child: ConstellationPersonSearchButton()),
                  ],
                ),
              ),
            ),
            locale: const Locale('ru'),
            navigatorObservers: [ClearSnackBarsOnPushObserver()],
          ),
        );

        final degreeChip = find.byKey(
          const Key('constellation.show.degree.second'),
        );
        await tester.scrollUntilVisible(
          degreeChip,
          16,
          scrollable: find.descendant(
            of: find.byKey(const Key('constellation.show')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.longPress(degreeChip);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text(degreeHint), findsWidgets);

        await tester.tap(find.byKey(const Key('constellation.app_bar.search')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        await tester.enterText(find.byType(TextField).last, 'al');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();

        final back = find.byIcon(Icons.arrow_back);
        expect(back, findsOneWidget);
        await tester.tap(back);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text(degreeHint), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
