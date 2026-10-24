import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_tag_lens_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/fake_people_tags_repository.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');

const _neighbour = PersonTag(
  id: 'T-neighbour',
  name: 'Neighbour',
  glyph: 'N',
  color: 0,
  ord: 0,
);
const _workshop = PersonTag(
  id: 'T-workshop',
  name: 'Workshop',
  glyph: 'W',
  color: 1,
  ord: 1,
);
const _garden = PersonTag(
  id: 'T-garden',
  name: 'Garden',
  glyph: 'G',
  color: 2,
  ord: 2,
);

final _loadedAt = DateTime.utc(2026, 10, 23, 12);

/// Memberships are listed out of tag order on purpose: glyphs follow the
/// tags' `ord`, not the order the index happens to hold them in.
const _memberships = [
  PersonTagMembers(
    tagId: 'T-garden',
    personIds: ['three-tags'],
  ),
  PersonTagMembers(
    tagId: 'T-neighbour',
    personIds: ['one-tag', 'two-tags', 'three-tags', 'lena', 'auto-and-own'],
  ),
  PersonTagMembers(
    tagId: 'T-workshop',
    personIds: ['two-tags', 'three-tags', 'lena'],
  ),
];

class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
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

const _people = [
  ConstellationPerson(id: 'no-tags', displayName: 'Nora'),
  ConstellationPerson(id: 'one-tag', displayName: 'Omar'),
  ConstellationPerson(id: 'two-tags', displayName: 'Tia'),
  ConstellationPerson(id: 'three-tags', displayName: 'Theo'),
  ConstellationPerson(
    id: 'lena',
    displayName: 'Lena',
    autoTagKinds: {ConstellationAutoTagKind.mutualContact},
  ),
  ConstellationPerson(
    id: 'auto-only',
    displayName: 'Aki',
    autoTagKinds: {
      ConstellationAutoTagKind.mutualContact,
      ConstellationAutoTagKind.iTrust,
    },
  ),
  ConstellationPerson(
    id: 'auto-and-own',
    displayName: 'Abe',
    autoTagKinds: {ConstellationAutoTagKind.trustsMe},
  ),
];

ConstellationField _field({bool pinLena = false}) => ConstellationField(
  loadedAt: _loadedAt,
  context: '',
  peers: _people,
  // Lena is a contact without a trust edge, so her label carries no trust
  // badge text and is exactly the name plus her tags.
  edges: [
    for (final person in _people)
      if (person.id != 'lena')
        ConstellationTrustEdgeEntity(src: 'ego', dst: person.id, tier: 1),
  ],
  directContactIds: [for (final person in _people) person.id],
  anchorProjection: pinLena
      ? ConstellationAnchorProjection(
          revision: ConstellationAnchorRevision(BigInt.one),
          anchors: [
            ConstellationAnchor(
              target: ConstellationAnchorTarget.person('lena'),
              position: const ConstellationAnchorPosition(
                xUnits: 4,
                yUnits: -2,
                coordinateSpaceVersion: 1,
              ),
              revision: ConstellationAnchorRevision(BigInt.one),
              placedAt: _loadedAt,
            ),
          ],
          pinnedPeers: _people,
          pinnedRequests: const [],
          supportPeers: const [],
          supportEdges: const [],
          serverFilteredBeaconIds: const [],
          serverFilteredBeaconCount: 0,
        )
      : null,
);

Finder _graphNode(String personId) =>
    find.byKey(TestIds.key(TestIds.graphNode(personId)));

/// The map marker (the clip-none stack around the node) of one person.
Finder _marker(String personId) => find
    .ancestor(
      of: _graphNode(personId),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Stack &&
            widget.clipBehavior == Clip.none &&
            widget.alignment == Alignment.center,
      ),
    )
    .first;

Finder _glyphsOn(String personId) =>
    find.descendant(of: _marker(personId), matching: find.byType(TagGlyph));

List<String> _glyphTextsOn(WidgetTester tester, String personId) => [
  for (final glyph in tester.widgetList<TagGlyph>(_glyphsOn(personId)))
    glyph.glyph,
];

void main() {
  late PeopleTagsTestRig rig;

  setUp(() async {
    rig = await PeopleTagsTestRig.create(
      FakePeopleTagsRepository(
        tagList: [_garden, _workshop, _neighbour],
        memberList: _memberships,
      ),
    );
    GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await rig.dispose();
  });

  Future<void> mount(WidgetTester tester, ConstellationField field) async {
    final cubit = ConstellationCubit(
      case_: ConstellationStoreFixture(
        _StubRepository(field),
        accountId: _ego.id,
      ).store,
      viewer: _ego,
    );
    addTearDown(cubit.close);
    await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
    cubit.updateLabelBudgetContext(
      viewport: const Size(1200, 900),
      textScaleFactor: 1,
    );
    final lens = ConstellationTagLensCubit(
      ownTagIdsOf: rig.peopleTags.tagsOfPerson,
    );
    addTearDown(lens.close);
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
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
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('own-tag glyphs on Field person nodes', () {
    testWidgets('a person without own tags shows no glyph and no overflow '
        'count', (tester) async {
      await mount(tester, _field());

      expect(_graphNode('no-tags'), findsOneWidget, reason: 'positive control');
      expect(_glyphsOn('no-tags'), findsNothing);
      expect(
        find.descendant(of: _marker('no-tags'), matching: find.text('+1')),
        findsNothing,
      );
    });

    testWidgets('one own tag shows its glyph and no overflow count', (
      tester,
    ) async {
      await mount(tester, _field());

      expect(_glyphTextsOn(tester, 'one-tag'), ['N']);
      expect(
        find.descendant(
          of: _marker('one-tag'),
          matching: find.textContaining('+'),
        ),
        findsNothing,
      );
    });

    testWidgets('two own tags show two glyphs and no overflow count', (
      tester,
    ) async {
      await mount(tester, _field());

      expect(_glyphTextsOn(tester, 'two-tags'), ['N', 'W']);
      expect(
        find.descendant(
          of: _marker('two-tags'),
          matching: find.textContaining('+'),
        ),
        findsNothing,
      );
    });

    testWidgets('three own tags show the first two in tag order and "+1"', (
      tester,
    ) async {
      await mount(tester, _field());

      // Tag order is the tags' `ord` (Neighbour, Workshop, Garden), not the
      // order the membership index lists them in.
      expect(_glyphTextsOn(tester, 'three-tags'), ['N', 'W']);
      expect(
        find.descendant(of: _marker('three-tags'), matching: find.text('+1')),
        findsOneWidget,
      );
    });

    testWidgets('automatic tags are never drawn on a node', (tester) async {
      await mount(tester, _field());

      // Only automatic tags: nothing drawn.
      expect(
        _graphNode('auto-only'),
        findsOneWidget,
        reason: 'positive control',
      );
      expect(_glyphsOn('auto-only'), findsNothing);
      // Own plus automatic: only the own tag is drawn.
      expect(_glyphTextsOn(tester, 'auto-and-own'), ['N']);
      // Neither person's marker carries any automatic-tag UI: no auto chip,
      // no tag chip, no automatic tag name.
      for (final personId in ['auto-only', 'auto-and-own']) {
        final marker = _marker(personId);
        expect(
          find.descendant(of: marker, matching: find.byType(AutoTagChip)),
          findsNothing,
          reason: personId,
        );
        expect(
          find.descendant(of: marker, matching: find.byType(PersonTagChip)),
          findsNothing,
          reason: personId,
        );
        for (final name in ['Mutual contact', 'I trust', 'Trusts me']) {
          expect(
            find.descendant(of: marker, matching: find.textContaining(name)),
            findsNothing,
            reason: '$personId shows "$name"',
          );
        }
      }
    });

    testWidgets('glyphs follow the tag store when a tag is added', (
      tester,
    ) async {
      await mount(tester, _field());
      expect(_glyphsOn('no-tags'), findsNothing);

      await rig.peopleTags.addToTag(
        personId: 'no-tags',
        tagId: _workshop.id,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(_glyphTextsOn(tester, 'no-tags'), ['W']);
    });
  });

  group('pin badge next to own-tag glyphs', () {
    testWidgets('a pinned person keeps the pin badge key, left of the glyphs', (
      tester,
    ) async {
      await mount(tester, _field(pinLena: true));

      final glyphs = _glyphsOn('lena');
      expect(glyphs, findsNWidgets(2));
      final pin = find.descendant(
        of: _marker('lena'),
        matching: find.byKey(TestIds.key(TestIds.constellationPinMarker)),
      );
      expect(pin, findsOneWidget);
      expect(
        tester.getCenter(pin).dx,
        lessThan(tester.getCenter(glyphs.first).dx),
        reason: 'the pin sits left of the glyph cluster',
      );
    });
  });

  group('screen-reader label with tags', () {
    testWidgets('lists own tags in tag order, then the automatic ones', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await mount(tester, _field());

      final label = tester.getSemantics(_graphNode('lena')).label;
      handle.dispose();

      expect(
        label,
        'Lena, tags: Neighbour, Workshop; automatic: Mutual contact',
      );
    });

    testWidgets('names every own tag, not just the drawn glyphs', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await mount(tester, _field());

      final label = tester.getSemantics(_graphNode('three-tags')).label;
      handle.dispose();

      expect(label, contains('tags: Neighbour, Workshop, Garden'));
    });

    testWidgets('a person with no tags has no tag text in the label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await mount(tester, _field());

      final label = tester.getSemantics(_graphNode('no-tags')).label;
      handle.dispose();

      expect(label, startsWith('Nora'));
      expect(label, isNot(contains('tags')));
      expect(label, isNot(contains('automatic')));
    });
  });
}
