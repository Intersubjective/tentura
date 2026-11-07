// Refs #1142: no pinned, mutual-trust glyph disc, or own-tag glyphs on nodes.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/gql/_g/constellation_field_fetch.data.gql.dart';
import 'package:tentura/features/constellation/data/model/constellation_field_mapper.dart';
import 'package:tentura/features/constellation/domain/constellation_trust_badge.dart';
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
import 'package:tentura/design_system/components/person_tag_chip.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/bloc/screen_state.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/fake_people_tags_repository.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_field_test_harness.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');
final _loadedAt = DateTime.utc(2026, 11, 7, 12);

const _neighbour = PersonTag(
  id: 'T-neighbour',
  name: 'Соседи с очень длинным названием для узкого экрана',
  glyph: 'N',
  color: 0,
  ord: 0,
);

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

ConstellationField _pinnedMutualTaggedField() {
  const target = 'peer-pinned-mutual-tagged';
  return ConstellationField(
    loadedAt: _loadedAt,
    context: '',
    peers: const [
      ConstellationPerson(
        id: target,
        displayName: 'Анна с взаимным доверием и меткой',
      ),
    ],
    edges: const [
      ConstellationTrustEdgeEntity(src: 'ego', dst: target, tier: 1),
      ConstellationTrustEdgeEntity(src: target, dst: 'ego', tier: 1),
    ],
    directContactIds: const [target],
    anchorProjection: ConstellationAnchorProjection(
      revision: ConstellationAnchorRevision(BigInt.one),
      anchors: [
        ConstellationAnchor(
          target: ConstellationAnchorTarget.person(target),
          position: const ConstellationAnchorPosition(
            xUnits: 2,
            yUnits: 1,
            coordinateSpaceVersion: 1,
          ),
          revision: ConstellationAnchorRevision(BigInt.one),
          placedAt: _loadedAt,
        ),
      ],
      pinnedPeers: const [
        ConstellationPerson(id: target, displayName: 'Анна'),
      ],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

Finder _personMarker(String personId) => find
    .ancestor(
      of: find.byKey(TestIds.key(TestIds.graphNode(personId))),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Stack &&
            w.clipBehavior == Clip.none &&
            w.alignment == Alignment.center,
      ),
    )
    .first;

void main() {
  group('wire', () {
    test('mutual tier-1 edges still map to mutual trust on the field', () {
      final wire = {
        '__typename': 'query_root',
        'constellationField': {
          '__typename': 'v2_ConstellationField',
          'loadedAt': '2026-11-07T12:00:00.000Z',
          'context': '',
          'peersCapped': false,
          'requestsCapped': false,
          'directContactIds': ['ego', 'peer-m'],
          'peers': [
            {
              '__typename': 'v2_ConstellationPeer',
              'id': 'ego',
              'contactOnly': false,
              'displayName': 'Ego',
              'handle': null,
              'image': null,
              'isNew': false,
              'pinState': null,
              'presence': 'visible',
              'temporaryBeaconId': null,
              'bondContexts': <dynamic>[],
              'visible': true,
            },
            {
              '__typename': 'v2_ConstellationPeer',
              'id': 'peer-m',
              'contactOnly': false,
              'displayName': 'Марина',
              'handle': null,
              'image': null,
              'isNew': false,
              'pinState': null,
              'presence': 'visible',
              'temporaryBeaconId': null,
              'bondContexts': <dynamic>[],
              'visible': true,
            },
          ],
          'edges': [
            {
              '__typename': 'v2_ConstellationTrustEdge',
              'src': 'ego',
              'dst': 'peer-m',
              'tier': 1,
            },
            {
              '__typename': 'v2_ConstellationTrustEdge',
              'src': 'peer-m',
              'dst': 'ego',
              'tier': 1,
            },
          ],
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
      expect(
        constellationTrustBadges(field: field, viewerId: 'ego')['peer-m'],
        ConstellationTrustBadge.mutual,
      );
    });
  });

  group('375×667 RU', () {
    late PeopleTagsTestRig rig;

    setUp(() async {
      rig = await PeopleTagsTestRig.create(
        FakePeopleTagsRepository(
          tagList: [_neighbour],
          memberList: const [
            PersonTagMembers(
              tagId: 'T-neighbour',
              personIds: ['peer-pinned-mutual-tagged'],
            ),
          ],
        ),
      );
      GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
    });

    tearDown(() async {
      await GetIt.I.reset();
      await rig.dispose();
    });

    testWidgets(
      'pinned, mutual-trust, tagged person shows no pin, tag or mutual glyph',
      (tester) async {
        await usePhoneSurface(tester);
        final field = _pinnedMutualTaggedField();
        final cubit = ConstellationCubit(
          case_: ConstellationStoreFixture(
            _StubRepository(field),
            accountId: _ego.id,
          ).store,
          viewer: _ego,
        );
        addTearDown(cubit.close);
        await cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
        cubit.updateLabelBudgetContext(
          viewport: const Size(375, 667),
          textScaleFactor: 1,
        );
        final lens = ConstellationTagLensCubit(
          ownTagIdsOf: rig.peopleTags.tagsOfPerson,
        );
        addTearDown(lens.close);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ru'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(375, 667),
                textScaler: TextScaler.linear(1),
              ),
              child: TenturaResponsiveScope(
                child: MultiBlocProvider(
                  providers: [
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
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 400));
        }

        const personId = 'peer-pinned-mutual-tagged';
        final marker = _personMarker(personId);
        expect(marker, findsOneWidget);
        expect(
          find.descendant(
            of: marker,
            matching: find.byKey(TestIds.key(TestIds.constellationPinMarker)),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: marker, matching: find.byType(TagGlyph)),
          findsNothing,
        );
        expect(
          find.descendant(
            of: marker,
            matching: find.byIcon(Icons.push_pin),
          ),
          findsNothing,
        );
        expect(
          constellationTrustBadges(
            field: cubit.state.field!,
            viewerId: _ego.id,
          )[personId],
          ConstellationTrustBadge.mutual,
        );

        final handle = tester.ensureSemantics();
        final label = tester
            .getSemantics(
              find.byKey(TestIds.key(TestIds.graphNode(personId))),
            )
            .label;
        handle.dispose();
        expect(label, contains('Анна'));
        expect(label, contains(_neighbour.name));
        expect(label, contains('Закреплено'));

        expect(tester.takeException(), isNull);
      },
    );
  });
}
