// #758 real path: a helper who withdrew (or was removed) is no longer a
// member, so the closed Request opens as the showcase. Built through the real
// BeaconViewCubit from real-shaped rows, with the result card fed by a real
// `closureResultForViewer` wire response, the showcase shows the server's
// line. A viewer who never offered sees no card, and the leaver gets no HUD.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_request_modes.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_pinned_block.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_showcase_surface.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/closure/domain/use_case/closure_case.dart';
import 'package:tentura/features/closure/ui/widget/closure_result_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/remote_wire_harness.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_screen_harness.dart';

const _beaconId = 'B983fadc0d2c4';
const _author = Profile(id: 'Ualice', displayName: 'Alice');
const _dave = Profile(id: 'Udave', displayName: 'Dave');
const _eve = Profile(id: 'Ueve', displayName: 'Eve');
const _stranger = Profile(id: 'Ustranger', displayName: 'Stan');
final _t = DateTime.utc(2026, 10, 31);

Beacon _closedRequest() => Beacon(
  id: _beaconId,
  title: 'QA1031 R4 leaver',
  author: _author,
  createdAt: _t,
  updatedAt: _t,
  status: BeaconStatus.closed,
  accessLevel: BeaconAccessLevel.observer,
);

FakeHelpOfferCoordinationRow _row(
  Profile user, {
  required int status,
  int? admissionAction,
  String? withdrawReason,
}) => (
  beaconId: _beaconId,
  userId: user.id,
  user: user,
  message: 'I can help',
  helpType: null,
  roleLabel: null,
  status: status,
  withdrawReason: withdrawReason,
  createdAt: _t,
  updatedAt: _t,
  editedAt: null,
  responseType: 1,
  responseUpdatedAt: _t,
  responseAuthorUserId: _author.id,
  roomAccess: 0,
  admissionAction: admissionAction,
  lastDeclineReason: null,
  lastRemoveReason: null,
  stakeState: 0,
  offerKind: 0,
  isDirectAuthorForward: false,
  authorSeenAt: null,
);

Map<String, dynamic> _resultWire({
  required String outcome,
  required String band,
  required bool unjudgedLeaver,
}) => {
  '__typename': 'query_root',
  'closureResultForViewer': {
    '__typename': 'ClosureResult',
    'outcome': outcome,
    'band': band,
    'draftFlag': 'none',
    'marks': <String>[],
    'story': null,
    'unjudgedLeaver': unjudgedLeaver,
  },
};

final Map<String, dynamic> _closureStateWire = {
  '__typename': 'query_root',
  'closureState': {
    '__typename': 'ClosureState',
    'epoch': 1,
    'status': 2,
    'role': 'member',
    'members': [
      {
        '__typename': 'ClosureMember',
        'id': _dave.id,
        'displayName': 'Dave',
        'avatarId': null,
        'helpTypes': null,
        'offerText': null,
        'notInRequest': true,
        'departure': 'voluntary',
      },
    ],
    'outcomes': null,
    'split': null,
    'mySupport': <String>[],
    'inCalcText': null,
    'myMarks': <String>[],
    'closesAt': '2026-10-31T00:28:00.000Z',
    'earlyCloseAt': null,
    'canCloseNow': false,
    'canReopen': false,
    'extensionsUsed': 0,
    'story': null,
  },
};

/// Opens the closed Request as [viewer] through the real cubit and screen,
/// with [offers] as the server's offer rows and [result] as its
/// `closureResultForViewer` answer.
Future<List<WireSent>> _open(
  WidgetTester tester, {
  required Profile viewer,
  required List<FakeHelpOfferCoordinationRow> offers,
  Map<String, dynamic>? result,
  Size size = kBeaconViewHarnessCompact,
  Locale locale = const Locale('en'),
}) async {
  final sent = <WireSent>[];
  await withRemoteWire(
    {
      'ClosureResultForViewer':
          result ??
          {'__typename': 'query_root', 'closureResultForViewer': null},
      'ClosureState': _closureStateWire,
    },
    sent,
    (remote) async {
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => _closedRequest();
      addTearDown(beaconRepo.dispose);
      final cubit = BeaconViewCubit(
        id: _beaconId,
        myProfile: viewer,
        beaconViewCase: buildTestBeaconViewCase(
          beaconRepo: beaconRepo,
          coordinationRepo: FakeBeaconViewCoordinationRepository(rows: offers),
        ),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      for (var i = 0; i < 50 && !cubit.state.beaconContextLoaded; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(cubit.state.beaconContextLoaded, isTrue);
      // A leaver is not an insider: the screen picks the showcase.
      expect(beaconViewModeFor(cubit.state), BeaconViewMode.showcase);

      await pumpBeaconViewHarness(
        tester,
        size: size,
        locale: locale,
        beaconState: cubit.state,
        threadsState: beaconViewHarnessThreadsState(authorId: viewer.id),
        beaconViewCubit: cubit,
        afterGetItRegistered: () {
          GetIt.I.registerSingleton<ClosureCase>(
            ClosureCase(
              ClosureRepository(remote),
              env: const Env(),
              logger: Logger('test'),
            ),
          );
        },
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 100));
    },
  );
  return sent;
}

void main() {
  tearDown(() async {
    if (GetIt.I.isRegistered<ClosureCase>()) {
      await GetIt.I.unregister<ClosureCase>();
    }
    await unregisterBeaconViewHarnessGetIt();
  });

  final en = lookupL10n(const Locale('en'));
  final ru = lookupL10n(const Locale('ru'));

  testWidgets('a helper who withdrew sees the no-share line in the showcase', (
    tester,
  ) async {
    final sent = await _open(
      tester,
      viewer: _dave,
      offers: [_row(_dave, status: 1, withdrawReason: 'q1031 r4 dave leaves')],
      result: _resultWire(
        outcome: 'notDone',
        band: 'none',
        unjudgedLeaver: true,
      ),
    );

    expect(find.byType(BeaconShowcaseSurface), findsOneWidget);
    expect(find.byType(BeaconHudPinnedBlock), findsNothing);
    expect(find.byType(ClosureResultCard), findsOneWidget);
    expect(find.text(en.closureResultLeftNoShare), findsOneWidget);
    expect(
      sent
          .firstWhere((c) => c.operationName == 'ClosureResultForViewer')
          .variables['beaconId'],
      _beaconId,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the no-share line in Russian at 375×667', (tester) async {
    await _open(
      tester,
      viewer: _dave,
      offers: [_row(_dave, status: 1)],
      result: _resultWire(
        outcome: 'notDone',
        band: 'none',
        unjudgedLeaver: true,
      ),
      size: const Size(375, 667),
      locale: const Locale('ru'),
    );

    expect(find.byType(ClosureResultCard), findsOneWidget);
    expect(find.text(ru.closureResultLeftNoShare), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a helper the author removed sees their result card', (
    tester,
  ) async {
    await _open(
      tester,
      viewer: _eve,
      offers: [
        _row(
          _eve,
          status: 1,
          admissionAction: HelpOfferAdmissionAction.remove.smallintValue,
        ),
      ],
      result: _resultWire(
        outcome: 'cantJudge',
        band: 'asIfSilent',
        unjudgedLeaver: false,
      ),
    );

    expect(find.byType(BeaconShowcaseSurface), findsOneWidget);
    expect(find.byType(ClosureResultCard), findsOneWidget);
    expect(find.text(en.closureResultTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a viewer who never offered sees no result card', (
    tester,
  ) async {
    final sent = await _open(tester, viewer: _stranger, offers: const []);

    expect(find.byType(BeaconShowcaseSurface), findsOneWidget);
    expect(find.byType(ClosureResultCard), findsNothing);
    expect(
      sent.map((c) => c.operationName),
      isNot(contains('ClosureResultForViewer')),
    );
  });
}
