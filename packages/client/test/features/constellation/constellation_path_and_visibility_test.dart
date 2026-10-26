import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/constellation_shown_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_visibility_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_visibility_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_text_view.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_visibility_bar.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_store_fixture.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../../support/people_tags_widget_harness.dart';

/// #641: selecting someone who is not a direct contact highlights the
/// shortest chain of visible trust and names it in the person panel.
/// #645: global show/hide switches for Requests, Posts and people by trust
/// degree, kept per viewer, applied to the map and the list alike.

const _ego = Profile(id: 'ego', displayName: 'Ego');
final _loadedAt = DateTime.utc(2026, 10, 22, 12);

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

final class _MemoryVisibilityPort implements ConstellationVisibilityPort {
  final stored = <String, ConstellationVisibility>{};
  final writes = <(String, ConstellationVisibility)>[];

  @override
  Future<ConstellationVisibility?> read({required String viewerId}) async =>
      stored[viewerId];

  @override
  Future<void> write({
    required String viewerId,
    required ConstellationVisibility visibility,
  }) async {
    writes.add((viewerId, visibility));
    stored[viewerId] = visibility;
  }
}

class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit() : super(const GraphPersonContextState());

  @override
  Stream<LazyWriteNotice> get lazyWriteNotices => const Stream.empty();

  @override
  Future<void> retryTrust([GraphTrustRevert? revert]) async {}

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {}

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  Future<void> untrustSelected() async {}

  @override
  void clearSelection() {}
}

ConstellationAnchor _anchor(ConstellationAnchorTarget target) =>
    ConstellationAnchor(
      target: target,
      position: const ConstellationAnchorPosition(
        xUnits: 1,
        yUnits: 1,
        coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
      ),
      revision: ConstellationAnchorRevision.zero,
      placedAt: DateTime.utc(2026, 10, 2),
    );

/// The viewer trusts Quiet and Ann; Ann trusts Bob (2nd degree), Bob trusts
/// Cid (3rd degree, pinned). Far authored a Request no visible trust leads
/// to.
ConstellationField _field() => ConstellationField(
  loadedAt: _loadedAt,
  context: '',
  peers: const [
    ConstellationPerson(id: 'quiet', displayName: 'Quiet'),
    ConstellationPerson(id: 'ann', displayName: 'Ann'),
    ConstellationPerson(id: 'bob', displayName: 'Bob'),
    ConstellationPerson(id: 'far', displayName: 'Far'),
  ],
  edges: const [
    ConstellationTrustEdgeEntity(src: 'ego', dst: 'quiet', tier: 1),
    ConstellationTrustEdgeEntity(src: 'ego', dst: 'ann', tier: 1),
    ConstellationTrustEdgeEntity(src: 'ann', dst: 'bob', tier: 1),
  ],
  requests: const [
    ConstellationRequest(
      id: 'req-ann',
      authorId: 'ann',
      title: 'Tools',
      status: 0,
    ),
    ConstellationRequest(
      id: 'req-bob',
      authorId: 'bob',
      title: 'Ride',
      status: 0,
    ),
    ConstellationRequest(
      id: 'req-far',
      authorId: 'far',
      title: 'Far away',
      status: 0,
    ),
  ],
  posts: [
    ConstellationPost(
      id: 'post-ann',
      authorId: 'ann',
      rootExcerpt: 'Who has a ladder?',
      lastActivityAt: _loadedAt.subtract(const Duration(hours: 1)),
    ),
  ],
  directContactIds: const ['ann', 'quiet'],
  anchorProjection: ConstellationAnchorProjection(
    revision: ConstellationAnchorRevision.zero,
    anchors: [_anchor(ConstellationAnchorTarget.person('cid'))],
    pinnedPeers: const [ConstellationPerson(id: 'cid', displayName: 'Cid')],
    pinnedRequests: const [],
    supportPeers: const [],
    supportEdges: const [
      ConstellationTrustEdgeEntity(src: 'bob', dst: 'cid', tier: 1),
    ],
    serverFilteredBeaconIds: const [],
    serverFilteredBeaconCount: 0,
  ),
);

ConstellationVisibilityCase _case(ConstellationVisibilityPort port) =>
    ConstellationVisibilityCase(
      port,
      env: const Env(),
      logger: Logger('test'),
    );

Future<ConstellationCubit> _loadCubit({
  ConstellationVisibilityPort? port,
  Profile viewer = _ego,
}) async {
  final cubit = ConstellationCubit(
    case_: ConstellationStoreFixture(
      _StubRepository(_field()),
      accountId: viewer.id,
    ).store,
    viewer: viewer,
    visibilityCase: port == null ? null : _case(port),
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  cubit.updateLabelBudgetContext(
    viewport: const Size(1200, 900),
    textScaleFactor: 1,
  );
  return cubit;
}

/// The drawn edge `src → dst` of [kind], whatever the node id prefixes.
String _edgeId(ConstellationCubit cubit, String src, String dst, String kind) =>
    cubit.edgeKindByPair.keys.singleWhere(
      (id) => RegExp('^[^:]+:$src->[^:]+:$dst#$kind\$').hasMatch(id),
    );

Set<String> _peopleIds(ConstellationCubit cubit) => {
  for (final person in cubit.fieldPeople) person.id,
};

Set<String> _mapNodeIds(ConstellationCubit cubit) => {
  for (final node in cubit.graphController.nodes) node.id,
};

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: TenturaResponsiveScope(child: child),
);

Future<void> _pumpBody(WidgetTester tester, ConstellationCubit cubit) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpPeopleTagsWidget(
    _app(
      MultiBlocProvider(
        providers: [
          BlocProvider<ConstellationCubit>.value(value: cubit),
          BlocProvider<GraphPersonContextCubit>(
            create: (_) => _StubContextCubit(),
          ),
          BlocProvider<ScreenCubit>(
            create: (_) => ScreenCubit(FakeUiEffectPort()),
          ),
        ],
        child: Scaffold(
          body: ConstellationBody(legendExpanded: false, onToggleLegend: () {}),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('trust chain (#641)', () {
    test('a 2nd-degree person is reached through the shown chain', () async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);

      cubit.selectPerson('bob');

      final chain = cubit.selectedTrustChain;
      expect(chain, isA<ConstellationTrustChainFound>());
      expect((chain! as ConstellationTrustChainFound).path, [
        'ego',
        'ann',
        'bob',
      ]);
    });

    test(
      'the chain dims everything off it but the person and their items',
      () async {
        final cubit = await _loadCubit();
        addTearDown(cubit.close);

        cubit.selectPerson('bob');

        final nodes = {for (final n in cubit.graphController.nodes) n.id: n};
        expect(cubit.isDimmedByTrustChain(nodes['quiet']!), isTrue);
        expect(cubit.isDimmedByTrustChain(nodes['req-ann']!), isTrue);
        for (final id in ['ego', 'ann', 'bob', 'req-bob']) {
          expect(cubit.isDimmedByTrustChain(nodes[id]!), isFalse, reason: id);
        }
      },
    );

    test('chain edges are drawn bright, every other edge fades', () async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);

      cubit.selectPerson('bob');

      final fades = cubit.edgeFadeBySemanticId;
      final chainUp = _edgeId(cubit, 'ego', 'ann', 'tier1Path');
      final chainDown = _edgeId(cubit, 'ann', 'bob', 'tier1Path');
      expect(fades[chainUp], isNull);
      expect(fades[chainDown], isNull);
      expect(fades[_edgeId(cubit, 'bob', 'req-bob', 'attachment')], isNull);
      expect(
        fades[_edgeId(cubit, 'ann', 'req-ann', 'attachment')],
        kConstellationTrustChainEdgeFade,
      );

      cubit.selectPerson(null);
      expect(cubit.edgeFadeBySemanticId, isEmpty);
    });

    test('a direct contact and an unreachable author get no chain', () async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);

      cubit.selectPerson('ann');
      expect(cubit.selectedTrustChain, isA<ConstellationTrustChainDirect>());

      cubit.selectPerson('far');
      expect(cubit.selectedTrustChain, isA<ConstellationTrustChainNone>());
      final nodes = {for (final n in cubit.graphController.nodes) n.id: n};
      // Nothing partial: no dimming without a chain.
      expect(cubit.isDimmedByTrustChain(nodes['quiet']!), isFalse);
      expect(cubit.edgeFadeBySemanticId, isEmpty);
    });

    testWidgets('the person panel names the intermediaries', (tester) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await _pumpBody(tester, cubit);

      cubit.selectPerson('cid');
      await tester.pump();

      expect(find.text('Through Ann → Bob'), findsOneWidget);
      final cidNode = find.byWidgetPredicate(
        (widget) =>
            widget is Opacity &&
            widget.opacity == kConstellationTrustChainDimOpacity,
      );
      expect(cidNode, findsWidgets);

      cubit.selectPerson('far');
      await tester.pump();
      expect(
        find.text('No chain of trust you can see leads to this person.'),
        findsOneWidget,
      );
    });
  });

  group('show/hide (#645)', () {
    test('hiding a degree hides those people and their items on map and '
        'list, a pinned person too', () async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      expect(_peopleIds(cubit), containsAll(['bob', 'cid']));

      cubit.setVisibility(
        const ConstellationVisibility(
          secondDegree: false,
          furtherDegrees: false,
        ),
      );

      expect(_peopleIds(cubit), {'ego', 'quiet', 'ann'});
      expect(_mapNodeIds(cubit), isNot(contains('bob')));
      expect(_mapNodeIds(cubit), isNot(contains('cid')));
      expect(_mapNodeIds(cubit), isNot(contains('req-bob')));
      expect(cubit.discoverableRequestsForPerson('bob'), isEmpty);
      // The pin itself is untouched.
      expect(
        cubit.state.field!.resolvedAnchorProjection.pinnedPeers.map(
          (p) => p.id,
        ),
        ['cid'],
      );

      cubit.setVisibility(ConstellationVisibility.all);
      expect(_mapNodeIds(cubit), containsAll(['bob', 'cid', 'req-bob']));
    });

    test('hiding Requests and Posts leaves the people', () async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);

      cubit.setVisibility(
        const ConstellationVisibility(requests: false, posts: false),
      );

      expect(
        _mapNodeIds(cubit).intersection({
          'req-ann',
          'req-bob',
          'req-far',
          'post-ann',
        }),
        isEmpty,
      );
      // Bob and Far are on the field only through their Requests; their
      // degrees stay shown, so they stay too.
      expect(
        _peopleIds(cubit),
        containsAll(['ego', 'quiet', 'ann', 'bob', 'far', 'cid']),
      );
      expect(_mapNodeIds(cubit), containsAll(['bob', 'far']));
      expect(cubit.discoverableRequestsForPerson('ann'), isEmpty);
      expect(cubit.postsForPerson('ann'), isEmpty);
    });

    test('a hidden intermediary breaks the chain', () async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);

      cubit
        ..setVisibility(const ConstellationVisibility(secondDegree: false))
        ..selectPerson('cid');

      expect(cubit.selectedTrustChain, isA<ConstellationTrustChainNone>());
      expect(cubit.hasHiddenLayers, isTrue);
    });

    test(
      'counts stay what the field holds while something is hidden',
      () async {
        final cubit = await _loadCubit();
        addTearDown(cubit.close);
        final before = cubit.visibilityCounts!;

        cubit.setVisibility(
          const ConstellationVisibility(requests: false, firstDegree: false),
        );

        final after = cubit.visibilityCounts!;
        expect(before.requests, 3);
        expect(before.posts, 1);
        expect(before.people, {
          ConstellationTrustDegree.first: 2,
          ConstellationTrustDegree.second: 1,
          ConstellationTrustDegree.further: 2,
        });
        expect(after.requests, before.requests);
        expect(after.posts, before.posts);
        expect(after.people, before.people);
      },
    );

    test(
      'counts follow the Request filters while something is hidden',
      () async {
        final cubit = await _loadCubit();
        addTearDown(cubit.close);
        cubit.setVisibility(const ConstellationVisibility(posts: false));

        final first = cubit.visibilityCounts;
        expect(identical(cubit.visibilityCounts, first), isTrue);

        cubit.setFilterLocation(LocationFilter.hasLocation);
        expect(identical(cubit.visibilityCounts, first), isFalse);
      },
    );

    test('the choice is kept per viewer and restored', () async {
      final port = _MemoryVisibilityPort();
      final first = await _loadCubit(port: port);
      first.setVisibility(const ConstellationVisibility(posts: false));
      await first.close();
      expect(port.writes.single, (
        'ego',
        const ConstellationVisibility(posts: false),
      ));

      final again = await _loadCubit(port: port);
      addTearDown(again.close);
      await pumpEventQueue();
      expect(
        again.state.visibility,
        const ConstellationVisibility(posts: false),
      );
      expect(_mapNodeIds(again), isNot(contains('post-ann')));

      final other = await _loadCubit(
        port: port,
        viewer: const Profile(id: 'other', displayName: 'Other'),
      );
      addTearDown(other.close);
      await pumpEventQueue();
      expect(other.state.visibility, ConstellationVisibility.all);
    });

    testWidgets('the chip row toggles the map and the list alike', (
      tester,
    ) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await _pumpBody(tester, cubit);

      expect(find.byType(ConstellationVisibilityBar), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('constellation.show.requests.count')),
            )
            .data,
        '3',
      );

      await tester.tap(find.byKey(const Key('constellation.show.requests')));
      await tester.pump();
      expect(cubit.state.visibility.requests, isFalse);
      expect(_mapNodeIds(cubit), isNot(contains('req-ann')));

      cubit.setViewMode(ConstellationViewMode.text);
      await tester.pumpAndSettle();
      expect(find.byType(ConstellationTextView), findsOneWidget);
      expect(find.byType(ConstellationVisibilityBar), findsOneWidget);
      expect(
        find.byKey(const Key('constellation.text.request.req-ann')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('constellation.text.post.post-ann')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('constellation.show.degree.first')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('constellation.text.person.ann')),
        findsNothing,
      );
      expect(_mapNodeIds(cubit), isNot(contains('ann')));
    });
  });
}
