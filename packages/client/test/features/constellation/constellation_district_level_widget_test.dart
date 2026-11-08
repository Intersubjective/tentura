import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/gql/_g/constellation_field_fetch.data.gql.dart';
import 'package:tentura/features/constellation/data/model/constellation_field_mapper.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_tag_lens_cubit.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_zoom_level_controller.dart';
import 'package:tentura/features/constellation/ui/util/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/util/constellation_tap_resolver.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/fake_people_tags_repository.dart';
import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_reference_fixture.dart';
import 'fixtures/constellation_field_test_harness.dart';

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
    this.image,
  });

  final String id;
  final String? name;
  final int depth;
  final bool pinned;
  final ImageEntity? image;
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
      ConstellationPerson(
        id: p.id,
        displayName: p.name ?? 'Person ${p.id}',
        image: p.image,
      ),
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
    bool phoneRu = false,
  }) async {
    final cubit = await loadReferenceCubit(field: _field(people));
    final zoom = ConstellationZoomLevelController();
    final holder = ConstellationPresentationFrameHolder();
    addTearDown(() async {
      await cubit.close();
      zoom.dispose();
    });
    if (phoneRu) {
      await usePhoneSurface(tester);
    } else {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(phoneRu ? 'ru' : 'en'),
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
              BlocProvider(
                create: (_) => constellationSelectionForFieldBodyTests(),
              ),
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
    for (final trackpad in [false, true]) {
      testWidgets(
        'keep initials font size and screen diameter stable during '
        '${trackpad ? 'trackpad scaling on a Russian phone surface' : 'wheel zoom'}',
        (tester) async {
          const markerPeople = [
            _Person('alice', name: 'Анна Борисова'),
            _Person('bob', name: 'Борис Сергеев'),
            _Person('cara', name: 'Вера Иванова'),
            _Person('dan', name: 'Денис Петров'),
          ];
          const letteringById = {
            'alice': 'АБ',
            'bob': 'БС',
            'cara': 'ВИ',
            'dan': 'ДП',
          };
          final (:cubit, :holder) = await mount(
            tester,
            markerPeople,
            at: const {
              'ego': Offset(80, 550),
              'alice': Offset(110, 220),
              'bob': Offset(210, 220),
              'cara': Offset(110, 370),
              'dan': Offset(210, 370),
            },
            phoneRu: trackpad,
          );
          Future<void> expectTapReach() async {
            for (final id in letteringById.keys) {
              final target = holder.frame!.tapTargets['fp:$id']!;
              expect(target.width, closeTo(kMinInteractiveDimension, 0.01));
              expect(target.height, closeTo(kMinInteractiveDimension, 0.01));
              for (final direction in const [
                Offset(1, 0),
                Offset(-1, 0),
                Offset(0, 1),
                Offset(0, -1),
              ]) {
                cubit.selectPerson(null);
                await tester.pumpAndSettle();
                final centre = tester.getCenter(_graphNode(id));
                // The 48 dp round hit target extends beyond the 20 dp paint.
                await tester.tapAt(centre + direction * 23);
                await tester.pumpAndSettle();
                expect(
                  cubit.state.selectedPersonId,
                  id,
                  reason: '$id must remain selectable at $direction',
                );
                expect(
                  constellationTapTargetContains(
                    target,
                    target.center + direction * 25,
                  ),
                  isFalse,
                  reason: 'zoom must not enlarge the round hit target',
                );
              }
            }
            cubit.selectPerson(null);
            await tester.pumpAndSettle();
          }

          await expectTapReach();
          Finder initialsFor(String id) => find.descendant(
            of: _graphNode(id),
            matching: find.text(letteringById[id]!),
          );
          Finder paragraphFor(String id) => find.descendant(
            of: initialsFor(id),
            matching: find.byType(RichText),
          );
          final paragraphs = <String, RenderParagraph>{};
          final initialFonts = <String, double>{};
          final initialBounds = <String, Rect>{};
          final initialConstraints = <String, BoxConstraints>{};
          final initialText = <String, InlineSpan>{};
          for (final id in letteringById.keys) {
            final initials = initialsFor(id);
            expect(initials, findsOneWidget, reason: id);
            final paragraph = tester.renderObject<RenderParagraph>(
              paragraphFor(id),
            );
            paragraphs[id] = paragraph;
            initialFonts[id] = tester.widget<Text>(initials).style!.fontSize!;
            expect(initialFonts[id], greaterThan(0));
            initialBounds[id] = _screenRect(tester, initials);
            initialConstraints[id] = paragraph.constraints;
            initialText[id] = paragraph.text;
          }
          expect(paragraphs.values.toSet(), hasLength(markerPeople.length));
          final startScale = cubit.graphController.cameraScale;
          final fontsAcrossTicks = <String, List<double>>{
            for (final id in letteringById.keys) id: [],
          };
          final constraintsAcrossTicks = <String, List<BoxConstraints>>{
            for (final id in letteringById.keys) id: [],
          };
          final textComparisons = <RenderComparison>[];
          // Zoom about the middle of the four markers, keeping all visible.
          final focalPoint =
              (tester.getCenter(_graphNode('alice')) +
                  tester.getCenter(_graphNode('dan'))) /
              2;
          final pad = TestPointer(9, PointerDeviceKind.trackpad);
          if (trackpad) {
            await tester.sendEventToBinding(pad.panZoomStart(focalPoint));
          }
          for (var tick = 1; tick <= 3; tick++) {
            if (trackpad) {
              await tester.sendEventToBinding(
                pad.panZoomUpdate(focalPoint, scale: 1 + tick * 0.04),
              );
            } else {
              await tester.sendEventToBinding(
                PointerScrollEvent(
                  position: focalPoint,
                  scrollDelta: const Offset(0, -12),
                ),
              );
            }
            await tester.pump();
            expect(holder.frame!.detail, ConstellationDetailLevel.district);
            expect(cubit.graphController.cameraScale, greaterThan(startScale));
            for (final id in letteringById.keys) {
              final initials = initialsFor(id);
              expect(initials, findsOneWidget, reason: id);
              final paragraph = tester.renderObject<RenderParagraph>(
                paragraphFor(id),
              );
              expect(
                paragraph,
                same(paragraphs[id]),
                reason: '$id must retain its paragraph across camera ticks',
              );
              // Equal widget configurations may rebuild: only paragraph reuse
              // and unchanged layout inputs matter, not Text build counts.
              constraintsAcrossTicks[id]!.add(paragraph.constraints);
              textComparisons.add(paragraph.text.compareTo(initialText[id]!));
              fontsAcrossTicks[id]!.add(
                tester.widget<Text>(initials).style!.fontSize!,
              );
              final marker = _screenRect(tester, _graphNode(id));
              expect(marker.width, closeTo(20, 0.5), reason: id);
              expect(marker.height, closeTo(20, 0.5), reason: id);
              final lettering = _screenRect(tester, initials);
              final before = initialBounds[id]!;
              expect(lettering.width, closeTo(before.width, 0.5), reason: id);
              expect(lettering.height, closeTo(before.height, 0.5), reason: id);
              expect(
                marker.inflate(0.5).contains(lettering.topLeft),
                isTrue,
                reason: id,
              );
              expect(
                marker.inflate(0.5).contains(lettering.bottomRight),
                isTrue,
                reason: id,
              );
            }
            expect(tester.takeException(), isNull);
          }
          if (trackpad) {
            await tester.sendEventToBinding(pad.panZoomEnd());
            await tester.pumpAndSettle();
          }
          await expectTapReach();
          expect(
            fontsAcrossTicks,
            {
              for (final id in letteringById.keys)
                id: everyElement(closeTo(initialFonts[id]!, 0.000001)),
            },
            reason:
                'every district marker must keep its text layout font size '
                'across camera ticks',
          );
          expect(
            constraintsAcrossTicks,
            {
              for (final id in letteringById.keys)
                id: everyElement(initialConstraints[id]),
            },
            reason: 'camera ticks must not change initials layout constraints',
          );
          expect(
            textComparisons,
            everyElement(RenderComparison.identical),
            reason:
                'rebuilt configurations must preserve paragraph layout inputs',
          );
        },
      );
    }

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

    testWidgets(
      'draw TenturaAvatar photo at district scale when peer has image, initials otherwise',
      (tester) async {
        const withPhoto = _Person(
          'alice',
          name: 'Alice Brown',
          image: ImageEntity(id: 'img-alice', authorId: 'alice'),
        );
        const noPhoto = _Person('bob', name: 'Bob Stone');
        await mount(
          tester,
          const [withPhoto, noPhoto],
          at: const {
            'ego': Offset(600, 700),
            'alice': Offset(300, 300),
            'bob': Offset(500, 300),
          },
        );

        final aliceAvatar = find.descendant(
          of: _graphNode('alice'),
          matching: find.byWidgetPredicate(
            (w) => w is TenturaAvatar && w.profile.id == 'alice',
          ),
        );
        expect(aliceAvatar, findsOneWidget);
        expect(
          tester.widget<TenturaAvatar>(aliceAvatar).profile.hasAvatar,
          isTrue,
        );
        expect(
          find.descendant(
            of: _graphNode('alice'),
            matching: find.byType(Image),
          ),
          findsWidgets,
        );

        expect(
          find.descendant(of: _graphNode('bob'), matching: find.text('BS')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: _graphNode('bob'),
            matching: find.byWidgetPredicate(
              (w) => w is TenturaAvatar && w.profile.hasNoAvatar,
            ),
          ),
          findsOneWidget,
        );
      },
    );
  });

  testWidgets(
    'district avatars on RU phone: long names fit, photo vs initials (#1149)',
    (tester) async {
      const longRu =
          'Новый человек с очень длинным именем для телефона и раскладки меток';
      const plainName = 'Без фотографии только инициалы';
      await mount(
        tester,
        const [
          _Person(
            'photo',
            name: longRu,
            image: ImageEntity(id: 'img-ru', authorId: 'photo'),
          ),
          _Person('plain', name: plainName),
        ],
        at: const {
          'ego': Offset(80, 620),
          'photo': Offset(120, 280),
          'plain': Offset(220, 280),
        },
        scale: 0.65,
        phoneRu: true,
      );

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: _graphNode('photo'),
          matching: find.byType(Image),
        ),
        findsWidgets,
      );
      final plainInitials = TenturaAvatar.initialsForProfile(
        const Profile(id: 'plain', displayName: plainName),
      );
      expect(
        find.descendant(
          of: _graphNode('plain'),
          matching: find.text(plainInitials),
        ),
        findsOneWidget,
      );
      final photoMarker = _screenRect(tester, _graphNode('photo'));
      expect(photoMarker.width, closeTo(20, 0.5));
      expect(photoMarker.height, closeTo(20, 0.5));
    },
  );

  test(
    'ConstellationFieldFetch maps peer image through to district avatar profile',
    () {
      final wire = {
        '__typename': 'query_root',
        'constellationField': {
          '__typename': 'v2_ConstellationField',
          'loadedAt': '2026-11-07T12:00:00.000Z',
          'context': '',
          'peersCapped': false,
          'requestsCapped': false,
          'directContactIds': ['peer-img'],
          'peers': [
            {
              '__typename': 'v2_ConstellationPeer',
              'id': 'peer-img',
              'contactOnly': false,
              'displayName': 'Photo Peer',
              'handle': null,
              'image': {
                '__typename': 'v2_image',
                'id': 'img-peer',
                'hash': 'hash-1',
                'height': 100,
                'width': 100,
                'author_id': 'peer-img',
                'created_at': '2026-11-01',
              },
              'isNew': false,
              'pinState': null,
              'presence': 'visible',
              'temporaryBeaconId': null,
              'bondContexts': <dynamic>[],
              'visible': true,
            },
          ],
          'edges': <dynamic>[],
          'requests': <dynamic>[],
          'posts': <dynamic>[],
          'memberWebs': <dynamic>[],
          'anchorProjection': {
            '__typename': 'v2_ConstellationAnchorProjection',
            'revision': '0',
            'anchors': <dynamic>[],
            'pinnedPeers': <dynamic>[],
            'pinnedRequests': <dynamic>[],
            'supportPeers': <dynamic>[],
            'supportEdges': <dynamic>[],
            'serverFilteredBeaconIds': <dynamic>[],
            'serverFilteredBeaconCount': 0,
          },
        },
      };

      final field = mapConstellationFieldFromFieldFetch(
        GConstellationFieldFetchData.fromJson(wire)!.constellationField,
      );
      final peer = field.peers.single;
      expect(peer.image?.id, 'img-peer');
      final profile = Profile(
        id: peer.id,
        displayName: peer.displayName ?? '',
        image: peer.image,
      );
      expect(profile.hasAvatar, isTrue);
      expect(TenturaAvatar.initialsForProfile(profile), 'PP');
    },
  );

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
