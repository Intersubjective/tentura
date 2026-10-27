import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_tag_picker.dart';
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tag_suggestion_event.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tag_suggestion_case.dart';
import 'package:tentura/features/people_tags/ui/widget/tag_suggestion_card.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_tag_magnet.dart';
import 'package:tentura/features/constellation/domain/port/constellation_tag_magnet_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_tag_magnet_case.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_magnet_layer.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_magnet_control.dart';
import '../../support/counting_people_tags_repository.dart';
import '../../support/test_realtime_sync.dart';
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

final class _SuggestionRepository implements PeopleTagsRepositoryPort {
  @override
  Future<PersonTagSuggestionState> personTagSuggestionState() async =>
      const PersonTagSuggestionState(canSuggest: true, disabled: false);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _SavedMagnetRepository
    implements ConstellationTagMagnetRepositoryPort {
  @override
  Future<List<ConstellationTagMagnet>> list() async => const [
    ConstellationTagMagnet(
      tagId: 'T-neighbour',
      xUnits: 0,
      yUnits: 0,
      revision: 1,
    ),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

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
  late PeopleTagsCase peopleTags;
  late CountingPeopleTagsRepository repository;
  late RealtimeSyncCase realtimeCase;
  late TestRealtimeSyncPort realtimePort;

  setUp(() async {
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    realtimeCase = realtime.case_;
    repository = CountingPeopleTagsRepository(
      FakePeopleTagsRepository(
        tagList: [_garden, _workshop, _neighbour],
        memberList: _memberships,
      ),
    );
    peopleTags = PeopleTagsCase(
      repository,
      realtime.case_,
      env: const Env(),
      logger: Logger('test'),
    );
    GetIt.I.registerSingleton<PeopleTagsCase>(peopleTags);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await peopleTags.dispose();
    await realtimePort.dispose();
  });

  Future<ConstellationCubit> mount(
    WidgetTester tester,
    ConstellationField field,
  ) async {
    final cubit = ConstellationCubit(
      case_: ConstellationStoreFixture(
        _StubRepository(field),
        accountId: _ego.id,
      ).store,
      viewer: _ego,
      tagMagnetCase: ConstellationTagMagnetCase(
        _SavedMagnetRepository(),
        realtimeCase,
        env: const Env(),
        logger: Logger('test'),
      ),
    );
    addTearDown(cubit.close);
    await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
    cubit.updateLabelBudgetContext(
      viewport: const Size(1200, 900),
      textScaleFactor: 1,
    );
    final lens = ConstellationTagLensCubit(
      ownTagIdsOf: peopleTags.tagsOfPerson,
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
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    return cubit;
  }

  testWidgets('the Field shows own tags in its row on a cold session', (
    tester,
  ) async {
    await mount(tester, _field());
    expect(find.text('Neighbour'), findsWidgets);
    expect(repository.tagsCalls, 1);
    expect(repository.membershipCalls, 1);
  });

  testWidgets('the Field shows a tagged person glyph on a cold session', (
    tester,
  ) async {
    await mount(tester, _field());
    expect(_graphNode('one-tag'), findsOneWidget);
    expect(_glyphTextsOn(tester, 'one-tag'), ['N']);
  });
  testWidgets('a saved own tag magnet appears on the cold Field map', (
    tester,
  ) async {
    await mount(tester, _field());
    final marker = find.descendant(
      of: find.byType(ConstellationTagMagnetLayer),
      matching: find.byType(ConstellationTagMagnetControl),
    );
    expect(marker, findsOneWidget);
    expect(
      find.descendant(of: marker, matching: find.text('Neighbour')),
      findsOneWidget,
    );
  });

  testWidgets('the Field reuses loaded tags and reflects realtime changes', (
    tester,
  ) async {
    await mount(tester, _field());
    expect(repository.tagsCalls, 1);
    expect(repository.membershipCalls, 1);
    await mount(tester, _field());
    expect(repository.tagsCalls, 1);
    expect(repository.membershipCalls, 1);
    repository.store.tagList = const [
      PersonTag(id: 'T-new', name: 'Runners', glyph: 'R', color: 0, ord: 0),
    ];
    repository.store.memberList = const [
      PersonTagMembers(tagId: 'T-new', personIds: ['one-tag']),
    ];
    realtimePort.emitChange(
      RealtimeEntityChange(
        kind: RealtimeEntityKind.personTag,
        aggregateId: 'owner',
        operation: RealtimeOperation.update,
        source: RealtimeChangeSource.serverInvalidation,
        revision: BigInt.one,
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.tagsCalls, 2);
    expect(repository.membershipCalls, 2);
    expect(find.text('Runners'), findsWidgets);
    expect(_glyphTextsOn(tester, 'one-tag'), ['R']);
  });
  testWidgets(
    'a tagged person opens a panel with own tags from the cold Field',
    (tester) async {
      final field = await mount(tester, _field());
      field.selectPerson('one-tag');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final panel = find.byType(GraphPersonContextPanel);
      expect(panel, findsOneWidget);
      expect(
        find.descendant(of: panel, matching: find.text('Your tags')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('Neighbour')),
        findsOneWidget,
      );
      expect(repository.tagsCalls, 1);
      expect(repository.membershipCalls, 1);
    },
  );

  testWidgets(
    'Field, Forward and suggestions share one load; a new session fetches again',
    (tester) async {
      await mount(tester, _field());
      expect(find.text('Neighbour'), findsWidgets);
      expect(repository.tagsCalls, 1);
      expect(repository.membershipCalls, 1);
      GetIt.I.registerSingleton<PeopleTagSuggestionCase>(
        PeopleTagSuggestionCase(
          _SuggestionRepository(),
          env: const Env(),
          logger: Logger('test'),
        ),
      );

      Future<void> openConsumers() async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: Column(
                children: [
                  ForwardTagPicker(
                    state: const ForwardState(beaconId: 'B1'),
                    onToggle: (_) {},
                    onToggleTag: (_, __) {},
                  ),
                  TagSuggestionCard(
                    event: PeopleTagSuggestionEvent.mutualTrust('one-tag'),
                    personIds: const ['one-tag'],
                    names: 'Omar',
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await openConsumers();
      expect(
        find.byKey(const ValueKey('forward-tag-chip-T-neighbour')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tag-suggestion-card')),
          matching: find.text('Neighbour'),
        ),
        findsOneWidget,
      );
      expect(repository.tagsCalls, 1);
      expect(repository.membershipCalls, 1);

      // A fresh application session has a fresh tag store and a different account snapshot.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await GetIt.I.unregister<PeopleTagsCase>();
        await peopleTags.dispose();
      });
      repository.store.tagList = const [
        PersonTag(id: 'T-new', name: 'Runners', glyph: 'R', color: 0, ord: 0),
      ];
      repository.store.memberList = const [
        PersonTagMembers(tagId: 'T-new', personIds: ['one-tag']),
      ];
      peopleTags = PeopleTagsCase(
        repository,
        realtimeCase,
        env: const Env(),
        logger: Logger('test'),
      );
      GetIt.I.registerSingleton<PeopleTagsCase>(peopleTags);
      await tester.runAsync(
        () async => await GetIt.I.unregister<PeopleTagSuggestionCase>(),
      );
      GetIt.I.registerSingleton<PeopleTagSuggestionCase>(
        PeopleTagSuggestionCase(
          _SuggestionRepository(),
          env: const Env(),
          logger: Logger('test'),
        ),
      );
      await openConsumers();
      expect(repository.tagsCalls, 2);
      expect(repository.membershipCalls, 2);
      expect(
        find.byKey(const ValueKey('forward-tag-chip-T-new')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('forward-tag-chip-T-neighbour')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tag-suggestion-card')),
          matching: find.text('Runners'),
        ),
        findsOneWidget,
      );
    },
  );
}
