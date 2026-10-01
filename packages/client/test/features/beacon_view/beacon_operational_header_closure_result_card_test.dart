// tentura-q8s8: A22 results card on the closed request screen (NOW / operational
// header is one valid mount point; acceptance is behavioral).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_operational_header_card.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/closure/domain/entity/closure_band.dart';
import 'package:tentura/features/closure/domain/entity/closure_draft_flag.dart';
import 'package:tentura/features/closure/domain/entity/closure_member.dart';
import 'package:tentura/features/closure/domain/entity/closure_outcome.dart';
import 'package:tentura/features/closure/domain/entity/closure_result.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/features/closure/domain/use_case/closure_case.dart';
import 'package:tentura/features/closure/ui/widget/closure_result_card.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this.profile);

  final Profile profile;

  @override
  ProfileState get state => ProfileState(profile: profile);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

final class _FakeClosureRepository implements ClosureRepository {
  @override
  Future<ClosureResult?> fetchResultForViewer(String beaconId) async =>
      const ClosureResult(
        outcome: ClosureOutcome.done,
        band: ClosureBand.none,
        draftFlag: ClosureDraftFlag.none,
        marks: [],
      );

  @override
  Future<ClosureState> fetchState(String beaconId) async => ClosureState(
        epoch: 1,
        status: 1,
        role: ClosureRole.voter,
        members: const [
          ClosureMember(id: 'uHelper', displayName: 'Helper'),
        ],
        closesAt: DateTime.utc(2030, 1, 1),
        myMarks: const [],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpRequestHeader(
  WidgetTester tester, {
  required BeaconViewState state,
}) async {
  GetIt.I.registerSingleton<ClosureCase>(
    ClosureCase(_FakeClosureRepository(), env: const Env(), logger: Logger('test')),
  );
  addTearDown(() => GetIt.I.unregister<ClosureCase>());

  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: BlocProvider<ProfileCubit>.value(
        value: _MockProfileCubit(state.myProfile),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: BeaconOperationalHeaderCard(
              state: state,
              onAuthorTap: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const author = Profile(id: 'uAuthor', displayName: 'Author');
  const helper = Profile(id: 'uHelper', displayName: 'Helper');
  const stranger = Profile(id: 'uStranger', displayName: 'Stranger');
  final t = DateTime.utc(2026, 6, 20);

  Beacon closedBeacon() => Beacon(
        id: 'b-closed',
        title: 'Closed request',
        author: author,
        createdAt: t,
        updatedAt: t,
        status: BeaconStatus.closed,
      );

  BeaconViewState closedAs(Profile viewer) {
    final participant = viewer.id == helper.id;
    return BeaconViewState(
      beacon: closedBeacon(),
      myProfile: viewer,
      beaconContextLoaded: true,
      isHelpOffered: participant,
      roomParticipants: participant
          ? [
              BeaconParticipant(
                id: 'p1',
                beaconId: 'b-closed',
                userId: helper.id,
                role: BeaconParticipantRoleBits.helper,
                status: BeaconParticipantStatusBits.committed,
                roomAccess: RoomAccessBits.admitted,
                createdAt: t,
                updatedAt: t,
              ),
            ]
          : const [],
    );
  }

  testWidgets(
    'closure participant on closed request sees Results for you on request screen',
    (tester) async {
      await _pumpRequestHeader(tester, state: closedAs(helper));

      expect(find.byType(ClosureResultCard), findsOneWidget);
      expect(find.text('Results for you'), findsOneWidget);
    },
  );

  testWidgets(
    'nonparticipant on closed request does not show Results for you on request screen',
    (tester) async {
      await _pumpRequestHeader(tester, state: closedAs(stranger));

      expect(find.text('Results for you'), findsNothing);
      expect(find.byType(ClosureResultCard), findsNothing);
    },
  );

  testWidgets('open request does not show Results for you on request screen', (
    tester,
  ) async {
    await _pumpRequestHeader(
      tester,
      state: closedAs(helper).copyWith(
        beacon: closedBeacon().copyWith(status: BeaconStatus.open),
      ),
    );

    expect(find.byType(ClosureResultCard), findsNothing);
    expect(find.text('Results for you'), findsNothing);
  });

  testWidgets(
    'author on closed request does not show Results for you on request screen',
    (tester) async {
      await _pumpRequestHeader(
        tester,
        state: BeaconViewState(
          beacon: closedBeacon(),
          myProfile: author,
          beaconContextLoaded: true,
        ),
      );

      expect(find.text('Results for you'), findsNothing);
      expect(find.byType(ClosureResultCard), findsNothing);
    },
  );
}
