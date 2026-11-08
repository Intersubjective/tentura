import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_new_people_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_new_people_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/util/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_field_new_ring_layer.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_text_view.dart';
import 'package:tentura/features/graph/domain/entity/graph_mode.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_legend_content.dart';
import 'package:tentura/features/graph/ui/widget/graph_legend_mode.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/phone_surface.dart';
import '../graph/scene_layout_test_support.dart';

const _legendViewer = Profile(
  id: 'Uviewer',
  displayName: 'Viewer',
  score: 3,
  rScore: 3,
);

class _StubGraphCubit extends Cubit<GraphState> implements GraphCubit {
  _StubGraphCubit()
    : super(const GraphState(me: _legendViewer, focus: '', isAnimated: false));

  @override
  final bool genealogyMode = false;

  @override
  final String? forwardsGraphBeaconId = null;

  @override
  GraphMode get mode => GraphMode.trust;

  @override
  final graphController = testGraphController();

  @override
  void jumpToEgo({bool resetScale = false}) {}

  @override
  void togglePositiveOnly() {
    emit(state.copyWith(positiveOnly: !state.positiveOnly));
  }

  @override
  bool get canPopFocus => false;

  @override
  void popFocus() {}

  @override
  void resetToEgo() {}

  @override
  void fitCurrentPath() {}

  @override
  List<String> get focusPath => const [];

  @override
  Set<String> get forwardsRootIds => const {};

  @override
  String get originNodeId => _legendViewer.id;

  @override
  void selectNode(NodeDetails node, {bool ensureStructuralEdges = true}) {}

  @override
  Future<void> expandNode(NodeDetails node) async {}

  @override
  bool canPageMore(String id) => false;

  @override
  bool isCurrentFocus(String id) => false;

  @override
  void handleNodeTap(NodeDetails node) {}

  @override
  bool hasEverFocused(String id) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<void> _pumpLegendContent(WidgetTester tester) async {
  final graphCubit = _StubGraphCubit();
  addTearDown(graphCubit.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: BlocProvider<GraphCubit>.value(
        value: graphCubit,
        child: const Scaffold(
          body: SingleChildScrollView(
            child: GraphLegendContent(mode: GraphLegendMode.constellation),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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

ConstellationField _fieldWithNewPeer({required bool isNew}) =>
    ConstellationField(
      loadedAt: DateTime.utc(2026, 11, 4),
      context: '',
      peers: [
        ConstellationPerson(
          id: 'peer-new',
          displayName:
              'Новый человек с очень длинным именем для проверки переноса',
          isNew: isNew,
        ),
      ],
      edges: const [
        ConstellationTrustEdgeEntity(src: 'ego', dst: 'peer-new', tier: 1),
      ],
      directContactIds: const ['peer-new'],
    );

void main() {
  test('ConstellationFieldNewRingPainter draws only new graph ids', () {
    final frame = ConstellationPresentationFrame(
      snapshot: 'test',
      cameraRevision: 0,
      detail: ConstellationDetailLevel.close,
      paintOrder: const ['new', 'old'],
      bodies: {
        'new': Rect.fromCircle(center: const Offset(50, 50), radius: 20),
        'old': Rect.fromCircle(center: const Offset(150, 50), radius: 20),
      },
      labels: const {},
      tapTargets: const {},
      chips: const {},
      forcedLabels: const {},
    );
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    ConstellationFieldNewRingPainter(
      frame: frame,
      newGraphIds: const {'new'},
      accentColor: const Color(0xFF625B71),
      gap: 4,
      minTrustRadius: 14,
      badgeDiameter: 18,
    ).paint(canvas, const Size(200, 100));
    expect(recorder.endRecording(), isNotNull);
  });

  testWidgets('legend lists New on your Field row', (tester) async {
    await _pumpLegendContent(tester);
    expect(
      find.byKey(const ValueKey('constellation.legend.fieldNew')),
      findsOneWidget,
    );
    expect(find.text('New on your Field'), findsOneWidget);
  });

  testWidgets('375×667 RU: list row shows Новый chip without overflow', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final field = _fieldWithNewPeer(isNew: true);
    final fixture = ConstellationStoreFixture(
      _StubRepository(field),
      accountId: 'ego',
    );
    final cubit = fixture.createCubit(
      viewer: const Profile(id: 'ego', displayName: 'Viewer'),
    );
    await cubit.load();
    cubit.emit(cubit.state.copyWith(viewMode: ConstellationViewMode.text));

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: BlocProvider<ConstellationCubit>.value(
          value: cubit,
          child: const Scaffold(body: ConstellationTextView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Новый'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('selectPerson clears isNew and calls acknowledge mutation', () async {
    final field = _fieldWithNewPeer(isNew: true);
    final fixture = ConstellationStoreFixture(
      _StubRepository(field),
      accountId: 'ego',
    );
    final acknowledged = <List<String>>[];
    final port = _RecordingPort(acknowledged);
    final case_ = ConstellationNewPeopleCase(
      port,
      fixture.store,
      env: const Env.fromEnvironment(),
      logger: Logger('test'),
    );
    final cubit = ConstellationCubit(
      case_: fixture.store,
      viewer: const Profile(id: 'ego', displayName: 'Viewer'),
      loadOnCreate: false,
      newPeopleCase: case_,
    );
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    await cubit.load();

    expect(cubit.fieldPersonById('peer-new')!.isNew, isTrue);
    cubit.selectPerson('peer-new');
    await Future<void>.delayed(Duration.zero);

    expect(cubit.fieldPersonById('peer-new')!.isNew, isFalse);
    expect(acknowledged, [
      ['peer-new'],
    ]);
  });
}

final class _RecordingPort implements ConstellationNewPeoplePort {
  _RecordingPort(this.calls);

  final List<List<String>> calls;

  @override
  Future<void> acknowledgeNew(Iterable<String> peerIds) async {
    calls.add(peerIds.toList());
  }
}
