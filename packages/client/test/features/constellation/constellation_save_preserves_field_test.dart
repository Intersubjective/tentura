import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/repository/constellation_anchor_repository.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/placement_overlay.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/screen/constellation_screen.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/people_tags/data/repository/people_tags_repository.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_field_test_harness.dart';

class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  @override
  Stream<LazyWriteNotice> get lazyWriteNotices => const Stream.empty();

  @override
  Future<void> retryTrust([GraphTrustRevert? revert]) async {}

  _StubContextCubit() : super(const GraphPersonContextState());

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

Future<void> _pumpScreen(
  WidgetTester tester, {
  required ConstellationCubit cubit,
  required Size size,
  required Locale locale,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ConstellationCubit>.value(value: cubit),
              BlocProvider(
                create: (_) => constellationSelectionForFieldBodyTests(),
              ),
              BlocProvider(create: (_) => HomeTabReselectCubit()),
              BlocProvider<GraphPersonContextCubit>(
                create: (_) => _StubContextCubit(),
              ),
              BlocProvider<ScreenCubit>(
                create: (_) => ScreenCubit(FakeUiEffectPort()),
              ),
            ],
            child: const ConstellationScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

bool _isFullFieldFetch(WireSent request) =>
    request.operationName == 'ConstellationFieldFetch' &&
    request.variables['projection'] == 'FULL';

void _expectNoFieldLoading() {
  expect(find.byType(TenturaCircularProgress), findsNothing);
  expect(find.byType(LinearPiActive), findsNothing);
}

Future<void> _expectFiltersApplied(
  WidgetTester tester, {
  required bool phone,
}) async {
  final control = find.byKey(
    Key(phone ? 'constellation.app_bar.more' : 'constellation.app_bar.filters'),
  );
  final badge = find.descendant(of: control, matching: find.byType(Badge));
  expect(badge, findsOneWidget);
  expect(tester.widget<Badge>(badge).isLabelVisible, isTrue);
  await tester.tap(control);
  await tester.pumpAndSettle();
  if (phone) {
    await tester.tap(
      find.byKey(const Key('constellation.app_bar.more.filters')),
    );
    await tester.pumpAndSettle();
  }
  final timing = find.byKey(const Key('constellation.filter.timing.undated'));
  expect(timing, findsOneWidget);
  expect(tester.widget<FilterChip>(timing).selected, isTrue);
  expect(
    tester
        .widget<SwitchListTile>(
          find.byKey(TestIds.key(TestIds.constellationFilterShowClosed)),
        )
        .value,
    isTrue,
  );
  Navigator.of(tester.element(timing)).pop();
  await tester.pumpAndSettle();
  _expectNoFieldLoading();
}

Map<String, dynamic> _peer() => {
  '__typename': 'v2_ConstellationPeer',
  'id': 'a',
  'displayName': 'Анна',
  'contactOnly': false,
  'visible': true,
  'presence': 'visible',
  'temporaryBeaconId': null,
  'bondContexts': <dynamic>[],
  'handle': null,
  'image': null,
  'pinState': null,
  'isNew': false,
};

Map<String, dynamic> _anchor(Map<String, dynamic> position, String revision) =>
    {
      '__typename': 'v2_ConstellationAnchor',
      'targetKind': 'PERSON',
      'targetId': 'a',
      ...position,
      'coordinateSpaceVersion': 1,
      'revision': revision,
      'placedAt': '2026-11-07T11:00:00.000Z',
    };

Map<String, dynamic> _fieldWire(Map<String, dynamic> anchor) => {
  '__typename': 'query_root',
  'constellationField': {
    '__typename': 'v2_ConstellationField',
    'loadedAt': '2026-11-07T12:00:00.000Z',
    'context': '',
    'peersCapped': false,
    'requestsCapped': false,
    'directContactIds': ['a'],
    'peers': [_peer()],
    'edges': [
      {
        '__typename': 'v2_ConstellationTrustEdge',
        'src': 'ego',
        'dst': 'a',
        'tier': 1,
      },
    ],
    'requests': <dynamic>[],
    'posts': <dynamic>[],
    'memberWebs': <dynamic>[],
    'anchorProjection': {
      '__typename': 'v2_ConstellationAnchorProjection',
      'revision': anchor['revision'],
      'anchors': [anchor],
      'pinnedPeers': [_peer()],
      'pinnedRequests': <dynamic>[],
      'supportPeers': <dynamic>[],
      'supportEdges': <dynamic>[],
      'serverFilteredBeaconIds': <dynamic>[],
      'serverFilteredBeaconCount': 0,
    },
  },
};

void main() {
  for (final scenario in [
    (phone: false, fails: false),
    (phone: true, fails: false),
    (phone: false, fails: true),
    (phone: true, fails: true),
  ]) {
    final phone = scenario.phone;
    final fails = scenario.fails;
    testWidgets(
      '${fails ? 'failed placement keeps its error and arrangement' : 'saved placement keeps its anchor and arrangement'} after Done '
      '${phone ? 'at 375×667 in Russian' : 'on desktop in English'}',
      (tester) async {
        final sent = <WireSent>[];
        var anchor = _anchor({'xUnits': 1.0, 'yUnits': 1.0}, '1');
        late ConstellationCubit cubit;
        late ConstellationPlacementCase placement;
        final clock = FakeClockPort();
        final retries = FakeWakeUpPort();
        late Future<void> Function() dispose;
        late Completer<void> gate;
        late Completer<void> ready;
        late Completer<void> acknowledgement;
        late Future<void> wireRun;
        await tester.runAsync(() async {
          gate = Completer<void>();
          ready = Completer<void>();
          acknowledgement = Completer<void>();
          wireRun = withRemoteWire(
            const {},
            sent,
            (remote) async {
              final sync = buildTestRealtimeSync();
              final tags = PeopleTagsCase(
                PeopleTagsRepository(remote),
                sync.case_,
                env: const Env(),
                logger: Logger('FieldSaveTags'),
              );
              await tags.load();
              GetIt.I.registerSingleton<PeopleTagsCase>(tags);
              final store = ConstellationStoreFixture(
                ConstellationRepository(remote),
                accountId: 'ego',
                realtime: sync.case_,
              ).store;
              // Keep the real anchor repository, Ferry request/response chain
              // and generated GraphQL mapper. Only the HTTP server is stubbed.
              placement = ConstellationPlacementCase(
                ConstellationAnchorRepository(remote),
                store,
                clock,
                retries,
                realtime: sync.case_,
                env: const Env(),
                logger: Logger('FieldPlacementSave'),
              );
              cubit = ConstellationCubit(
                case_: store,
                placementCase: placement,
                viewer: const Profile(id: 'ego', displayName: 'Я'),
                loadOnCreate: false,
              );
              await cubit.load();
              dispose = () async {
                await cubit.close();
                await placement.dispose();
                await tags.dispose();
                await GetIt.I.reset();
                await sync.port.dispose();
              };
              ready.complete();
              await gate.future;
            },
            errorFor: (request) =>
                fails && request.operationName == 'ConstellationAnchorsApply'
                ? {'message': 'Server unavailable'}
                : null,
            responseFor: (request) async {
              if (request.operationName == 'ConstellationAnchorsApply') {
                await acknowledgement.future;
                final op = (request.variables['ops'] as List).single as Map;
                anchor = _anchor(
                  Map<String, dynamic>.from(op['position'] as Map),
                  '2',
                );
                return {
                  'constellationAnchorsApply': {
                    '__typename': 'v2_ConstellationAnchorsApplyResult',
                    'beforeRevision': '1',
                    'afterRevision': '2',
                    'results': [
                      {
                        '__typename': 'v2_ConstellationAnchorOpResult',
                        'clientOpId': op['clientOpId'],
                        'status': 'OK',
                        'reason': null,
                        'resultingTargetRevision': '2',
                        'anchor': anchor,
                        'replayed': false,
                      },
                    ],
                  },
                };
              }
              if (request.operationName == 'ConstellationFieldFetch' ||
                  request.operationName == 'ConstellationAnchorsFetch') {
                return _fieldWire(anchor);
              }
              if (request.operationName == 'PersonTags') {
                return {'personTags': <dynamic>[]};
              }
              if (request.operationName == 'PersonTagMemberships') {
                return {'personTagMemberships': <dynamic>[]};
              }
              if (request.operationName == 'PersonAutoTags') {
                return {'personAutoTags': <dynamic>[]};
              }
              if (request.operationName == 'PersonTagsOf') {
                return {
                  'personTagsOf': {
                    '__typename': 'PersonTagsOf',
                    'own': <dynamic>[],
                    'auto': <dynamic>[],
                  },
                };
              }
              throw StateError(
                'Unexpected operation: ${request.operationName}',
              );
            },
          );
          await Future.any([ready.future, wireRun]);
        });
        try {
          await tester.runAsync(() => cubit.setShowClosed(true));
          cubit.setFilterTiming(const TimingFilterUndated());
          if (phone) await usePhoneSurface(tester);
          await _pumpScreen(
            tester,
            cubit: cubit,
            size: phone ? kPhoneSurface : const Size(1200, 800),
            locale: Locale(phone ? 'ru' : 'en'),
          );
          await tester.pumpAndSettle();
          await _expectFiltersApplied(tester, phone: phone);
          await tester.tap(
            find.byKey(const Key('constellation.camera.arrange')),
          );
          await tester.pumpAndSettle();
          final selection = tester.constellationSelectionUnderTest();
          expect(selection.state.arranging, isTrue);
          final target = ConstellationAnchorTarget.person('a');
          selection.toggle(target);
          final selected = selection.state;
          expect(selected.contains(target), isTrue);
          await tester.pumpAndSettle();
          final graph = cubit.graphController;
          expect(
            find.byKey(const Key('constellation.selection.rings')),
            findsOneWidget,
          );
          final viewer = tester.widget<InteractiveViewer>(
            find.byType(InteractiveViewer),
          );
          viewer.transformationController!.value =
              viewer.transformationController!.value.clone()
                ..translateByDouble(35, 20, 0, 1);
          await tester.pumpAndSettle();
          final camera = viewer.transformationController!.value.clone();
          final before = cubit.state;
          final fullCount = sent.where(_isFullFieldFetch).length;
          final saveRequestOffset = sent.length;
          expect(fullCount, greaterThan(0));
          final otherPositions = {
            for (final id in graph.renderSnapshot.topology.nodesById.keys)
              if (id != 'fp:a') id: graph.getPositionOrNullForId(id),
          };
          expect(otherPositions, isNotEmpty);
          expect(otherPositions.values, everyElement(isNotNull));
          final emissions = <ConstellationState>[];
          final subscription = cubit.stream.listen(emissions.add);
          void expectNoSavePathReload() {
            expect(
              emissions.where((s) => s.status is StateIsLoading),
              isEmpty,
              reason:
                  'No loading emission is allowed from drag through acknowledgement and Done',
            );
            expect(
              sent.skip(saveRequestOffset).where(_isFullFieldFetch),
              isEmpty,
              reason:
                  'Saving through the real anchor repository and GraphQL mapper must not send a FULL Field fetch',
            );
            expect(sent.where(_isFullFieldFetch), hasLength(fullCount));
            expect(cubit.state.loadGeneration, before.loadGeneration);
          }

          addTearDown(subscription.cancel);
          final startScene = graph.getPositionOrNullForId('fp:a')!;
          final startGlobal =
              tester.getTopLeft(find.byType(InteractiveViewer)) +
              graph.sceneToViewportLocal(startScene);
          // Simulated mouse input exercises the Field's drag callback. Real
          // browser mouse/touch hit-testing remains an integration-suite gate.
          final gesture = await tester.startGesture(
            startGlobal,
            kind: PointerDeviceKind.mouse,
          );
          await gesture.moveBy(const Offset(20, 0));
          await tester.pump();
          _expectNoFieldLoading();
          await gesture.moveBy(const Offset(40, 30));
          await tester.pump();
          _expectNoFieldLoading();
          await tester.runAsync(() async {
            await gesture.up();
            await pumpEventQueue();
          });
          // Observe the drop while its real transport response is held.
          await tester.pump();
          _expectNoFieldLoading();
          expectNoSavePathReload();
          if (!fails) {
            expect(placement.current.targets, isNotEmpty);
            await tester.runAsync(() async {
              acknowledgement.complete();
              await pumpEventQueue();
            });
          }
          final firstWrite = sent.firstWhere(
            (r) => r.operationName == 'ConstellationAnchorsApply',
          );
          final sentOp = (firstWrite.variables['ops'] as List).single as Map;
          expect(sentOp['targetId'], 'a');
          expect(sentOp['kind'], 'UPSERT');
          final sentPosition = sentOp['position'] as Map;
          final expected = ConstellationAnchorPosition(
            xUnits: (sentPosition['xUnits'] as num).toDouble(),
            yUnits: (sentPosition['yUnits'] as num).toDouble(),
            coordinateSpaceVersion: 1,
          );
          final dropPoint = constellationV1AnchorToPoint(expected);
          final drop = Offset(dropPoint.x, dropPoint.y);
          expect(
            (drop - startScene).distance,
            greaterThan(10),
            reason: 'The simulated drag must actually move the saved node',
          );
          await tester.pumpAndSettle();
          _expectNoFieldLoading();
          if (fails) {
            // The outbox marks a transport failure unsaved after its existing
            // three automatic attempts; the first error remains retryable.
            for (var retry = 0; retry < 2; retry++) {
              await tester.runAsync(() async {
                clock.advance(const Duration(seconds: 60));
                retries.elapse(const Duration(seconds: 60));
                await pumpEventQueue();
              });
              await tester.pumpAndSettle();
              _expectNoFieldLoading();
            }
          }
          expect(tester.takeException(), isNull);
          expect(selection.state.arranging, isTrue);
          expect(
            sent.where((r) => r.operationName == 'ConstellationAnchorsApply'),
            hasLength(fails ? 3 : 1),
          );
          await tester.tap(
            find.byKey(const Key('constellation.arranging.done')),
          );
          await tester.pumpAndSettle();
          expect(selection.state.arranging, isFalse);
          _expectNoFieldLoading();
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(
            find.byKey(const Key('constellation.selection.rings')),
            findsOneWidget,
          );
          expect(
            sent.where(_isFullFieldFetch),
            hasLength(fullCount),
          );
          expectNoSavePathReload();
          expect(emissions, isNotEmpty);
          expect(
            emissions.map((s) => s.status),
            everyElement(isA<StateIsSuccess>()),
          );
          expect(
            emissions.map((s) => s.field),
            fails ? everyElement(same(before.field)) : everyElement(isNotNull),
          );
          expect(selection.state.targets, selected.targets);
          expect(cubit.state.selectedPersonId, before.selectedPersonId);
          expect(cubit.state.filters, before.filters);
          expect(cubit.state.membershipFilters, before.membershipFilters);
          expect(
            tester
                .widget<InteractiveViewer>(find.byType(InteractiveViewer))
                .transformationController!
                .value,
            camera,
          );
          expect(
            (graph.getPositionOrNullForId('fp:a')! - drop).distance,
            lessThan(0.01),
          );
          for (final entry in otherPositions.entries) {
            expect(
              graph.getPositionOrNullForId(entry.key),
              entry.value,
              reason: 'A failed save must leave every other node in place',
            );
          }
          expect(cubit.isAnchored(target), isTrue);
          if (fails) {
            expect(
              placementCues(placement.current, now: clock.now()).cues[target],
              PlacementCue.notSaved,
              reason:
                  'The outbox must report this target as unsaved after retries',
            );
            final l10n = L10n.of(
              tester.element(find.byType(ConstellationBody)),
            )!;
            expect(
              find.text(l10n.constellationPlacementNotSaved),
              findsOneWidget,
            );
          } else {
            expect(placement.current.targets, isEmpty);
            expect(cubit.state.confirmedProjection!.revision.value, BigInt.two);
            expect(
              cubit.state.confirmedProjection!.anchors
                  .singleWhere((a) => a.target == target)
                  .position,
              expected,
            );
            expect(
              cubit.state.composition!.anchorOverlay.anchors
                  .singleWhere((a) => a.target == target)
                  .position,
              expected,
            );
          }
          await _expectFiltersApplied(tester, phone: phone);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            if (!acknowledgement.isCompleted) acknowledgement.complete();
            await dispose();
            gate.complete();
            await wireRun;
          });
        }
      },
    );
  }
}
