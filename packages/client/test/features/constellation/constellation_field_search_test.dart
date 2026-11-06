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
import 'package:tentura/features/constellation/ui/widget/constellation_person_search.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_visibility_bar.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_request_preview_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';

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

final class _FakeSearchPort implements ConstellationFieldSearchPort {
  _FakeSearchPort(this.result, {this.fail = false});

  final ConstellationFieldSearchResult result;
  final bool fail;
  final queries = <String>[];

  @override
  Future<ConstellationFieldSearchResult> search({
    required String query,
    required String context,
  }) async {
    queries.add(query);
    if (fail) {
      throw StateError('offline');
    }
    return result;
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

Future<ConstellationCubit> _loadCubit({
  required ConstellationField field,
  ConstellationFieldSearchCase? searchCase,
  ConstellationFieldHideCase? hideCase,
  _RecordingHidePort? hidePortForCase,
}) async {
  final fixture = ConstellationStoreFixture(
    _StubRepository(field),
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

ConstellationFieldSearchCase _searchCase(_FakeSearchPort port) =>
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

Future<List<Widget>> _suggestionsAfterQuery(
  WidgetTester tester,
  SearchController controller,
  String query,
) async {
  controller.text = query;
  await tester.pump();
  final anchor = tester.widget<SearchAnchor>(find.byType(SearchAnchor));
  final context = tester.element(find.byType(SearchAnchor));
  await anchor.suggestionsBuilder(context, controller);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
  final built = await anchor.suggestionsBuilder(context, controller);
  return built.toList();
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

      final controller = SearchController();
      addTearDown(controller.dispose);
      final widgets = await _suggestionsAfterQuery(tester, controller, 'move');
      await tester.pumpPeopleTagsWidget(
        _app(Scaffold(body: ListView(children: widgets))),
      );

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

      final controller = SearchController();
      addTearDown(controller.dispose);
      final widgets = await _suggestionsAfterQuery(tester, controller, 'alex');
      await tester.pumpPeopleTagsWidget(
        _app(Scaffold(body: ListView(children: widgets))),
      );

      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('Requests'), findsNothing);
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

    testWidgets('Show again on hidden search hit calls fieldUnhide', (
      tester,
    ) async {
      final hidePort = _RecordingHidePort();
      final cubit = await _loadCubit(
        field: ConstellationField(
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
        ),
        hidePortForCase: hidePort,
      );
      addTearDown(cubit.close);

      cubit.pickFieldSearchBeacon(
        hit: ConstellationFieldSearchRequestHit(
          id: 'req-hidden-user',
          authorId: 'am',
          title: 'Hidden item',
          status: 0,
          hidden: true,
          lastActivityAt: _loadedAt,
        ),
        insets: EdgeInsets.zero,
        isPost: false,
      );

      await tester.pumpPeopleTagsWidget(
        _app(
          BlocProvider.value(
            value: cubit,
            child: const Scaffold(
              body: ConstellationRequestPreviewSheet(
                request: ConstellationRequest(
                  id: 'req-hidden-user',
                  authorId: 'am',
                  title: 'Hidden item',
                  status: 0,
                ),
                authorDisplayName: 'Alex',
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(TestIds.key(TestIds.constellationShowAgain)));
      await tester.pumpAndSettle();

      expect(hidePort.unhideCalls, hasLength(1));
      expect(hidePort.unhideCalls.single.targetId, 'req-hidden-user');
    });

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

        final controller = SearchController();
        addTearDown(controller.dispose);
        final widgets = await _suggestionsAfterQuery(tester, controller, 'bo');
        await tester.pumpPeopleTagsWidget(
          _app(Scaffold(body: ListView(children: widgets))),
        );

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

      final controller = SearchController();
      addTearDown(controller.dispose);
      final widgets = await _suggestionsAfterQuery(tester, controller, 'кор');
      await tester.pumpPeopleTagsWidget(
        _app(
          Scaffold(body: ListView(children: widgets)),
          locale: const Locale('ru'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('коробок'), findsOneWidget);
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
