// Field presence rendering with the field membership gate on: a temporary
// person's node has a dashed outline, and the person panel says why a bond or
// temporary person is on the field.

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
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/constellation_store_fixture.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../../support/people_tags_widget_harness.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');

final _loadedAt = DateTime.utc(2026, 10, 25, 12);

class _MutableRepository implements ConstellationRepositoryPort {
  _MutableRepository(this.field);

  ConstellationField field;

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

/// Everyone holds a Request of their own, so each stays on the field whatever
/// the membership gate says; only the presence rendering is under test.
const _requests = [
  ConstellationRequest(
    id: 'B-roof',
    authorId: 'author',
    title: 'Fix the roof',
    status: 0,
  ),
  ConstellationRequest(
    id: 'B-piano',
    authorId: 'author',
    title: 'Move the piano',
    status: 0,
  ),
  ConstellationRequest(
    id: 'R-visible',
    authorId: 'visible',
    title: 'Borrow a ladder',
    status: 0,
  ),
  ConstellationRequest(
    id: 'R-bond',
    authorId: 'bond',
    title: 'Paint the fence',
    status: 0,
  ),
  ConstellationRequest(
    id: 'R-temporary',
    authorId: 'temporary',
    title: 'Seed tray swap',
    status: 0,
  ),
];

const _people = [
  ConstellationPerson(id: 'author', displayName: 'Ada'),
  ConstellationPerson(id: 'visible', displayName: 'Vera'),
  ConstellationPerson(
    id: 'bond',
    displayName: 'Boris',
    fieldMembership: ConstellationFieldMembership.bond,
    bondContexts: [
      ConstellationBondContext(beaconId: 'B-roof', title: 'Fix the roof'),
      ConstellationBondContext(beaconId: 'B-piano', title: 'Move the piano'),
    ],
  ),
  ConstellationPerson(
    id: 'temporary',
    displayName: 'Tamsin',
    fieldMembership: ConstellationFieldMembership.temporary,
    temporaryBeaconId: 'B-piano',
  ),
];

ConstellationField _field({List<ConstellationPerson> people = _people}) =>
    ConstellationField(
      loadedAt: _loadedAt,
      context: '',
      peers: people,
      edges: [
        for (final person in people)
          ConstellationTrustEdgeEntity(src: 'ego', dst: person.id, tier: 1),
      ],
      directContactIds: [for (final person in people) person.id],
      requests: _requests,
    );

Finder _outline(String personId) => find.byKey(
  TestIds.key(TestIds.constellationTemporaryOutline(personId)),
);

Finder _inPanel(Finder matching) => find.descendant(
  of: find.byType(GraphPersonContextPanel),
  matching: matching,
);

/// A [Text] in the person panel whose text holds every one of [parts].
Finder _panelLine(List<String> parts) => _inPanel(
  find.byWidgetPredicate((widget) {
    if (widget is! Text) return false;
    final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
    return parts.every(text.contains);
  }),
);

/// Whether the node's outline is painted as dashes: some path it draws is
/// broken into many separate strokes (a solid ring is one contour or a
/// circle draw call).
bool _paintsDashedPath(Symbol method, List<dynamic> arguments) {
  if (method != #drawPath) return false;
  final path = arguments.first as Path;
  return path.computeMetrics().length >= 6;
}

void main() {
  late _MutableRepository repository;
  late ConstellationCubit cubit;

  Future<void> mount(
    WidgetTester tester, {
    required bool gate,
    ConstellationField? field,
  }) async {
    repository = _MutableRepository(field ?? _field());
    cubit = ConstellationCubit(
      case_: ConstellationStoreFixture(repository, accountId: _ego.id).store,
      viewer: _ego,
      fieldMembershipV2Enabled: gate,
    );
    addTearDown(cubit.close);
    await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
    cubit.updateLabelBudgetContext(
      viewport: const Size(1200, 900),
      textScaleFactor: 1,
    );
    final lens = ConstellationTagLensCubit();
    addTearDown(lens.close);
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpPeopleTagsWidget(
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
              fieldMembershipV2Enabled: gate,
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
  }

  Future<void> select(WidgetTester tester, String personId) async {
    cubit.selectPerson(personId);
    await _settle(tester);
  }

  group('dashed outline of a temporary person', () {
    testWidgets('only the temporary person has one with the gate on', (
      tester,
    ) async {
      await mount(tester, gate: true);

      expect(
        find.byKey(TestIds.key(TestIds.graphNode('temporary'))),
        findsOneWidget,
        reason: 'positive control',
      );
      expect(_outline('temporary'), findsOneWidget);
      expect(
        tester.renderObject(_outline('temporary')),
        paints..something(_paintsDashedPath),
        reason: 'the outline is drawn as dashes, not a solid ring',
      );
      expect(_outline('visible'), findsNothing);
      expect(_outline('bond'), findsNothing);
      expect(_outline('author'), findsNothing);
    });

    testWidgets('no node is outlined with the gate off', (tester) async {
      await mount(tester, gate: false);

      expect(
        find.byKey(TestIds.key(TestIds.graphNode('temporary'))),
        findsOneWidget,
        reason: 'positive control',
      );
      for (final id in ['temporary', 'visible', 'bond', 'author']) {
        expect(_outline(id), findsNothing, reason: id);
      }
    });

    testWidgets('disappears after a field update without the person', (
      tester,
    ) async {
      await mount(tester, gate: true);
      expect(_outline('temporary'), findsOneWidget, reason: 'positive control');

      repository.field = _field(
        people: [
          for (final p in _people)
            if (p.id != 'temporary') p,
        ],
      );
      await cubit.load();
      await _settle(tester);

      expect(
        find.byKey(TestIds.key(TestIds.graphNode('temporary'))),
        findsNothing,
      );
      expect(_outline('temporary'), findsNothing);
    });

    testWidgets('goes away when the person is no longer temporary', (
      tester,
    ) async {
      await mount(tester, gate: true);
      expect(_outline('temporary'), findsOneWidget, reason: 'positive control');

      repository.field = _field(
        people: [
          for (final p in _people)
            if (p.id == 'temporary')
              const ConstellationPerson(id: 'temporary', displayName: 'Tamsin')
            else
              p,
        ],
      );
      await cubit.load();
      await _settle(tester);

      expect(
        find.byKey(TestIds.key(TestIds.graphNode('temporary'))),
        findsOneWidget,
      );
      expect(_outline('temporary'), findsNothing);
    });
  });

  group('person panel presence lines', () {
    testWidgets('a bond person: working together on the first Request title', (
      tester,
    ) async {
      await mount(tester, gate: true);
      await select(tester, 'bond');

      expect(_inPanel(find.text('Boris')), findsWidgets);
      expect(
        _panelLine(['Working together on', 'Fix the roof']),
        findsOneWidget,
      );
      expect(_inPanel(find.textContaining('Move the piano')), findsNothing);
      expect(_panelLine(['Temporary']), findsNothing);
    });

    testWidgets('a temporary person: the temporary line names their Request', (
      tester,
    ) async {
      await mount(tester, gate: true);
      await select(tester, 'temporary');

      expect(_inPanel(find.text('Tamsin')), findsWidgets);
      // The temporary copy ("Temporary: you see each other while “…” is
      // open") names the Request that made them visible, in the same line.
      expect(_panelLine(['Temporary', 'Move the piano']), findsOneWidget);
      expect(_inPanel(find.textContaining('Fix the roof')), findsNothing);
      expect(
        _inPanel(find.textContaining('Working together on')),
        findsNothing,
      );
    });

    testWidgets('a visible person has no presence line', (tester) async {
      await mount(tester, gate: true);
      await select(tester, 'visible');

      expect(_inPanel(find.text('Vera')), findsWidgets);
      expect(
        _inPanel(find.textContaining('Working together on')),
        findsNothing,
      );
      expect(_panelLine(['Temporary']), findsNothing);
      for (final title in ['Fix the roof', 'Move the piano']) {
        expect(
          _inPanel(find.textContaining(title)),
          findsNothing,
          reason: title,
        );
      }
    });

    testWidgets('the gate off hides every presence line', (tester) async {
      await mount(tester, gate: false);

      for (final id in ['bond', 'temporary']) {
        await select(tester, id);
        expect(_inPanel(find.byType(Text)), findsWidgets, reason: 'panel $id');
        expect(
          _inPanel(find.textContaining('Working together on')),
          findsNothing,
          reason: id,
        );
        expect(_panelLine(['Temporary']), findsNothing, reason: id);
        for (final title in ['Fix the roof', 'Move the piano']) {
          expect(
            _inPanel(find.textContaining(title)),
            findsNothing,
            reason: '$id shows "$title"',
          );
        }
      }
    });
  });
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}
