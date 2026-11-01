// #915: a closed Request must load its closure snapshot so the Discussion
// hides phantom Final check lines (#825). Real path: BeaconViewCubit,
// BeaconViewCase, ClosureRepository over the wire harness.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon_display_status_dto.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon/domain/exception.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_activity_sheet.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/closure/domain/entity/beacon_close_result.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/support/room_body_harness.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

const _beaconId = 'B915closed';
const _author = Profile(id: 'U915author', displayName: 'Alice');
const _helper = Profile(id: 'U915helper', displayName: 'Bob');
final _t = DateTime.utc(2026, 11, 1, 12);
final _ru = lookupL10n(const Locale('ru'));

Beacon _beacon({required BeaconStatus status}) => Beacon(
  id: _beaconId,
  title: 'Two helpers closed',
  author: _author,
  createdAt: _t,
  updatedAt: _t,
  status: status,
  accessLevel: BeaconAccessLevel.member,
);

BeaconDisplayStatusDto _displayStatus(BeaconStatus status) =>
    BeaconDisplayStatusDto(
      beaconId: _beaconId,
      status: status,
      phase: status == BeaconStatus.closed
          ? BeaconCoordinationPhase.closed
          : BeaconCoordinationPhase.enoughHelpInMotion,
      suggestedAction: BeaconPhasePrimaryAction.none,
      slot2Kind: BeaconPhaseSlot2Kind.none,
      tier: BeaconDisplayTier.coordination,
      everAcknowledgedCommitterCount: 2,
    );

Map<String, dynamic> _closureStateWire({
  required String role,
  DateTime? earlyCloseAt,
}) => {
  '__typename': 'query_root',
  'closureState': {
    '__typename': 'ClosureState',
    'epoch': 1,
    'status': 1,
    'role': role,
    'members': [
      {
        '__typename': 'ClosureMember',
        'id': _helper.id,
        'displayName': 'Bob',
        'avatarId': null,
        'helpTypes': null,
        'offerText': null,
        'notInRequest': false,
        'departure': null,
      },
    ],
    'outcomes': null,
    'split': null,
    'mySupport': <String>[],
    'inCalcText': null,
    'myMarks': <String>[],
    'closesAt': '2026-11-01T12:00:00.000Z',
    'earlyCloseAt': earlyCloseAt?.toUtc().toIso8601String(),
    'canCloseNow': false,
    'canReopen': false,
    'extensionsUsed': 0,
    'story': null,
  },
};

RoomMessage _statusLine({
  required String id,
  required int from,
  required int to,
  required String reason,
}) => RoomMessage(
  id: id,
  beaconId: _beaconId,
  authorId: _author.id,
  author: _author,
  body: '',
  createdAt: _t,
  systemMessageKind: BeaconRoomSystemMessageKind.statusChanged,
  systemPayloadJson:
      '{"version":1,"fromStatus":$from,"toStatus":$to,"reason":"$reason"}',
);

List<RoomMessage> get _skippedFinalCheckDiscussionLines => [
  _statusLine(
    id: 'open',
    from: BeaconStatus.enoughHelp.smallintValue,
    to: BeaconStatus.reviewOpen.smallintValue,
    reason: 'closureOpened',
  ),
  _statusLine(
    id: 'close',
    from: BeaconStatus.reviewOpen.smallintValue,
    to: BeaconStatus.closed.smallintValue,
    reason: 'authorCloseNow',
  ),
];

List<BeaconActivityEvent> get _skippedFinalCheckActivityEvents => [
  BeaconActivityEvent(
    id: 'open',
    beaconId: _beaconId,
    visibility: 0,
    type: BeaconActivityEventTypeBits.beaconLifecycleChanged,
    createdAt: _t,
    diffJson:
        '{"fromState":${BeaconStatus.enoughHelp.smallintValue},"toState":${BeaconStatus.reviewOpen.smallintValue},"reason":"${BeaconLifecycleChangeReason.closureOpened}"}',
  ),
  BeaconActivityEvent(
    id: 'close',
    beaconId: _beaconId,
    visibility: 0,
    type: BeaconActivityEventTypeBits.beaconLifecycleChanged,
    createdAt: _t.add(const Duration(hours: 1)),
    diffJson:
        '{"fromState":${BeaconStatus.reviewOpen.smallintValue},"toState":${BeaconStatus.closed.smallintValue},"reason":"${BeaconLifecycleChangeReason.authorCloseNow}"}',
  ),
];

FakeHelpOfferCoordinationRow _helperRow() => (
  beaconId: _beaconId,
  userId: _helper.id,
  user: _helper,
  message: 'I can help',
  helpType: null,
  roleLabel: null,
  status: 1,
  withdrawReason: null,
  createdAt: _t,
  updatedAt: _t,
  editedAt: null,
  responseType: 1,
  responseUpdatedAt: _t,
  responseAuthorUserId: _author.id,
  roomAccess: RoomAccessBits.admitted,
  admissionAction: null,
  lastDeclineReason: null,
  lastRemoveReason: null,
  stakeState: 0,
  offerKind: 0,
  isDirectAuthorForward: false,
  authorSeenAt: null,
);

Future<void> _pumpDiscussionFromCubit(
  WidgetTester tester, {
  required BeaconViewCubit cubit,
  required Profile viewer,
  Size viewport = const Size(375, 667),
  Locale locale = const Locale('ru'),
}) async {
  await pumpBeaconRoomBody(
    tester,
    roomState: RoomState(
      beaconId: _beaconId,
      myUserId: viewer.id,
      messages: _skippedFinalCheckDiscussionLines,
      firstLoadDone: true,
    ),
    width: viewport.width,
    height: viewport.height,
    locale: locale,
    closureHadNoFinalCheck: cubit.state.closureState?.hadNoFinalCheck,
  );
}

Future<(BeaconViewCubit, List<WireSent>)> _loadClosedCubit({
  required Profile viewer,
  required String closureRole,
  DateTime? earlyCloseAt,
  Object? closureError,
}) async {
  final sent = <WireSent>[];
  late BeaconViewCubit cubit;
  await withRemoteWire(
    {
      'ClosureState': _closureStateWire(
        role: closureRole,
        earlyCloseAt: earlyCloseAt,
      ),
    },
    sent,
    (remote) async {
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => _beacon(status: BeaconStatus.closed);
      cubit = BeaconViewCubit(
        id: _beaconId,
        myProfile: viewer,
        beaconViewCase: buildTestBeaconViewCase(
          beaconRepo: beaconRepo,
          closureRepo: ClosureRepository(remote),
          displayRepo: FakeBeaconDisplayRepository(
            rows: [_displayStatus(BeaconStatus.closed)],
          ),
          coordinationRepo: FakeBeaconViewCoordinationRepository(
            rows: [_helperRow()],
          ),
          activityEventsRepo: _FixedActivityEventsRepo(
            _skippedFinalCheckActivityEvents,
          ),
        ),
        effects: FakeUiEffectPort(),
      );
      await pumpUntil(
        cubit.stream,
        () => cubit.state.beaconContextLoaded,
      );
    },
    errors: closureError == null
        ? const {}
        : {
            'ClosureState': closureError as Map<String, dynamic>,
          },
  );
  return (cubit, sent);
}

void main() {
  group('#915 closed Request loads closureState', () {
    test('issues ClosureState on the wire for a closed Request', () async {
      final (cubit, sent) = await _loadClosedCubit(
        viewer: _author,
        closureRole: 'author',
      );
      addTearDown(cubit.close);

      expect(
        sent.map((c) => c.operationName),
        contains('ClosureState'),
      );
      expect(cubit.state.closureState?.hadNoFinalCheck, isTrue);
      expect(cubit.state.closureState?.role, ClosureRole.author);
    });

    test('a fetch error leaves a null snapshot', () async {
      final (cubit, sent) = await _loadClosedCubit(
        viewer: _author,
        closureRole: 'author',
        closureError: wireCodeError(1002),
      );
      addTearDown(cubit.close);

      expect(sent.map((c) => c.operationName), contains('ClosureState'));
      expect(cubit.state.closureState, isNull);
    });

    testWidgets('author RU phone hides phantom Final check lines', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      late BeaconViewCubit cubit;
      await tester.runAsync(() async {
        final loaded = await _loadClosedCubit(
          viewer: _author,
          closureRole: 'author',
        );
        cubit = loaded.$1;
      });
      addTearDown(cubit.close);
      await _pumpDiscussionFromCubit(
        tester,
        cubit: cubit,
        viewer: _author,
      );
      expect(find.text(_ru.beaconLifecycleReviewOpen), findsNothing);
      expect(find.byType(RoomMessageTile), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('helper voter desktop keeps one merged close line', (
      tester,
    ) async {
      late BeaconViewCubit cubit;
      await tester.runAsync(() async {
        final loaded = await _loadClosedCubit(
          viewer: _helper,
          closureRole: 'voter',
        );
        cubit = loaded.$1;
      });
      addTearDown(cubit.close);
      await _pumpDiscussionFromCubit(
        tester,
        cubit: cubit,
        viewer: _helper,
        viewport: const Size(1280, 800),
        locale: const Locale('en'),
      );
      expect(find.byType(RoomMessageTile), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('member role keeps both lifecycle lines', (tester) async {
      late BeaconViewCubit cubit;
      await tester.runAsync(() async {
        final loaded = await _loadClosedCubit(
          viewer: _helper,
          closureRole: 'member',
        );
        cubit = loaded.$1;
      });
      addTearDown(cubit.close);
      await _pumpDiscussionFromCubit(
        tester,
        cubit: cubit,
        viewer: _helper,
      );
      expect(find.byType(RoomMessageTile), findsNWidgets(2));
    });

    testWidgets('a final check that ran keeps both lifecycle lines', (
      tester,
    ) async {
      late BeaconViewCubit cubit;
      await tester.runAsync(() async {
        final loaded = await _loadClosedCubit(
          viewer: _author,
          closureRole: 'author',
          earlyCloseAt: _t,
        );
        cubit = loaded.$1;
      });
      addTearDown(cubit.close);
      await _pumpDiscussionFromCubit(
        tester,
        cubit: cubit,
        viewer: _author,
      );
      expect(find.byType(RoomMessageTile), findsNWidgets(2));
    });

    testWidgets('activity log omits the skipped final check step', (
      tester,
    ) async {
      late BeaconViewCubit cubit;
      await tester.runAsync(() async {
        final loaded = await _loadClosedCubit(
          viewer: _author,
          closureRole: 'author',
        );
        cubit = loaded.$1;
      });
      addTearDown(cubit.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: BlocProvider.value(
              value: cubit,
              child: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => showBeaconActivitySheet(
                      context,
                      cubit: cubit,
                      onTapCoordinationEvent: (_) {},
                    ),
                    child: const Text('log'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('log'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final en = lookupL10n(const Locale('en'));
      expect(find.text(en.beaconLifecycleReviewOpen), findsNothing);
      expect(find.text(en.beaconLifecycleClosed), findsOneWidget);
    });
  });

  group('#915 close without final check updates the Discussion live', () {
    test('author close loads closureState without a reload', () async {
      final sent = <WireSent>[];
      late _WireTransitionClosureRepository closureRepo;
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => _beacon(
          status: closureRepo.closed
              ? BeaconStatus.closed
              : BeaconStatus.enoughHelp,
        );
      addTearDown(beaconRepo.dispose);

      late BeaconViewCubit cubit;
      await withRemoteWire(
        {'ClosureState': _closureStateWire(role: 'author')},
        sent,
        (remote) async {
          closureRepo = _WireTransitionClosureRepository(remote);
          cubit = BeaconViewCubit(
            id: _beaconId,
            myProfile: _author,
            beaconViewCase: buildTestBeaconViewCase(
              beaconRepo: beaconRepo,
              closureRepo: closureRepo,
              displayRepo: FakeBeaconDisplayRepository(
                rows: [
                  _displayStatus(BeaconStatus.enoughHelp),
                  _displayStatus(BeaconStatus.closed),
                ],
              ),
              coordinationRepo: FakeBeaconViewCoordinationRepository(
                rows: [_helperRow()],
              ),
            ),
            effects: FakeUiEffectPort(),
          );
          await pumpUntil(
            cubit.stream,
            () => cubit.state.beaconContextLoaded,
          );
          expect(cubit.state.closureState, isNull);
          await cubit.closeBeacon(expectedRequiresReviewWindow: false);
          await pumpUntil(
            cubit.stream,
            () => cubit.state.closureState?.hadNoFinalCheck == true,
          );
          expect(cubit.state.beacon.status, BeaconStatus.closed);
          expect(sent.map((c) => c.operationName), contains('ClosureState'));
        },
      );
      addTearDown(cubit.close);
    });

    testWidgets('author close updates the room filter without reload', (
      tester,
    ) async {
      final sent = <WireSent>[];
      late _WireTransitionClosureRepository closureRepo;
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => _beacon(
          status: closureRepo.closed
              ? BeaconStatus.closed
              : BeaconStatus.enoughHelp,
        );
      addTearDown(beaconRepo.dispose);

      late BeaconViewCubit cubit;
      await tester.runAsync(() async {
        await withRemoteWire(
          {'ClosureState': _closureStateWire(role: 'author')},
          sent,
          (remote) async {
            closureRepo = _WireTransitionClosureRepository(remote);
            cubit = BeaconViewCubit(
              id: _beaconId,
              myProfile: _author,
              beaconViewCase: buildTestBeaconViewCase(
                beaconRepo: beaconRepo,
                closureRepo: closureRepo,
                displayRepo: FakeBeaconDisplayRepository(
                  rows: [
                    _displayStatus(BeaconStatus.enoughHelp),
                    _displayStatus(BeaconStatus.closed),
                  ],
                ),
                coordinationRepo: FakeBeaconViewCoordinationRepository(
                  rows: [_helperRow()],
                ),
              ),
              effects: FakeUiEffectPort(),
            );
            await pumpUntil(
              cubit.stream,
              () => cubit.state.beaconContextLoaded,
            );
            await cubit.closeBeacon(expectedRequiresReviewWindow: false);
            await pumpUntil(
              cubit.stream,
              () => cubit.state.closureState?.hadNoFinalCheck == true,
            );
          },
        );
      });
      addTearDown(cubit.close);

      await _pumpDiscussionFromCubit(
        tester,
        cubit: cubit,
        viewer: _author,
      );

      expect(find.byType(RoomMessageTile), findsOneWidget);
      expect(find.text(_ru.beaconLifecycleReviewOpen), findsNothing);
    });

    test('another client closing the Request loads closureState', () async {
      late _WireTransitionClosureRepository closureRepo;
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => _beacon(
          status: closureRepo.closed
              ? BeaconStatus.closed
              : BeaconStatus.enoughHelp,
        );
      addTearDown(beaconRepo.dispose);
      final sent = <WireSent>[];
      late BeaconViewCubit cubit;
      await withRemoteWire(
        {'ClosureState': _closureStateWire(role: 'author')},
        sent,
        (remote) async {
          closureRepo = _WireTransitionClosureRepository(remote);
          cubit = BeaconViewCubit(
            id: _beaconId,
            myProfile: _author,
            beaconViewCase: buildTestBeaconViewCase(
              beaconRepo: beaconRepo,
              closureRepo: closureRepo,
              displayRepo: FakeBeaconDisplayRepository(
                rows: [
                  _displayStatus(BeaconStatus.enoughHelp),
                  _displayStatus(BeaconStatus.closed),
                ],
              ),
            ),
            effects: FakeUiEffectPort(),
          );
          await pumpUntil(
            cubit.stream,
            () => cubit.state.beaconContextLoaded,
          );
          closureRepo.closed = true;
          beaconRepo.emitUpdate(_beacon(status: BeaconStatus.closed));
          await pumpUntil(
            cubit.stream,
            () => cubit.state.closureState?.hadNoFinalCheck == true,
          );
          expect(sent.map((c) => c.operationName), contains('ClosureState'));
        },
      );
      addTearDown(cubit.close);
    });
  });
}

class _FixedActivityEventsRepo extends FakeBeaconViewActivityEventRepository {
  _FixedActivityEventsRepo(this._events);

  final List<BeaconActivityEvent> _events;

  @override
  Future<List<BeaconActivityEvent>> list({required String beaconId}) async =>
      _events;
}

class _WireTransitionClosureRepository extends ClosureRepository {
  _WireTransitionClosureRepository(super._remoteApiService);

  bool closed = false;

  @override
  Future<BeaconCloseResult> beaconClose({required String beaconId}) async {
    closed = true;
    return BeaconCloseResult(beaconId: beaconId, state: 1);
  }

  @override
  Future<ClosureState> fetchState(String beaconId) async {
    if (!closed) throw const BeaconFetchException();
    return super.fetchState(beaconId);
  }
}
