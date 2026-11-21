import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field_search_result.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field_hidden_item.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field_target_kind.dart';
import 'package:tentura/features/constellation/domain/port/constellation_field_hide_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_field_search_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_hide_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_search_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/screen/constellation_screen.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_temporary_outline.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_person_search.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_visibility_bar.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/util/ui_utils.dart';

import '../../../integration_test/support/constellation_search_test_helpers.dart';
import '../../support/constellation_store_fixture.dart';
import '../../support/fake_people_tags_repository.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_case_builders.dart';
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
          ? buildTestFieldHideCase(
              hidePortForCase,
              fixture.store,
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
    ConstellationFieldSearchCase(port);

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

void _expectComposedSearchBeacon(ConstellationCubit cubit, String beaconId) {
  final composition = cubit.state.composition;
  expect(composition, isNotNull);
  expect(composition!.eligibleRequestIds.contains(beaconId), isTrue);
  expect(
    composition.beaconNodes.any((node) => node.id == beaconId),
    isTrue,
  );
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

const _hiddenRequestId = 'req-h';
const _hiddenPostId = 'post-h';

ConstellationFieldSearchRequestHit _hiddenBeaconHit({bool isPost = false}) =>
    ConstellationFieldSearchRequestHit(
      id: isPost ? _hiddenPostId : _hiddenRequestId,
      authorId: 'am',
      title: isPost ? 'Spare ladder' : 'Need boxes',
      status: 0,
      hidden: true,
      lastActivityAt: _loadedAt,
    );

final _hiddenPost = ConstellationPost(
  id: _hiddenPostId,
  authorId: 'am',
  rootExcerpt: 'Spare ladder',
  status: 0,
  lastActivityAt: _loadedAt,
);

ConstellationFieldSearchCase _hiddenItemSearchCase() => _searchCase(
  _QueryKeyedFakeSearchPort({
    'boxes': ConstellationFieldSearchResult(requests: [_hiddenBeaconHit()]),
    'ladder': ConstellationFieldSearchResult(
      posts: [
        ConstellationFieldSearchPostHit(
          id: _hiddenPostId,
          authorId: 'am',
          rootExcerpt: _hiddenPost.rootExcerpt,
          status: 0,
          hidden: true,
          lastActivityAt: _hiddenPost.lastActivityAt,
        ),
      ],
    ),
  }),
);

void _expectAbsentFromLoadedField(ConstellationCubit cubit, String id) {
  final field = cubit.state.field!;
  final projection = field.resolvedAnchorProjection;
  expect(field.requests.map((request) => request.id), isNot(contains(id)));
  expect(field.posts.map((post) => post.id), isNot(contains(id)));
  expect(
    projection.pinnedRequests.map((request) => request.id),
    isNot(contains(id)),
  );
  expect(
    projection.anchors.map((anchor) => anchor.target.id),
    isNot(contains(id)),
  );
  expect(cubit.graphController.getPositionOrNullForId('fr:$id'), isNull);
}

Future<void> _parkCameraInEmptyCorner(
  WidgetTester tester,
  ConstellationCubit cubit,
  Offset corner,
) async {
  final graph = cubit.graphController;
  final beforeZoom = graph.cameraScale;
  expect(graph.getPositionOrNullForId('fp:am'), isNotNull);
  graph.zoomBy(1.5 / beforeZoom);
  graph.jumpToPosition(corner);
  await tester.pumpAndSettle();
  final viewport = Offset.zero & graph.viewportSize!;
  expect(graph.cameraScale, closeTo(1.5, 0.01));
  expect(
    (graph.viewportLocalToScene(viewport.center) - corner).distance,
    lessThan(1),
  );
  for (final id in graph.renderSnapshot.topology.nodesById.keys) {
    final at = graph.getPositionOrNullForId(id);
    if (at != null) {
      expect(
        viewport.inflate(100).contains(graph.sceneToViewportLocal(at)),
        isFalse,
        reason: '$id should be far from the starting viewport',
      );
    }
  }
}

Finder _hiddenNode(String id) => find.byKey(TestIds.key(TestIds.graphNode(id)));

Finder _dashedOutline(String id) => find.byWidgetPredicate(
  (widget) =>
      widget is ConstellationTemporaryOutline &&
      widget.key == TestIds.key(TestIds.constellationTemporaryOutline(id)),
);

final _showAgain = find.byKey(TestIds.key(TestIds.constellationShowAgain));
final _unavailable = find.byKey(
  const Key('constellation.selection_unavailable'),
);

Future<void> _settleSearchCamera(WidgetTester tester) async {
  // Allow a layout job followed by a camera update, even if no frame is
  // scheduled between the two. A missing placement must fail the assertion.
  for (var frame = 0; frame < 20; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

Future<({EdgeInsets insets, Offset start})> _pickSearchHitFromEmptyCorner(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required String query,
  required String kind,
  required String id,
  required Offset corner,
}) async {
  await _searchInOpenOverlay(tester, query);
  final hit = find.byKey(Key('constellation.field_search.$kind.$id'));
  expect(hit.hitTestable(), findsOneWidget);
  await _parkCameraInEmptyCorner(tester, cubit, corner);
  final graph = cubit.graphController;
  final insets = fieldSearchPickInsets(cubit, tester.element(hit));
  final safe = insets.deflateRect(Offset.zero & graph.viewportSize!);
  expect(safe.isEmpty, isFalse);
  final start = graph.viewportLocalToScene(safe.center);
  await tester.tap(hit);
  await _settleSearchCamera(tester);
  return (insets: insets, start: start);
}

List<String> _hiddenBeaconDrawingMismatches(String id) => [
  if (_hiddenNode(id).evaluate().length != 1) '$id has no rendered map node',
  if (_dashedOutline(id).evaluate().length != 1) '$id has no dashed outline',
];

void _hiddenItemsOnTheFieldTests() {
  group('Finding hidden items on the Field', () {
    testWidgets(
      'centres on the hidden Request on each pick from an empty corner',
      (
        tester,
      ) async {
        final cubit = await _loadCubit(
          field: _emptyFieldBase(),
          hidePortForCase: _RecordingHidePort(),
        );
        addTearDown(cubit.close);
        await _pumpFieldMapScreen(
          tester,
          cubit,
          locale: const Locale('en'),
          size: const Size(1280, 800),
        );
        _expectAbsentFromLoadedField(cubit, _hiddenRequestId);
        const insets = EdgeInsets.fromLTRB(24, 48, 84, 72);
        final errors = <String>[];
        for (final corner in [
          const Offset(2000, 2000),
          const Offset(14000, 14000),
        ]) {
          await _parkCameraInEmptyCorner(tester, cubit, corner);
          final graph = cubit.graphController;
          final safe = insets.deflateRect(Offset.zero & graph.viewportSize!);
          final start = graph.viewportLocalToScene(safe.center);
          cubit.pickFieldSearchBeacon(
            hit: _hiddenBeaconHit(),
            insets: insets,
            isPost: false,
          );
          await _settleSearchCamera(tester);
          expect(cubit.state.selectedRequestId, _hiddenRequestId);
          expect(
            cubit.isSearchTemporaryOutlineBeacon(_hiddenRequestId),
            isTrue,
          );
          expect(_showAgain.hitTestable(), findsOneWidget);
          expect(_unavailable, findsNothing);
          if (_hiddenNode(_hiddenRequestId).evaluate().length != 1 ||
              _dashedOutline(_hiddenRequestId).evaluate().length != 1) {
            errors.add(
              'Picking from $corner: the Request map node or its dashed outline is missing',
            );
          }
          for (final failure in fieldSearchCameraMismatches(
            cubit,
            _hiddenRequestId,
            insets,
            start,
          )) {
            errors.add('Picking from $corner: $failure');
          }
        }
        expect(errors, isEmpty);
      },
    );

    testWidgets('reopening search and picking the same hidden Request '
        'centres it from a second empty corner', (tester) async {
      final cubit = await _loadCubit(
        field: _emptyFieldBase(),
        searchCase: _hiddenItemSearchCase(),
        hidePortForCase: _RecordingHidePort(),
      );
      addTearDown(cubit.close);
      await _pumpFieldMapScreen(
        tester,
        cubit,
        locale: const Locale('en'),
        size: const Size(1280, 800),
      );
      _expectAbsentFromLoadedField(cubit, _hiddenRequestId);
      final errors = <String>[];
      for (final corner in [
        const Offset(2000, 2000),
        const Offset(14000, 14000),
      ]) {
        final pick = await _pickSearchHitFromEmptyCorner(
          tester,
          cubit,
          query: 'boxes',
          kind: 'request',
          id: _hiddenRequestId,
          corner: corner,
        );
        expect(
          find.byKey(const Key('constellation.field_search.request.req-h')),
          findsNothing,
        );
        expect(cubit.state.selectedRequestId, _hiddenRequestId);
        for (final failure in fieldSearchCameraMismatches(
          cubit,
          _hiddenRequestId,
          pick.insets,
          pick.start,
        )) {
          errors.add('Picking the Request result from $corner: $failure');
        }
      }
      expect(errors, isEmpty);
    });

    for (final (locale, label) in [
      (const Locale('ru'), 'Показать снова'),
      (const Locale('en'), 'Show again'),
    ]) {
      testWidgets('frames both hidden item types with reachable actions '
          'on a 375×667 ${locale.languageCode} phone', (tester) async {
        // The suggestions are a Navigator route above the Field's MediaQuery.
        tester.view.physicalSize = kPhoneSurface * tester.view.devicePixelRatio;
        addTearDown(tester.view.resetPhysicalSize);
        final cubit = await _loadCubit(
          field: _emptyFieldBase(),
          searchCase: _hiddenItemSearchCase(),
          hidePortForCase: _RecordingHidePort(),
        );
        addTearDown(cubit.close);
        await _pumpFieldMapScreen(tester, cubit, locale: locale);
        final bodyContext = tester.element(find.byType(ConstellationBody));
        expect(MediaQuery.sizeOf(bodyContext), kPhoneSurface);
        expect(Localizations.localeOf(bodyContext), locale);
        final errors = <String>[];
        for (final (id, kind, query, corner) in [
          (_hiddenRequestId, 'request', 'boxes', const Offset(2000, 2000)),
          (_hiddenPostId, 'post', 'ladder', const Offset(14000, 14000)),
        ]) {
          _expectAbsentFromLoadedField(cubit, id);
          await _searchInOpenOverlay(tester, query);
          final hit = find.byKey(Key('constellation.field_search.$kind.$id'));
          expect(hit.hitTestable(), findsOneWidget);
          expect(MediaQuery.sizeOf(tester.element(hit)), kPhoneSurface);
          await _parkCameraInEmptyCorner(tester, cubit, corner);
          final graph = cubit.graphController;
          final insets = fieldSearchPickInsets(cubit, tester.element(hit));
          final safe = insets.deflateRect(Offset.zero & graph.viewportSize!);
          expect(safe.isEmpty, isFalse);
          final before = graph.viewportLocalToScene(safe.center);
          await tester.tap(hit);
          await _settleSearchCamera(tester);
          expect(cubit.state.selectedRequestId, id);
          expect(cubit.isSearchTemporaryOutlineBeacon(id), isTrue);
          expect(_unavailable, findsNothing);
          await tester.ensureVisible(_showAgain);
          await tester.pumpAndSettle();
          expect(_showAgain.hitTestable(), findsOneWidget);
          expect(
            find.descendant(of: _showAgain, matching: find.text(label)),
            findsOneWidget,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$kind fits the phone',
          );
          if (_hiddenNode(id).evaluate().isEmpty ||
              _dashedOutline(id).evaluate().isEmpty) {
            errors.add(
              '$id is missing its rendered map node or dashed outline',
            );
          }
          errors.addAll(
            fieldSearchCameraMismatches(
              cubit,
              id,
              // The first pick opens the sheet after the tap. Check the
              // final map against the insets of the measured sheet.
              cubit.fieldCameraViewportSnapshotForTest,
              before,
              postAuthorId: kind == 'post' ? 'am' : null,
            ),
          );
        }
        expect(errors, isEmpty);
      });
    }

    testWidgets(
      'picks Request and Post results over the Field magnet menu button',
      (
        tester,
      ) async {
        const tag = PersonTag(
          id: 'supplies',
          name: 'Supplies',
          glyph: 'S',
          color: 0,
          ord: 1,
        );
        final tags = await PeopleTagsTestRig.create(
          FakePeopleTagsRepository(tagList: const [tag]),
        );
        GetIt.I.registerSingleton<PeopleTagsCase>(tags.peopleTags);
        addTearDown(() async {
          await GetIt.I.unregister<PeopleTagsCase>();
          await tags.dispose();
        });

        const window = Size(1280, 800);
        tester.view.physicalSize = window * tester.view.devicePixelRatio;
        addTearDown(tester.view.resetPhysicalSize);
        final cubit = await _loadCubit(
          field: _emptyFieldBase(),
          searchCase: _hiddenItemSearchCase(),
        );
        addTearDown(cubit.close);
        await _pumpFieldMapScreen(
          tester,
          cubit,
          locale: const Locale('en'),
          size: window,
        );
        final graph = cubit.graphController;
        final viewport = Offset.zero & graph.viewportSize!;
        cubit.placeTagMagnet(
          tagId: tag.id,
          position: graph.viewportLocalToScene(viewport.center),
          tagsOfPerson: tags.peopleTags.tagsOfPerson,
        );
        await tester.pumpAndSettle();
        final magnetMenu = find.byType(PopupMenuItem<bool>);
        // With no search overlay, the button really does open the magnet menu.
        expect(fieldSearchMagnetMenuButton.hitTestable(), findsOneWidget);
        await tester.tap(fieldSearchMagnetMenuButton);
        await tester.pumpAndSettle();
        expect(magnetMenu, findsOneWidget);
        Navigator.of(tester.element(magnetMenu)).pop();
        await tester.pumpAndSettle();

        final errors = <String>[];
        for (final (id, kind, query) in [
          (_hiddenRequestId, 'request', 'boxes'),
          (_hiddenPostId, 'post', 'ladder'),
        ]) {
          await _searchInOpenOverlay(tester, query);
          await tester.pumpAndSettle();
          final hit = find.byKey(Key('constellation.field_search.$kind.$id'));
          expect(hit.hitTestable(), findsOneWidget);
          final insets = fieldSearchPickInsets(cubit, tester.element(hit));
          final point = await positionMagnetBehindSearchResult(
            tester,
            cubit,
            hit,
          );
          final before = graph.viewportLocalToScene(
            insets.deflateRect(viewport).center,
          );
          await tester.tapAt(point, kind: PointerDeviceKind.mouse);
          await _settleSearchCamera(tester);
          expect(cubit.state.selectedRequestId, id);
          expect(
            magnetMenu,
            findsNothing,
            reason: 'the $kind result kept the tap',
          );
          errors.addAll(
            fieldSearchCameraMismatches(
              cubit,
              id,
              insets,
              before,
              postAuthorId: kind == 'post' ? 'am' : null,
            ),
          );
        }
        expect(errors, isEmpty);
      },
    );

    testWidgets('clearing search ends the hidden item selection', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        field: _emptyFieldBase(),
        searchCase: _hiddenItemSearchCase(),
      );
      addTearDown(cubit.close);
      await _pumpFieldMapScreen(tester, cubit);
      await _pickHiddenSearchHit(
        tester,
        query: 'ladder',
        hitKey: 'constellation.field_search.post.post-h',
      );
      expect(cubit.state.selectedRequestId, _hiddenPostId);
      expect(cubit.isSearchTemporaryOutlineBeacon(_hiddenPostId), isTrue);
      expect(cubit.isSearchRevealedHiddenBeacon(_hiddenPostId), isTrue);
      expect(cubit.postById(_hiddenPostId), isNotNull);
      expect(_hiddenNode(_hiddenPostId), findsOneWidget);
      await _searchInOpenOverlay(tester, 'ladder');
      final clear = find.byTooltip(
        MaterialLocalizations.of(
          tester.element(find.byType(TextField).last),
        ).clearButtonTooltip,
      );
      expect(clear.hitTestable(), findsOneWidget);
      await tester.tap(clear);
      await _settleSearchCamera(tester);
      final input = find.descendant(
        of: find.byType(SearchBar),
        matching: find.byType(TextField),
      );
      if (input.evaluate().isNotEmpty) {
        expect(tester.widget<TextField>(input).controller!.text, isEmpty);
        // Close the suggestions so the following assertion sees the map.
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      }
      final remainingPick = (
        selected: cubit.state.selectedRequestId,
        dashed: cubit.isSearchTemporaryOutlineBeacon(_hiddenPostId),
        revealed: cubit.isSearchRevealedHiddenBeacon(_hiddenPostId),
        injected: cubit.postById(_hiddenPostId) != null,
        onMap: _hiddenNode(_hiddenPostId).evaluate().isNotEmpty,
      );
      expect(remainingPick, (
        selected: null,
        dashed: false,
        revealed: false,
        injected: false,
        onMap: false,
      ));
    });

    testWidgets(
      'centres on the dashed hidden Post and restores it on Show again '
      'while the Requests count stays at 31',
      (tester) async {
        final visibleField = _emptyFieldBase().copyWith(
          requests: [
            for (var i = 0; i < 31; i++)
              ConstellationRequest(
                id: 'box-request-$i',
                authorId: 'ego',
                title: 'Boxes $i',
                status: 0,
                lastActivityAt: _loadedAt,
              ),
          ],
          posts: [_hiddenPost],
        );
        final repo = _MutableFieldRepository(visibleField);
        final hidePort = _RecordingHidePort();
        final cubit = await _loadCubit(
          field: repo.field,
          repositoryOverride: repo,
          searchCase: _hiddenItemSearchCase(),
          hidePortForCase: hidePort,
        );
        addTearDown(cubit.close);
        await _pumpFieldMapScreen(
          tester,
          cubit,
          locale: const Locale('en'),
          size: const Size(1280, 800),
        );
        final count = find.byKey(
          const Key('constellation.show.requests.count'),
        );
        void expectRequestCount() =>
            expect(tester.widget<Text>(count).data, '31');
        expectRequestCount();
        cubit.selectRequest(_hiddenPostId);
        await tester.pumpAndSettle();
        final hide = find.byKey(
          TestIds.key(TestIds.constellationHideFromField),
        );
        await tester.ensureVisible(hide);
        await tester.tap(hide);
        await tester.pumpAndSettle();
        repo.field = visibleField.copyWith(posts: []);
        _expectAbsentFromLoadedField(cubit, _hiddenPostId);
        expectRequestCount();
        await _parkCameraInEmptyCorner(tester, cubit, const Offset(2000, 2000));
        const insets = EdgeInsets.fromLTRB(24, 48, 84, 72);
        final graph = cubit.graphController;
        final safe = insets.deflateRect(Offset.zero & graph.viewportSize!);
        final start = graph.viewportLocalToScene(safe.center);
        cubit.pickFieldSearchBeacon(
          hit: _hiddenBeaconHit(isPost: true),
          insets: insets,
          isPost: true,
        );
        await _settleSearchCamera(tester);
        expect(cubit.state.selectedRequestId, _hiddenPostId);
        final cameraErrors = fieldSearchCameraMismatches(
          cubit,
          _hiddenPostId,
          insets,
          start,
          postAuthorId: 'am',
        );
        expectRequestCount();
        expect(cubit.isSearchTemporaryOutlineBeacon(_hiddenPostId), isTrue);
        expect(_dashedOutline(_hiddenPostId), findsOneWidget);
        cubit.selectRequest(null);
        await _settleSearchCamera(tester);
        _expectAbsentFromLoadedField(cubit, _hiddenPostId);
        expect(cubit.state.selectedRequestId, isNull);

        final rowPick = await _pickSearchHitFromEmptyCorner(
          tester,
          cubit,
          query: 'ladder',
          kind: 'post',
          id: _hiddenPostId,
          corner: const Offset(14000, 14000),
        );
        expect(cubit.state.selectedRequestId, _hiddenPostId);
        expectRequestCount();
        cameraErrors.addAll(
          fieldSearchCameraMismatches(
            cubit,
            _hiddenPostId,
            rowPick.insets,
            rowPick.start,
            postAuthorId: 'am',
          ),
        );
        expect(cubit.isSearchTemporaryOutlineBeacon(_hiddenPostId), isTrue);
        final outlineBefore = _dashedOutline(_hiddenPostId).evaluate().length;
        await tester.ensureVisible(_showAgain);
        expect(_showAgain.hitTestable(), findsOneWidget);
        repo.field = visibleField;
        await tester.tap(_showAgain);
        await _settleSearchCamera(tester);
        expect(hidePort.unhideCalls, [
          (
            targetKind: ConstellationFieldTargetKind.post.wireValue,
            targetId: _hiddenPostId,
          ),
        ]);
        expect(
          cubit.state.field!.posts.map((post) => post.id),
          contains(_hiddenPostId),
        );
        expect(cubit.isSearchTemporaryOutlineBeacon(_hiddenPostId), isFalse);
        expect(_dashedOutline(_hiddenPostId), findsNothing);
        expectRequestCount();
        expect(
          outlineBefore,
          1,
          reason: 'the temporarily revealed Post was drawn dashed',
        );
        expect(cameraErrors, isEmpty);
      },
    );
  });
}

void main() {
  _hiddenItemsOnTheFieldTests();

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
      'frames and restores the dashed hidden Request from search on a Russian phone',
      (tester) async {
        tester.view.physicalSize = kPhoneSurface * tester.view.devicePixelRatio;
        addTearDown(tester.view.resetPhysicalSize);
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

        final pick = await _pickSearchHitFromEmptyCorner(
          tester,
          cubit,
          query: '1137',
          kind: 'request',
          id: requestId,
          corner: const Offset(2000, 2000),
        );

        expect(
          find.byKey(const Key('constellation.selection_unavailable')),
          findsNothing,
        );
        expect(cubit.state.selectedRequestId, requestId);
        expect(cubit.isSearchTemporaryOutlineBeacon(requestId), isTrue);
        _expectComposedSearchBeacon(cubit, requestId);
        final revealErrors = [
          ..._hiddenBeaconDrawingMismatches(requestId),
          ...fieldSearchCameraMismatches(
            cubit,
            requestId,
            cubit.fieldCameraViewportSnapshotForTest,
            pick.start,
          ),
        ];
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
        expect(revealErrors, isEmpty);
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
      'frames and restores the dashed hidden Post from search on a Russian phone',
      (tester) async {
        tester.view.physicalSize = kPhoneSurface * tester.view.devicePixelRatio;
        addTearDown(tester.view.resetPhysicalSize);
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

        final pick = await _pickSearchHitFromEmptyCorner(
          tester,
          cubit,
          query: '1137',
          kind: 'post',
          id: postId,
          corner: const Offset(2000, 2000),
        );

        expect(
          find.byKey(const Key('constellation.selection_unavailable')),
          findsNothing,
        );
        expect(cubit.state.selectedRequestId, postId);
        expect(cubit.isPostId(postId), isTrue);
        _expectComposedSearchBeacon(cubit, postId);
        expect(cubit.isSearchTemporaryOutlineBeacon(postId), isTrue);
        final revealErrors = [
          ..._hiddenBeaconDrawingMismatches(postId),
          ...fieldSearchCameraMismatches(
            cubit,
            postId,
            cubit.fieldCameraViewportSnapshotForTest,
            pick.start,
            postAuthorId: 'am',
          ),
        ];
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
        expect(revealErrors, isEmpty);
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
