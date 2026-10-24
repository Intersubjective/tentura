import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/constellation_store_fixture.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');
const _neighbour = 'T-neighbour';
const _helpedMe = 'T-helped-me';

const _ownTags = <String, Set<String>>{
  'ann': {_neighbour, _helpedMe},
  'bob': {_neighbour},
};

Set<String> _ownTagIdsOf(String id) => _ownTags[id] ?? const {};

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

/// Ann (both tags) and Bob (one tag) are contacts, each with a Request and a
/// Post; Cid carries no tag.
ConstellationField _field({
  bool bobRequest = true,
  bool bobPost = true,
}) => ConstellationField(
  loadedAt: _loadedAt,
  context: '',
  peers: const [
    ConstellationPerson(id: 'ann', displayName: 'Ann'),
    ConstellationPerson(id: 'bob', displayName: 'Bob'),
    ConstellationPerson(id: 'cid', displayName: 'Cid'),
  ],
  edges: const [
    ConstellationTrustEdgeEntity(src: 'ego', dst: 'ann', tier: 1),
    ConstellationTrustEdgeEntity(src: 'ego', dst: 'bob', tier: 1),
    ConstellationTrustEdgeEntity(src: 'ego', dst: 'cid', tier: 1),
  ],
  requests: [
    const ConstellationRequest(
      id: 'req-ann',
      authorId: 'ann',
      title: 'Tools',
      status: 0,
    ),
    if (bobRequest)
      const ConstellationRequest(
        id: 'req-bob',
        authorId: 'bob',
        title: 'Ride',
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
    if (bobPost)
      ConstellationPost(
        id: 'post-bob',
        authorId: 'bob',
        rootExcerpt: 'Anyone driving north?',
        lastActivityAt: _loadedAt.subtract(const Duration(hours: 2)),
      ),
  ],
  directContactIds: const ['ann', 'bob', 'cid'],
);

typedef _Mounted = ({ConstellationCubit field, ConstellationTagLensCubit lens});

Future<_Mounted> _mount(
  WidgetTester tester,
  ConstellationField field,
) async {
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
  final lens = ConstellationTagLensCubit(ownTagIdsOf: _ownTagIdsOf);
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
  return (field: cubit, lens: lens);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Widgets fading their child to the tag lens opacity.
int _dimmedCount(WidgetTester tester) => find
    .byWidgetPredicate(
      (w) => w is Opacity && w.opacity == kConstellationTagLensDimOpacity,
    )
    .evaluate()
    .length;

/// Selects the "and" intersection of both own tags: only Ann stays bright.
Future<void> _selectIntersection(WidgetTester tester, _Mounted m) async {
  m.lens
    ..toggleOwn(_neighbour)
    ..toggleOwn(_helpedMe)
    ..setMode(ConstellationTagFilterMode.and);
  await _settle(tester);
}

void main() {
  group('tag lens on the rendered field', () {
    testWidgets('nothing fades while no tag is selected', (tester) async {
      await _mount(tester, _field());

      expect(_dimmedCount(tester), 0);
    });

    testWidgets('people outside the selection fade to 25 %', (tester) async {
      final m = await _mount(
        tester,
        _field(bobRequest: false, bobPost: false),
      );
      // Remove Ann's Request and Post from the picture too: only people left.
      expect(_dimmedCount(tester), 0);

      await _selectIntersection(tester, m);

      // Bob and Cid; each marker may also have a separate label plate.
      expect(_dimmedCount(tester), greaterThanOrEqualTo(2));
    });

    testWidgets("a dimmed person's Request fades as well", (tester) async {
      final without = await _mount(tester, _field(bobRequest: false));
      await _selectIntersection(tester, without);
      final base = _dimmedCount(tester);

      final withRequest = await _mount(tester, _field());
      await _selectIntersection(tester, withRequest);

      expect(_dimmedCount(tester), greaterThan(base));
    });

    testWidgets("a dimmed person's Post fades as well", (tester) async {
      final without = await _mount(tester, _field(bobPost: false));
      await _selectIntersection(tester, without);
      final base = _dimmedCount(tester);

      final withPost = await _mount(tester, _field());
      await _selectIntersection(tester, withPost);

      expect(_dimmedCount(tester), greaterThan(base));
    });

    testWidgets('clearing the selection brightens everything again', (
      tester,
    ) async {
      final m = await _mount(tester, _field());
      await _selectIntersection(tester, m);
      expect(_dimmedCount(tester), greaterThan(0));

      m.lens.clear();
      await _settle(tester);

      expect(_dimmedCount(tester), 0);
    });

    testWidgets('"or" dims fewer people than "and"', (tester) async {
      final m = await _mount(tester, _field());
      m.lens
        ..toggleOwn(_neighbour)
        ..toggleOwn(_helpedMe);
      await _settle(tester);
      final union = _dimmedCount(tester);

      m.lens.setMode(ConstellationTagFilterMode.and);
      await _settle(tester);

      expect(_dimmedCount(tester), greaterThan(union));
    });
  });

  group(
    'selecting a tag through the screen-scoped lens leaves the field alone',
    () {
      testWidgets('node positions, camera and layout work stay identical', (
        tester,
      ) async {
        final m = await _mount(tester, _field());
        final controller = m.field.graphController;
        final ids = [for (final n in controller.nodes) n.id];
        expect(ids, isNotEmpty);
        final positions = {
          for (final id in ids) id: controller.getPositionOrNullForId(id),
        };
        final cameraRevision = controller.cameraRevision.value;
        final cameraScale = controller.cameraScale;
        final reconciliations = m.field.layoutReconciliationCount;
        final layoutRuns = controller.relayoutInvocationCount;
        final composition = m.field.state.composition;
        expect(reconciliations, greaterThan(0), reason: 'positive control');

        await _selectIntersection(tester, m);

        // Positive control: the selection reached the rendered field.
        expect(_dimmedCount(tester), greaterThan(0));
        expect([for (final n in controller.nodes) n.id], ids);
        for (final id in ids) {
          expect(
            controller.getPositionOrNullForId(id),
            positions[id],
            reason: id,
          );
        }
        expect(controller.cameraRevision.value, cameraRevision);
        expect(controller.cameraScale, cameraScale);
        expect(m.field.layoutReconciliationCount, reconciliations);
        expect(controller.relayoutInvocationCount, layoutRuns);
        expect(m.field.state.composition, same(composition));
      });
    },
  );
}
