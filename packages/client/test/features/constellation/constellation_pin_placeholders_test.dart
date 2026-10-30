import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/gql/_g/constellation_anchors_fetch.data.gql.dart';
import 'package:tentura/features/constellation/data/gql/_g/constellation_field_fetch.data.gql.dart';
import 'package:tentura/features/constellation/data/model/constellation_field_mapper.dart';
import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_request_preview_sheet.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_text_view.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_composer_screen_harness.dart';
import '../../support/constellation_store_fixture.dart';
import '../../support/test_realtime_sync.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_block_case.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _id = 'Bplaceholder';
const _states = [
  'noAccess',
  'unpublished',
  'deleted',
  'tombstone',
  'blockedByMe',
];

Map<String, Object?> _wire(
  String pinState, {
  bool isMine = false,
  bool withBlockedPerson = false,
  bool withImage = true,
}) => {
  'constellationField': {
    'loadedAt': '2026-10-30T00:00:00Z',
    'context': '',
    'peersCapped': false,
    'requestsCapped': false,
    'directContactIds': <String>[],
    'peers': <Object>[],
    'edges': <Object>[],
    'requests': <Object>[],
    'posts': <Object>[],
    'memberWebs': <Object>[],
    'anchorProjection': {
      'revision': '1',
      'anchors': [
        if (withBlockedPerson)
          {
            'targetKind': 'PERSON',
            'targetId': 'blocked',
            'xUnits': -2.0,
            'yUnits': 1.0,
            'coordinateSpaceVersion': 1,
            'revision': '1',
            'placedAt': '2026-10-30T00:00:00Z',
          },
        {
          'targetKind': 'BEACON',
          'targetId': _id,
          'xUnits': 2.0,
          'yUnits': 1.0,
          'coordinateSpaceVersion': 1,
          'revision': '1',
          'placedAt': '2026-10-30T00:00:00Z',
        },
      ],
      'pinnedPeers': [
        if (withBlockedPerson)
          {
            'id': 'blocked',
            'displayName': 'Blocked person',
            'pinState': 'blockedByMe',
            'visible': false,
            'presence': 'pinnedOnly',
            'temporaryBeaconId': null,
            'bondContexts': <Object>[],
            'image': withImage
                ? {
                    'id': 'avatar',
                    'hash': 'hash',
                    'width': 100,
                    'height': 100,
                    'author_id': 'blocked',
                    'created_at': '2026-10-30',
                  }
                : null,
          },
      ],
      'pinnedRequests': [
        {
          'id': _id,
          'pinState': pinState,
          'authorId': isMine ? 'ego' : '',
          'title': isMine ? 'My draft' : '',
          'status': isMine ? 3 : 0,
          'needs': <String>[],
          'hasCoordinates': false,
          'isMine': isMine,
          'viewerHasActiveHelpOffer': false,
          'viewerIsRoomParticipant': false,
          'viewerHasForwardEdge': false,
          'helpOfferCount': 0,
          'coverSource': 0,
          'coverThumb': null,
          'parentBeaconId': null,
        },
      ],
      'supportPeers': <Object>[],
      'supportEdges': <Object>[],
      'serverFilteredBeaconIds': <String>[],
      'serverFilteredBeaconCount': 0,
    },
  },
};

ConstellationField _decode(
  String state, {
  bool anchors = false,
  bool isMine = false,
  bool withBlockedPerson = false,
  bool withImage = true,
}) {
  final wire = _wire(
    state,
    isMine: isMine,
    withBlockedPerson: withBlockedPerson,
    withImage: withImage,
  );
  return anchors
      ? mapConstellationFieldFromAnchorsFetch(
          GConstellationAnchorsFetchData.fromJson(wire)!.constellationField,
        )
      : mapConstellationFieldFromFieldFetch(
          GConstellationFieldFetchData.fromJson(wire)!.constellationField,
        );
}

class _Repository implements ConstellationRepositoryPort {
  _Repository(this.field);
  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

class _AnchorRepository implements ConstellationAnchorRepositoryPort {
  final operations = <ConstellationAnchorApplyOp>[];

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) async {
    operations.addAll(ops);
    final revision = ConstellationAnchorRevision(BigInt.two);
    return ConstellationAnchorApplyResult(
      beforeRevision: ConstellationAnchorRevision(BigInt.one),
      afterRevision: revision,
      results: [
        for (final op in ops)
          ConstellationAnchorOpResult(
            clientOpId: op.clientOpId,
            status: ConstellationAnchorOpStatus.ok,
            target: op.target,
            resultingTargetRevision: revision,
          ),
      ],
    );
  }

  @override
  Future<ConstellationAnchorResetResult> reset({
    required String clientOpId,
    bool saveHistory = false,
  }) => throw UnsupportedError('reset');
  @override
  Future<String> saveLayoutSnapshot({
    required String reason,
    required String clientOpId,
  }) => throw UnsupportedError('save');
  @override
  Future<String> restoreLayoutSnapshot({
    required String snapshotId,
    required String clientOpId,
  }) => throw UnsupportedError('restore');
}

Future<({ConstellationCubit cubit, _AnchorRepository anchors})> _load(
  ConstellationField field,
) async {
  final sync = buildTestRealtimeSync();
  final fixture = ConstellationStoreFixture(
    _Repository(field),
    accountId: 'ego',
    realtime: sync.case_,
  );
  final anchors = _AnchorRepository();
  final placement = ConstellationPlacementCase(
    anchors,
    fixture.store,
    FakeClockPort(),
    FakeWakeUpPort(),
    realtime: sync.case_,
    recordAutomaticHistory: false,
    env: const Env.fromEnvironment(),
    logger: Logger('PinPlaceholdersTest'),
  );
  final cubit = ConstellationCubit(
    case_: fixture.store,
    viewer: const Profile(id: 'ego', displayName: 'Ego'),
    anchorCase: ConstellationAnchorCase(
      env: const Env.fromEnvironment(),
      logger: Logger('PinPlaceholdersTest'),
    ),
    placementCase: placement,
    loadOnCreate: false,
  );
  addTearDown(() async {
    await cubit.close();
    await placement.dispose();
    await sync.port.dispose();
  });
  await cubit.load();
  return (cubit: cubit, anchors: anchors);
}

Future<void> _pump(
  WidgetTester tester,
  ConstellationCubit cubit,
  Widget child, {
  String locale = 'en',
}) async {
  await tester.pumpPeopleTagsWidget(
    MaterialApp(
      locale: Locale(locale),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ConstellationCubit>.value(value: cubit),
            BlocProvider<GraphPersonContextCubit>(
              create: (_) => ComposerHarnessContextCubit(),
            ),
            BlocProvider<ScreenCubit>(
              create: (_) => ScreenCubit(FakeUiEffectPort()),
            ),
          ],
          child: Scaffold(body: child),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  for (final state in _states) {
    for (final anchors in [false, true]) {
      test(
        '${anchors ? 'ANCHORS' : 'FULL'} decodes a content-free $state pin without an author node',
        () {
          final field = _decode(state, anchors: anchors);
          final request = field.resolvedAnchorProjection.pinnedRequests.single;
          expect(request.pinState, state);
          expect(request.isPlaceholder, isTrue);
          expect(request.title, isEmpty);
          expect(request.authorId, isEmpty);
          expect(request.needs, isEmpty);
          expect(request.coverThumb, isNull);
          expect(request.parentBeaconId, isNull);
          final composed = composeConstellationPresentation(
            viewerId: 'ego',
            field: field,
            localFilters: (
              capabilitySlugs: {'transport'},
              location: LocationFilter.hasLocation,
              timing: timingFilterWithinDays(1),
              includeUnspecified: false,
            ),
            asOfUtc: field.loadedAt,
            labelBudget: (perPerson: 1, total: 1),
          );
          expect(composed.eligibleRequestIds, contains(_id));
          expect(composed.labelPlan.drawnRequestIds, contains(_id));
          expect(composed.beaconNodes.single.request, request);
          expect(composed.labelPlan.layoutRequestsByAuthor, isEmpty);
          expect(composed.keptPeerIds, isNot(contains('')));
          expect(composed.paths.parent.keys, isNot(contains('')));
          expect(composed.anchorOverlay.anchors.single.position.xUnits, 2);
          expect(composed.anchorOverlay.anchors.single.position.yUnits, 1);
        },
      );
    }

    for (final locale in ['en', 'ru']) {
      testWidgets(
        '$state preview explains the state in $locale and offers only Unpin',
        (tester) async {
          final field = _decode(state);
          final harness = await _load(field);
          final cubit = harness.cubit;
          final request = field.resolvedAnchorProjection.pinnedRequests.single;
          var opens = 0;
          var offers = 0;
          var forwards = 0;
          await _pump(
            tester,
            cubit,
            ConstellationRequestPreviewSheet(
              request: request,
              authorDisplayName: 'Private author',
              onOpen: () => opens++,
              onPrimaryAction: () => offers++,
              onForward: () => forwards++,
            ),
            locale: locale,
          );
          expect(
            find.byKey(const Key('constellation.pin_placeholder')),
            findsOneWidget,
          );
          expect(find.byIcon(Icons.lock_outline), findsOneWidget);
          final button = find.byKey(
            TestIds.key(TestIds.constellationUnpinTarget),
          );
          expect(button, findsOneWidget);
          expect(find.byType(OutlinedButton), findsOneWidget);
          expect(find.byType(FilledButton), findsNothing);
          expect(find.text('Private author'), findsNothing);
          final l10n = L10n.of(tester.element(button))!;
          final explanation = switch (state) {
            'unpublished' => l10n.constellationPinUnpublishedExplanation,
            'deleted' || 'tombstone' => l10n.constellationPinDeletedExplanation,
            'blockedByMe' => l10n.constellationPinBlockedExplanation,
            _ => l10n.constellationPinNoAccessExplanation,
          };
          expect(find.text(explanation), findsOneWidget);
          await tester.tap(button);
          await tester.pump();
          expect(harness.anchors.operations, hasLength(1));
          expect(
            harness.anchors.operations.single.kind,
            ConstellationAnchorOpKind.delete,
          );
          expect(
            harness.anchors.operations.single.target,
            ConstellationAnchorTarget.beacon(_id),
          );
          expect(
            cubit.isAnchored(ConstellationAnchorTarget.beacon(_id)),
            isFalse,
          );
          expect(opens + offers + forwards, 0);
        },
      );
    }
  }

  for (final anchors in [false, true]) {
    test(
      '${anchors ? 'ANCHORS' : 'FULL'} preserves a viewer-blocked person name and avatar',
      () {
        final field = _decode(
          'noAccess',
          anchors: anchors,
          withBlockedPerson: true,
        );
        final person = field.resolvedAnchorProjection.pinnedPeers.single;
        expect(person.pinState, 'blockedByMe');
        expect(person.visible, isFalse);
        expect(person.displayName, 'Blocked person');
        expect(person.image?.id, 'avatar');
      },
    );
  }

  testWidgets('a viewer-blocked person stays on the map with a Blocked mark', (
    tester,
  ) async {
    final harness = await _load(
      _decode('noAccess', withBlockedPerson: true, withImage: false),
    );
    final cubit = harness.cubit;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(
      tester,
      cubit,
      ConstellationBody(legendExpanded: false, onToggleLegend: () {}),
    );
    final person = cubit.graphController.nodes
        .whereType<FieldPersonNode>()
        .singleWhere((p) => p.id == 'blocked');
    expect(person.person.shownName, 'Blocked person');
    expect(
      find.byKey(TestIds.key(TestIds.graphNode('blocked'))),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('constellation.pin_state.blockedByMe')),
      findsOneWidget,
    );
    expect(
      cubit.state.composition?.paths.parent.containsKey('blocked'),
      isFalse,
    );
  });

  for (final locale in ['en', 'ru']) {
    testWidgets('$locale blocked person map sheet offers Unblock and Unpin', (
      tester,
    ) async {
      final blocks = FakeBlockCase();
      GetIt.I.registerSingleton<BlockCase>(blocks);
      addTearDown(() => GetIt.I.unregister<BlockCase>());
      final harness = await _load(
        _decode('noAccess', withBlockedPerson: true, withImage: false),
      );
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(
        tester,
        harness.cubit,
        ConstellationBody(legendExpanded: false, onToggleLegend: () {}),
        locale: locale,
      );
      await tester.tap(find.byKey(TestIds.key(TestIds.graphNode('blocked'))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final l10n = await L10n.delegate.load(Locale(locale));
      expect(find.text(l10n.unblockUserMenuItem), findsOneWidget);
      expect(find.text(l10n.constellationUnpinTarget), findsOneWidget);
      expect(
        find.byKey(TestIds.key(TestIds.graphPersonContextTrust)),
        findsNothing,
      );
      expect(
        find.byKey(TestIds.key(TestIds.graphPersonContextSendRequest)),
        findsNothing,
      );
      expect(
        find.byKey(TestIds.key(TestIds.graphPersonContextRequestOptions)),
        findsNothing,
      );
      await tester.tap(find.text(l10n.unblockUserMenuItem));
      await tester.pump();
      expect(blocks.unblockCalls, ['blocked']);
    });
  }

  test('an author-owned unpublished pin stays a readable draft', () {
    final request = _decode(
      'unpublished',
      isMine: true,
    ).resolvedAnchorProjection.pinnedRequests.single;
    expect(request.isPlaceholder, isFalse);
    expect(request.title, 'My draft');
    expect(request.authorId, 'ego');
  });

  testWidgets(
    'a placeholder stays on the map, opens its explanation and has no text-view content',
    (tester) async {
      final field = _decode('noAccess').copyWith(
        requests: const [
          ConstellationRequest(
            id: _id,
            authorId: 'old-author',
            title: 'Private old title',
            status: 0,
          ),
          ConstellationRequest(
            id: 'Bvisible',
            authorId: 'ego',
            title: 'Visible Request',
            status: 0,
            isMine: true,
          ),
        ],
      );
      final harness = await _load(field);
      final cubit = harness.cubit;
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(
        tester,
        cubit,
        ConstellationBody(legendExpanded: false, onToggleLegend: () {}),
      );
      final node = cubit.graphController.nodes
          .whereType<FieldBeaconNode>()
          .singleWhere((node) => node.id == _id);
      expect(node.request?.isPlaceholder, isTrue);
      expect(cubit.canDragNode(node), isFalse);
      final marker = find.byKey(TestIds.key(TestIds.graphNode(_id)));
      expect(marker, findsOneWidget);
      await tester.tap(marker);
      await tester.pump();
      expect(cubit.state.selectedRequestId, _id);
      expect(
        find.byKey(const Key('constellation.pin_placeholder')),
        findsOneWidget,
      );
      expect(
        find.byKey(TestIds.key(TestIds.constellationUnpinTarget)),
        findsOneWidget,
      );
      expect(cubit.discoverableRequestsForPerson('old-author'), isEmpty);
      expect(cubit.requestById(_id)?.isPlaceholder, isTrue);
      cubit.setViewMode(ConstellationViewMode.text);
      await _pump(tester, cubit, const ConstellationTextView());
      expect(find.byType(ConstellationTextView), findsOneWidget);
      expect(
        find.byKey(const Key('constellation.text.request.$_id')),
        findsNothing,
      );
      expect(find.text(_id), findsNothing);
      expect(find.text('Private old title'), findsNothing);
      expect(find.text('Visible Request'), findsOneWidget);
    },
  );
}
