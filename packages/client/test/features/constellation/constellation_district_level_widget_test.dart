import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_tag_lens_cubit.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_zoom_level_controller.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/fake_people_tags_repository.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_reference_fixture.dart';

// Colour index 4 for the first own tag, 6 for the second: a person in both
// must take the first (by tag order), never the second.
const _first = PersonTag(
  id: 'T-first',
  name: 'First',
  glyph: 'F',
  color: 4,
  ord: 0,
);
const _second = PersonTag(
  id: 'T-second',
  name: 'Second',
  glyph: 'S',
  color: 6,
  ord: 1,
);

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

/// A person on the test field: [depth] trust hops from the viewer (the trust
/// path decides how near a person is), [pinned] by an anchor.
final class _Person {
  const _Person(
    this.id, {
    this.name,
    this.depth = 1,
    this.pinned = false,
  });

  final String id;
  final String? name;
  final int depth;
  final bool pinned;
}

/// Everyone in [people] is a direct contact so all of them are drawn. A
/// person at depth 2 or 3 hangs off a hidden-name relay at the depth before
/// it (`relay1`, `relay2`), which the field adds on its own.
ConstellationField _field(List<_Person> people) {
  final relays = [
    for (final depth in [1, 2])
      if (people.any((p) => p.depth > depth)) 'relay$depth',
  ];
  final peers = [
    for (final p in people)
      ConstellationPerson(id: p.id, displayName: p.name ?? 'Person ${p.id}'),
    for (final relay in relays)
      ConstellationPerson(id: relay, displayName: 'Relay $relay'),
  ];
  String parentOf(_Person p) => p.depth <= 1 ? 'ego' : 'relay${p.depth - 1}';
  final edges = [
    for (final p in people)
      ConstellationTrustEdgeEntity(src: parentOf(p), dst: p.id, tier: 1),
    for (final relay in relays)
      ConstellationTrustEdgeEntity(
        src: relay == 'relay1' ? 'ego' : 'relay1',
        dst: relay,
        tier: 1,
      ),
  ];
  final revision = ConstellationAnchorRevision(BigInt.one);
  final pinned = [
    for (final p in people)
      if (p.pinned) peers.firstWhere((peer) => peer.id == p.id),
  ];
  return ConstellationField(
    loadedAt: DateTime.utc(2026, 10, 25),
    context: '',
    peers: peers,
    directContactIds: [for (final p in peers) p.id],
    edges: edges,
    anchorProjection: ConstellationAnchorProjection(
      revision: revision,
      anchors: [
        for (final p in pinned)
          ConstellationAnchor(
            target: ConstellationAnchorTarget.person(p.id),
            position: const ConstellationAnchorPosition(
              xUnits: 1,
              yUnits: 1,
              coordinateSpaceVersion: 1,
            ),
            revision: revision,
            placedAt: DateTime.utc(2026, 10, 25),
          ),
      ],
      pinnedPeers: pinned,
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

Finder _graphNode(String id) => find.byKey(TestIds.key(TestIds.graphNode(id)));

/// The on-screen rect of a widget (its corners mapped through the camera).
Rect _screenRect(WidgetTester tester, Finder finder) =>
    Rect.fromPoints(tester.getTopLeft(finder), tester.getBottomRight(finder));

/// The colour of a circular outline a widget draws (a border, not a fill).
Color? _outlineColour(Widget w) {
  Color? ofDecoration(Decoration? d) => switch (d) {
    BoxDecoration(:final border?, shape: BoxShape.circle)
        when border.isUniform && border.top.style != BorderStyle.none =>
      border.top.color,
    ShapeDecoration(:final shape)
        when shape is CircleBorder && shape.side.style != BorderStyle.none =>
      shape.side.color,
    _ => null,
  };
  return switch (w) {
    DecoratedBox(:final decoration) => ofDecoration(decoration),
    Container(:final decoration) => ofDecoration(decoration),
    Material(:final shape)
        when shape is CircleBorder && shape.side.style != BorderStyle.none =>
      shape.side.color,
    _ => null,
  };
}

/// Circular outlines in [colour] drawn inside one node, as wide as the 20 pt
/// circle they ring (a tag-coloured fill or a small glyph is not a ring).
Finder _ringIn(String id, Color colour) => find.descendant(
  of: _graphNode(id),
  matching: find.byWidgetPredicate((w) {
    if (_outlineColour(w) != colour) return false;
    final element = find.byWidget(w).evaluate().first;
    final box = element.renderObject;
    if (box is! RenderBox) return false;
    final extent =
        box.localToGlobal(box.size.bottomRight(Offset.zero)) -
        box.localToGlobal(Offset.zero);
    return extent.dx >= 16 && extent.dx <= 26 && extent.dy >= 16;
  }),
);

void main() {
  late PeopleTagsTestRig rig;
  late ConstellationTagLensCubit lens;

  setUp(() async {
    rig = await PeopleTagsTestRig.create(
      FakePeopleTagsRepository(
        tagList: [_first, _second],
        memberList: const [
          PersonTagMembers(
            tagId: 'T-first',
            personIds: [
              'alice',
              'bob',
              'aa-tagged',
              'aa-tag1',
              'aa-tag2',
              'aa-tag3',
            ],
          ),
          PersonTagMembers(tagId: 'T-second', personIds: ['bob', 'cara']),
        ],
      ),
    );
    GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
    lens = ConstellationTagLensCubit(ownTagIdsOf: rig.peopleTags.tagsOfPerson);
  });

  tearDown(() async {
    await lens.close();
    await GetIt.I.reset();
    await rig.dispose();
  });

  /// Mounts the Field of [people], puts each at its screen position in
  /// [at] (the viewer included, under `ego`) and settles at camera [scale].
  Future<
    ({
      ConstellationCubit cubit,
      ConstellationPresentationFrameHolder holder,
    })
  >
  mount(
    WidgetTester tester,
    List<_Person> people, {
    required Map<String, Offset> at,
    double scale = 0.6,
    String? selectedId,
  }) async {
    final cubit = await loadReferenceCubit(field: _field(people));
    final zoom = ConstellationZoomLevelController();
    final holder = ConstellationPresentationFrameHolder();
    addTearDown(() async {
      await cubit.close();
      zoom.dispose();
    });
    const size = Size(1200, 900);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              RepositoryProvider<ConstellationZoomLevelController>.value(
                value: zoom,
              ),
              BlocProvider<ConstellationCubit>.value(value: cubit),
              BlocProvider<ConstellationTagLensCubit>.value(value: lens),
              BlocProvider<GraphPersonContextCubit>(
                create: (_) => _StubContextCubit(),
              ),
              BlocProvider<ScreenCubit>(
                create: (_) => ScreenCubit(FakeUiEffectPort()),
              ),
            ],
            child: ConstellationBody(
              legendExpanded: false,
              onToggleLegend: () {},
              presentationFrameHolder: holder,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    cubit.graphController.zoomBy(scale / cubit.graphController.cameraScale);
    await tester.pumpAndSettle();
    if (selectedId != null) {
      cubit.selectPerson(selectedId);
      await tester.pumpAndSettle();
    }
    // Presentation overrides put every node at an exact screen position
    // whatever the layout chose.
    final controller = cubit.graphController..clearAllPresentationPositions();
    for (final entry in at.entries) {
      controller.beginNodePresentationDragForId(
        'fp:${entry.key}',
        controller.viewportLocalToScene(entry.value),
      );
    }
    await tester.pumpAndSettle();
    expect(holder.frame!.detail, ConstellationDetailLevel.district);
    return (cubit: cubit, holder: holder);
  }

  group('district markers', () {
    const people = [
      _Person('alice', name: 'Alice Brown'),
      _Person('bob', name: 'Bob Stone'),
      _Person('cara', name: 'Cara Vale'),
      _Person('dan', name: 'Dan Reed'),
    ];
    const at = {
      'ego': Offset(600, 700),
      'alice': Offset(300, 300),
      'bob': Offset(500, 300),
      'cara': Offset(700, 300),
      'dan': Offset(900, 300),
    };

    for (final scale in [0.6, 0.8]) {
      testWidgets('draw people as 20 pt circles at scale $scale', (
        tester,
      ) async {
        final (:holder, cubit: _) = await mount(
          tester,
          people,
          at: at,
          scale: scale,
        );

        for (final p in people) {
          final body = holder.frame!.bodies['fp:${p.id}']!;
          expect(body.width, closeTo(20, 0.01), reason: p.id);
          expect(body.height, closeTo(20, 0.01), reason: p.id);
          final onScreen =
              tester.getBottomRight(_graphNode(p.id)) -
              tester.getTopLeft(_graphNode(p.id));
          expect(onScreen.dx, closeTo(20, 0.5), reason: '${p.id} node width');
          expect(onScreen.dy, closeTo(20, 0.5), reason: '${p.id} node height');
        }
      });
    }

    testWidgets(
      'show the initials of a person with no photo inside the 20 pt circle',
      (tester) async {
        await mount(tester, people, at: at);

        for (final (id, initials) in [
          ('alice', 'AB'),
          ('bob', 'BS'),
          ('cara', 'CV'),
          ('dan', 'DR'),
        ]) {
          final text = find.descendant(
            of: _graphNode(id),
            matching: find.text(initials),
          );
          expect(text, findsOneWidget, reason: id);
          final circle = _screenRect(tester, _graphNode(id));
          expect(circle.width, closeTo(20, 0.5), reason: '$id circle width');
          expect(circle.height, closeTo(20, 0.5), reason: '$id circle height');
          final lettering = _screenRect(tester, text);
          expect(
            circle.inflate(0.5).contains(lettering.topLeft) &&
                circle.inflate(0.5).contains(lettering.bottomRight),
            isTrue,
            reason: '$id initials $lettering lie inside its circle $circle',
          );
        }
      },
    );

    testWidgets('ring a person in the colour of their first own tag', (
      tester,
    ) async {
      await mount(tester, people, at: at);
      const palette = TenturaTagColors.light;
      final firstAccent = palette.swatches[_first.color].accent;
      final secondAccent = palette.swatches[_second.color].accent;

      expect(_ringIn('alice', firstAccent), findsWidgets);
      expect(_ringIn('alice', secondAccent), findsNothing);
      // In both tags: the first, never the second.
      expect(_ringIn('bob', firstAccent), findsWidgets);
      expect(_ringIn('bob', secondAccent), findsNothing);
      expect(_ringIn('cara', secondAccent), findsWidgets);
      expect(_ringIn('cara', firstAccent), findsNothing);
    });

    testWidgets('give a person with no tag no tag-coloured ring', (
      tester,
    ) async {
      await mount(tester, people, at: at);

      for (final swatch in TenturaTagColors.light.swatches) {
        expect(_ringIn('dan', swatch.accent), findsNothing);
      }
    });
  });

  group('district label budget', () {
    // Everyone in the crowd shares one screen point, so only the few names
    // that fit around that point get a label.
    const crowdPoint = Offset(600, 300);
    const relayPoints = {
      'relay1': Offset(150, 700),
      'relay2': Offset(300, 700),
    };

    /// Mounts [crowd] on one point and returns the ids that got a name.
    Future<Set<String>> namedIn(
      WidgetTester tester,
      List<_Person> crowd, {
      String? selectedId,
      Set<String> selectedTagMembers = const {},
    }) async {
      if (selectedTagMembers.isNotEmpty) {
        lens.toggleOwn(_first.id);
      }
      final (:holder, cubit: _) = await mount(
        tester,
        crowd,
        at: {
          'ego': const Offset(1000, 800),
          for (final p in crowd) p.id: crowdPoint,
          for (final entry in relayPoints.entries)
            if (crowd.any((p) => p.depth > int.parse(entry.key[5])))
              entry.key: entry.value,
        },
        selectedId: selectedId,
      );
      return {
        for (final p in crowd)
          if (holder.frame!.labels.containsKey('fp:${p.id}')) p.id,
      };
    }

    /// The names go to the crowd best tier first: tiers are filled in order,
    /// a tier in full before the next gets any (which of the people inside one
    /// tier is named when it does not fit whole is left open). The budget must
    /// be tight, or the order would not matter.
    void expectNamedTierByTier(
      Set<String> named,
      List<Set<String>> tiers,
    ) {
      final everyone = tiers.expand((tier) => tier).toSet();
      expect(named, isNotEmpty);
      expect(
        named.length,
        lessThan(everyone.length),
        reason: 'the budget must be tight for the order to matter',
      );
      var left = named.length;
      for (var i = 0; i < tiers.length; i++) {
        final inTier = tiers[i].where(named.contains).length;
        expect(
          inTier,
          left < tiers[i].length ? left : tiers[i].length,
          reason: 'tier $i ${tiers[i]} gets the names first; named=$named',
        );
        left -= inTier;
      }
    }

    testWidgets('name the selected person before pinned people', (
      tester,
    ) async {
      final named = await namedIn(
        tester,
        const [
          _Person('selected', depth: 3),
          _Person('pin1', pinned: true),
          _Person('pin2', pinned: true),
          _Person('pin3', pinned: true),
          _Person('pin4', pinned: true),
          _Person('pin5', pinned: true),
        ],
        selectedId: 'selected',
      );

      expectNamedTierByTier(named, [
        {'selected'},
        {'pin1', 'pin2', 'pin3', 'pin4', 'pin5'},
      ]);
    });

    testWidgets(
      'name the selected person before nearer people of the selected tag',
      (tester) async {
        final named = await namedIn(
          tester,
          const [
            _Person('selected', depth: 3),
            _Person('aa-tag1'),
            _Person('aa-tag2'),
            _Person('aa-tag3'),
          ],
          selectedId: 'selected',
          selectedTagMembers: {'aa-tag1'},
        );

        expectNamedTierByTier(named, [
          {'selected'},
          {'aa-tag1', 'aa-tag2', 'aa-tag3'},
        ]);
      },
    );

    testWidgets(
      'name a far pinned person before unpinned people nearer by path',
      (
        tester,
      ) async {
        final named = await namedIn(tester, const [
          _Person('far-pin', depth: 3, pinned: true),
          _Person('near1'),
          _Person('near2'),
          _Person('near3'),
          _Person('near4'),
          _Person('near5'),
        ]);

        expectNamedTierByTier(named, [
          {'far-pin'},
          {'near1', 'near2', 'near3', 'near4', 'near5'},
        ]);
      },
    );

    testWidgets('name pinned people before people of the selected tag', (
      tester,
    ) async {
      // `tagged` sorts first by id, so only the rank can keep it unnamed.
      final named = await namedIn(
        tester,
        const [
          _Person('aa-tagged', depth: 2),
          _Person('pin1', depth: 2, pinned: true),
          _Person('pin2', depth: 2, pinned: true),
          _Person('pin3', depth: 2, pinned: true),
          _Person('pin4', depth: 2, pinned: true),
        ],
        selectedTagMembers: {'aa-tagged'},
      );

      expectNamedTierByTier(named, [
        {'pin1', 'pin2', 'pin3', 'pin4'},
        {'aa-tagged'},
      ]);
    });

    testWidgets(
      'name a far person of the selected tag before unpinned people nearer by path',
      (tester) async {
        final named = await namedIn(
          tester,
          const [
            _Person('aa-tagged', depth: 3),
            _Person('near1'),
            _Person('near2'),
            _Person('near3'),
            _Person('near4'),
            _Person('near5'),
          ],
          selectedTagMembers: {'aa-tagged'},
        );

        expectNamedTierByTier(named, [
          {'aa-tagged'},
          {'near1', 'near2', 'near3', 'near4', 'near5'},
        ]);
      },
    );

    testWidgets(
      'name people nearest by path first when nothing outranks them',
      (
        tester,
      ) async {
        final named = await namedIn(tester, const [
          _Person('far1', depth: 3),
          _Person('far2', depth: 3),
          _Person('mid1', depth: 2),
          _Person('mid2', depth: 2),
          _Person('near1'),
          _Person('near2'),
        ]);

        expectNamedTierByTier(named, [
          {'near1', 'near2'},
          {'mid1', 'mid2'},
          {'far1', 'far2'},
        ]);
      },
    );
  });
}
