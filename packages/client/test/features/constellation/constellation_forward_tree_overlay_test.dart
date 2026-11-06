// #774 31ve.6: forward tree on Field (overlay, replay, arrange, preview).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_forward_tree_scene_layout.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_request_preview_sheet.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_graph.dart';
import 'package:tentura/features/forward/domain/entity/forward_recipient_offer_status.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';
import '../../support/test_forward_case.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _viewer = Profile(id: 'ego', displayName: 'Ego');

const _beaconId = 'req-am-1';
const _authorId = 'am';
const _b = 'in';
const _v = 'sm';
const _r = 'ego';
const _d = 'off-d';
const _k = 'off-k';
const _l = 'off-l';

final class _StubRepo implements ConstellationRepositoryPort {
  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async =>
      constellationReferenceField();
}

final class _GraphForwardRepo implements ForwardRepository {
  _GraphForwardRepo(this._graph);

  final ForwardGraph _graph;

  @override
  Future<ForwardGraph> fetchForwardGraph({required String beaconId}) async {
    expect(beaconId, _beaconId);
    return _graph;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Six-edge tree: A=am, B=in, V=sm (helper), R=ego, D/K/L off-field except R on field.
ForwardGraph _sixEdgeGraph() {
  final t = DateTime.utc(2026, 11, 6, 12);
  return ForwardGraph(
    beaconId: _beaconId,
    authorId: _authorId,
    helpOffererIds: {_v},
    edges: [
      ForwardGraphEdge(
        id: 'e-ab',
        beaconId: _beaconId,
        senderId: _authorId,
        recipientId: _b,
        createdAt: t,
        senderDisplayName: 'Anna',
        recipientDisplayName: 'Boris',
      ),
      ForwardGraphEdge(
        id: 'e-bv',
        beaconId: _beaconId,
        senderId: _b,
        recipientId: _v,
        parentEdgeId: 'e-ab',
        createdAt: t.add(const Duration(seconds: 1)),
        offerStatus: ForwardRecipientOfferStatus.accepted,
        senderDisplayName: 'Boris',
        recipientDisplayName: 'Vera',
      ),
      ForwardGraphEdge(
        id: 'e-ar',
        beaconId: _beaconId,
        senderId: _authorId,
        recipientId: _r,
        createdAt: t.add(const Duration(seconds: 2)),
        senderDisplayName: 'Anna',
        recipientDisplayName: 'Ego',
      ),
      ForwardGraphEdge(
        id: 'e-bd',
        beaconId: _beaconId,
        senderId: _b,
        recipientId: _d,
        parentEdgeId: 'e-ab',
        createdAt: t.add(const Duration(seconds: 3)),
        declinedInvite: true,
        senderDisplayName: 'Boris',
        recipientDisplayName: 'Dan',
      ),
      ForwardGraphEdge(
        id: 'e-bk',
        beaconId: _beaconId,
        senderId: _b,
        recipientId: _k,
        parentEdgeId: 'e-ab',
        createdAt: t.add(const Duration(seconds: 4)),
        forwardedOn: false,
        senderDisplayName: 'Boris',
        recipientDisplayName: 'Kim',
      ),
      ForwardGraphEdge(
        id: 'e-rl',
        beaconId: _beaconId,
        senderId: _r,
        recipientId: _l,
        parentEdgeId: 'e-ar',
        createdAt: t.add(const Duration(seconds: 5)),
        senderDisplayName: 'Ego',
        recipientDisplayName: 'Lee',
      ),
    ],
  );
}

Future<ConstellationCubit> _cubit({
  required ForwardRepository forwardRepo,
  bool? reduceMotionOverride,
}) async {
  final fixture = ConstellationStoreFixture(_StubRepo(), accountId: _viewer.id);
  await fixture.ready();
  final cubit = fixture.createCubit(
    viewer: _viewer,
    forwardCase: buildTestForwardCase(forwardRepo),
  );
  if (reduceMotionOverride != null) {
    cubit.reduceMotionMediaOverrideForTest = reduceMotionOverride;
  }
  await cubit.load();
  expect(cubit.state.status, isA<StateIsSuccess>());
  return cubit;
}

bool _hasTempOutline(ConstellationCubit cubit, String personId) =>
    cubit.forwardTreeTemporaryOutlinePersonIds.contains(personId);

ConstellationCubit _previewCubit() {
  final fixture = ConstellationStoreFixture(_StubRepo(), accountId: _viewer.id);
  return ConstellationCubit(
    case_: fixture.store,
    viewer: _viewer,
    loadOnCreate: false,
    forwardCase: buildTestForwardCase(_GraphForwardRepo(_sixEdgeGraph())),
  );
}

Future<void> _pumpPreview(
  WidgetTester tester, {
  required ConstellationRequest request,
  VoidCallback? onShowForwardTreeOnField,
  Locale locale = const Locale('en'),
}) async {
  final cubit = _previewCubit();
  addTearDown(() async {
    if (!cubit.isClosed) await cubit.close();
  });
  await tester.pumpPeopleTagsWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: BlocProvider<ConstellationCubit>.value(
          value: cubit,
          child: Scaffold(
            body: Center(
              child: ConstellationRequestPreviewSheet(
                request: request,
                authorDisplayName: 'Ann',
                onClose: () {},
                onShowForwardTreeOnField: onShowForwardTreeOnField,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  group('Forward tree overlay (#774)', () {
    test('edge kinds and markers for six-edge graph', () async {
      final cubit = await _cubit(
        forwardRepo: _GraphForwardRepo(_sixEdgeGraph()),
        reduceMotionOverride: true,
      );
      await cubit.enterForwardTreeMode(beaconId: _beaconId, helpOffererFocusId: _v);
      expect(cubit.state.forwardTreeOverlay?.loading, isFalse);

      expect(
        cubit.edgeKindByPair.values.where((k) => k == ConstellationEdgeKind.helpBranch).length,
        2,
      );
      expect(
        cubit.edgeKindByPair.values.where((k) => k == ConstellationEdgeKind.forwardBranch).length,
        4,
      );

      expect(
        cubit.forwardTreeRecipientMarkerByPersonId[_v]?.name,
        'helped',
      );
      expect(
        cubit.forwardTreeRecipientMarkerByPersonId[_d]?.name,
        'cantHelp',
      );
      expect(
        cubit.forwardTreeRecipientMarkerByPersonId[_k]?.name,
        'notOpened',
      );
      expect(
        cubit.forwardTreeRecipientMarkerByPersonId[_authorId],
        isNull,
      );

      await cubit.close();
    });

    test('temporary outline for off-field L, cleared after exit', () async {
      final cubit = await _cubit(
        forwardRepo: _GraphForwardRepo(_sixEdgeGraph()),
        reduceMotionOverride: true,
      );
      await cubit.enterForwardTreeMode(beaconId: _beaconId);
      expect(cubit.state.forwardTreeOverlay?.loading, isFalse);

      expect(_hasTempOutline(cubit, _l), isTrue);

      cubit.exitForwardTreeMode();
      expect(cubit.state.forwardTreeOverlay, isNull);

      expect(
        cubit.graphController.renderSnapshot.topology.nodesById.keys.where((k) => k == 'fp:$_l'),
        isEmpty,
      );

      await cubit.close();
    });

    test('«Arrange as tree» toggles radial layout algorithm on scene', () async {
      final cubit = await _cubit(
        forwardRepo: _GraphForwardRepo(_sixEdgeGraph()),
        reduceMotionOverride: true,
      );
      await cubit.enterForwardTreeMode(beaconId: _beaconId);
      expect(cubit.state.forwardTreeOverlay?.loading, isFalse);
      expect(cubit.forwardTreeLayoutAlgorithmForTest, isNull);

      cubit.toggleForwardTreeArrange();
      expect(cubit.state.forwardTreeOverlay?.arrangeAsTree, isTrue);
      expect(
        cubit.forwardTreeLayoutAlgorithmForTest,
        isA<ConstellationForwardTreeRadialLayout>(),
      );

      cubit.toggleForwardTreeArrange();
      expect(cubit.state.forwardTreeOverlay?.arrangeAsTree, isFalse);
      expect(
        cubit.forwardTreeLayoutAlgorithmForTest,
        isNull,
      );

      await cubit.close();
    });

    test('disableAnimations shows full graph immediately', () async {
      final cubit = await _cubit(
        forwardRepo: _GraphForwardRepo(_sixEdgeGraph()),
        reduceMotionOverride: true,
      );
      await cubit.enterForwardTreeMode(beaconId: _beaconId);
      expect(cubit.state.forwardTreeOverlay?.loading, isFalse);

      expect(cubit.forwardTreeVisibleEdgesForTest.length, 6);
      expect(cubit.state.forwardTreeOverlay?.replaying, isFalse);

      await cubit.close();
    });

    test('replay completes with all edges visible (real time)', () async {
      final cubit = await _cubit(
        forwardRepo: _GraphForwardRepo(_sixEdgeGraph()),
        reduceMotionOverride: false,
      );
      await cubit.enterForwardTreeMode(beaconId: _beaconId);
      expect(cubit.state.forwardTreeOverlay?.loading, isFalse);
      expect(cubit.state.forwardTreeOverlay?.replayVisibleCount, 0);

      await Future<void>.delayed(const Duration(seconds: 4));
      expect(cubit.forwardTreeVisibleEdgesForTest.length, 6);
      expect(cubit.state.forwardTreeOverlay?.replaying, isFalse);

      await cubit.close();
    });
  });

  group('Request preview: Show on Field (#774)', () {
    testWidgets('shown for chain participant, hidden otherwise', (tester) async {
      await _pumpPreview(
        tester,
        request: const ConstellationRequest(
          id: 'b1',
          authorId: 'x',
          title: 'T',
          status: 0,
          viewerHasForwardEdge: true,
        ),
        onShowForwardTreeOnField: () {},
      );
      expect(find.byKey(const Key('constellation.request_preview.forward_tree')), findsOneWidget);

      await _pumpPreview(
        tester,
        request: const ConstellationRequest(
          id: 'b2',
          authorId: 'x',
          title: 'T',
          status: 0,
        ),
      );
      expect(find.byKey(const Key('constellation.request_preview.forward_tree')), findsNothing);
    });

    testWidgets('RU 375×667 preview forward-tree row does not overflow', (tester) async {
      await usePhoneSurface(tester);
      final l10n = lookupL10n(const Locale('ru'));
      await _pumpPreview(
        tester,
        locale: const Locale('ru'),
        request: const ConstellationRequest(
          id: 'b1',
          authorId: 'x',
          title: 'Нужна помощь с переездом',
          status: 0,
          viewerHasForwardEdge: true,
        ),
        onShowForwardTreeOnField: () {},
      );
      expect(find.text(l10n.constellationPreviewShowForwardTreeOnField), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
