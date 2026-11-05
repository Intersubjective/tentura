import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_field_unread_glow_layer.dart';
import 'package:tentura/features/graph/domain/entity/graph_mode.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_legend_content.dart';
import 'package:tentura/features/graph/ui/widget/graph_legend_mode.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../graph/scene_layout_test_support.dart';

void main() {
  tearDown(ConstellationFieldUnreadGlowAtlas.resetForTest);

  test('ConstellationFieldUnreadGlowPainter draws glow sites', () {
    final frame = ConstellationPresentationFrame(
      snapshot: 'test',
      cameraRevision: 0,
      detail: ConstellationDetailLevel.close,
      paintOrder: const ['unread'],
      bodies: {
        'unread': Rect.fromCircle(center: const Offset(50, 50), radius: 20),
      },
      labels: const {},
      tapTargets: const {},
      chips: const {},
      forcedLabels: const {},
    );
    final atlas = ConstellationFieldUnreadGlowAtlas.instance;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    ConstellationFieldUnreadGlowPainter(
      frame: frame,
      glowSites: const {
        'unread': (authorId: 'author', opacity: 1),
      },
      colorForAuthor: (_) => const Color(0xFF625B71),
      atlas: atlas,
      spread: 2.15,
      alphaDark: 0.34,
      alphaLight: 0.26,
      unreadDotSize: 10,
      unreadDotColor: Colors.blue,
      isDark: false,
      highContrast: false,
      pulseBoost: 1,
    ).paint(canvas, const Size(200, 100));
    expect(recorder.endRecording(), isNotNull);
  });

  testWidgets('legend lists Unread row', (tester) async {
    await _pumpLegendContent(tester);
    expect(
      find.byKey(const ValueKey('constellation.legend.fieldUnread')),
      findsOneWidget,
    );
    expect(find.text('Unread'), findsOneWidget);
  });

  testWidgets('375×667 RU: legend shows Непрочитанное without overflow', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final graphCubit = _StubGraphCubit();
    addTearDown(graphCubit.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
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
    expect(find.text('Непрочитанное'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('constellationNodeSemanticLabel marks unread request', () {
    // Covered via constellation_node_semantics import in store tests; pin string shape.
    final l10n = lookupL10n(const Locale('en'));
    expect(
      l10n.constellationFieldUnreadBeaconSemantics('Request: Roof'),
      'Request: Roof, unread',
    );
    expect(
      l10n.constellationFieldUnreadAuthorSemantics('Maria'),
      'Maria, has unread',
    );
  });
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

class _StubGraphCubit extends Cubit<GraphState> implements GraphCubit {
  _StubGraphCubit()
    : super(
        const GraphState(
          me: Profile(
            id: 'Uviewer',
            displayName: 'Viewer',
            score: 3,
            rScore: 3,
          ),
          focus: '',
          isAnimated: false,
        ),
      );

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
  String get originNodeId => 'Uviewer';

  @override
  void selectNode(NodeDetails node, {bool ensureStructuralEdges = true}) {}

  @override
  Future<void> expandNode(NodeDetails node) async {}

  @override
  bool canExpandNode(String id) => false;

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
