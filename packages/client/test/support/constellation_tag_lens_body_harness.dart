import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_tag_lens_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../ui/effect/fake_ui_effect_port.dart';
import 'constellation_store_fixture.dart';
import 'fake_people_tags_repository.dart';

const tagLensHarnessEgo = Profile(id: 'ego', displayName: 'Ego');

const tagLensNeighbour = PersonTag(
  id: 'T-neighbour',
  name: 'Neighbour',
  glyph: 'N',
  color: 0,
  ord: 0,
);
const tagLensWorkshop = PersonTag(
  id: 'T-workshop',
  name: 'Workshop',
  glyph: 'W',
  color: 1,
  ord: 1,
);
const tagLensGarden = PersonTag(
  id: 'T-garden',
  name: 'Garden',
  glyph: 'G',
  color: 2,
  ord: 2,
);

/// A tag nobody on the Field belongs to.
const tagLensEmpty = PersonTag(
  id: 'T-empty',
  name: 'Nobody',
  glyph: 'X',
  color: 3,
  ord: 3,
);

final _loadedAt = DateTime.utc(2026, 10, 24, 12);

/// Neighbour: Ann and Bob. Workshop: Ann. Garden: Ann, Bob and Cid. Cid and
/// Dan carry no other tag; Dan is in none.
const tagLensMemberships = [
  PersonTagMembers(tagId: 'T-neighbour', personIds: ['ann', 'bob']),
  PersonTagMembers(tagId: 'T-workshop', personIds: ['ann']),
  PersonTagMembers(tagId: 'T-garden', personIds: ['ann', 'bob', 'cid']),
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

/// Ann has two Requests, Bob one, Cid one, Dan none; the viewer has none
/// (so a count of "Requests" is only ever other people's).
ConstellationField tagLensHarnessField() => ConstellationField(
  loadedAt: _loadedAt,
  context: '',
  peers: const [
    ConstellationPerson(id: 'ann', displayName: 'Ann'),
    ConstellationPerson(id: 'bob', displayName: 'Bob'),
    ConstellationPerson(id: 'cid', displayName: 'Cid'),
    ConstellationPerson(id: 'dan', displayName: 'Dan'),
  ],
  edges: const [
    ConstellationTrustEdgeEntity(src: 'ego', dst: 'ann', tier: 1),
    ConstellationTrustEdgeEntity(src: 'ego', dst: 'bob', tier: 1),
    ConstellationTrustEdgeEntity(src: 'ego', dst: 'cid', tier: 1),
    ConstellationTrustEdgeEntity(src: 'ego', dst: 'dan', tier: 1),
  ],
  requests: const [
    ConstellationRequest(
      id: 'req-ann-1',
      authorId: 'ann',
      title: 'Tools',
      status: 0,
    ),
    ConstellationRequest(
      id: 'req-ann-2',
      authorId: 'ann',
      title: 'Ladder',
      status: 0,
    ),
    ConstellationRequest(
      id: 'req-bob',
      authorId: 'bob',
      title: 'Ride',
      status: 0,
    ),
    ConstellationRequest(
      id: 'req-cid',
      authorId: 'cid',
      title: 'Soil',
      status: 0,
    ),
  ],
  directContactIds: const ['ann', 'bob', 'cid', 'dan'],
);

/// The tag-lens field plus the viewer's own Requests in every lifecycle
/// state, and one open Request of somebody else.
ConstellationField tagLensHarnessFieldWithViewerRequests() {
  final base = tagLensHarnessField();
  const mine = [
    ConstellationRequest(
      id: 'mine-open',
      authorId: 'ego',
      title: 'Borrow a drill',
      status: 0,
      isMine: true,
    ),
    ConstellationRequest(
      id: 'mine-needs-help',
      authorId: 'ego',
      title: 'Help moving',
      status: 7,
      isMine: true,
    ),
    ConstellationRequest(
      id: 'mine-closed',
      authorId: 'ego',
      title: 'Old closed errand',
      status: 6,
      isMine: true,
    ),
    ConstellationRequest(
      id: 'mine-cancelled',
      authorId: 'ego',
      title: 'Old cancelled errand',
      status: 1,
      isMine: true,
    ),
  ];
  return base.copyWith(requests: [...base.requests, ...mine]);
}

typedef TagLensBodyHarness = ({
  ConstellationCubit field,
  ConstellationTagLensCubit lens,
  PeopleTagsTestRig rig,
  RootStackRouter? router,
});

/// Mounts [ConstellationBody] on the tag-lens field with the people-tags
/// store registered in GetIt (as the app does) and a screen-scoped lens.
Future<TagLensBodyHarness> mountTagLensBody(
  WidgetTester tester, {
  ConstellationPlacementCase Function(ConstellationFieldStoreCase store)?
  placementFor,
  ConstellationField? field,

  /// Hosts the body in a router that knows the forward route, so a push to
  /// it can be observed on the returned router.
  bool withRouter = false,
}) async {
  final rig = await PeopleTagsTestRig.create(
    FakePeopleTagsRepository(
      tagList: const [
        tagLensNeighbour,
        tagLensWorkshop,
        tagLensGarden,
        tagLensEmpty,
      ],
      memberList: tagLensMemberships,
    ),
  );
  GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
  addTearDown(() async {
    await GetIt.I.reset();
    await rig.dispose();
  });
  final fixture = ConstellationStoreFixture(
    _StubRepository(field ?? tagLensHarnessField()),
    accountId: tagLensHarnessEgo.id,
  );
  final cubit = ConstellationCubit(
    case_: fixture.store,
    placementCase: placementFor?.call(fixture.store),
    viewer: tagLensHarnessEgo,
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
  Widget scoped(Widget child) => TenturaResponsiveScope(
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
      child: child,
    ),
  );
  Widget body() => Scaffold(
    body: ConstellationBody(legendExpanded: false, onToggleLegend: () {}),
  );
  RootStackRouter? router;
  if (withRouter) {
    router = RootStackRouter.build(
      routes: [
        AutoRoute(
          page: PageInfo('TagLensHostRoute', builder: (_) => body()),
          initial: true,
        ),
        AutoRoute(
          page: PageInfo(
            ForwardBeaconRoute.name,
            builder: (_) => const Scaffold(body: Text('forward-screen')),
          ),
          path: '/forward/:id',
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        routerConfig: router.config(),
        builder: (_, child) => scoped(child!),
      ),
    );
  } else {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: scoped(body()),
      ),
    );
  }
  await settleTagLensBody(tester);
  return (field: cubit, lens: lens, rig: rig, router: router);
}

Future<void> settleTagLensBody(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}
