// A22: a helper may archive a request from My Work even while it is still
// OPEN (U6). Archiving only hides the card for the viewer. Today
// `_deriveHelpOffered` sets `showArchiveAffordance` only for finished or
// archived requests, so an open helper card has no «Archive» action.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_cards.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_fetch_types.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_cards.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'my_work_test_support.dart';

const _viewerId = 'helper-1';

final class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state =>
      const ProfileState(profile: Profile(id: _viewerId, displayName: 'Me'));

  @override
  Stream<ProfileState> get stream =>
      Stream<ProfileState>.value(state).asBroadcastStream();
}

Beacon _openBeacon(String id) => Beacon.empty.copyWith(
  id: id,
  title: 'Open request $id',
  updatedAt: DateTime(2026, 9, 5),
  status: BeaconStatus.open,
  author: const Profile(id: 'auth', displayName: 'Author Co'),
);

MyWorkHelpOfferedRow _row(Beacon beacon) => (
  beacon: beacon,
  offerHelpMessage: 'I can help',
  helpType: null,
  authorResponseType: null,
  stakeState: CommitmentStakeState.none,
  forwarderSenders: const <Profile>[],
  helpOfferRowUpdatedAt: DateTime(2026, 9, 4),
  authorCoordinationUpdatedAt: null,
);

void main() {
  setUp(() {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger('my-work-helper-archive'));
    }
    if (!GetIt.I.isRegistered<BeaconRepository>()) {
      GetIt.I.registerSingleton<BeaconRepository>(FakeBeaconRepository());
    }
    if (!GetIt.I.isRegistered<EvaluationRepository>()) {
      GetIt.I.registerSingleton<EvaluationRepository>(
        EvaluationRepositoryMock(),
      );
    }
  });

  tearDown(() {
    for (final unregister in <void Function()>[
      if (GetIt.I.isRegistered<BeaconRepository>())
        GetIt.I.unregister<BeaconRepository>,
      if (GetIt.I.isRegistered<EvaluationRepository>())
        GetIt.I.unregister<EvaluationRepository>,
    ]) {
      unregister();
    }
  });

  test('derive: helper card on an OPEN request offers the archive action', () {
    final vm = buildNonArchivedViewModels(
      authoredNonArchived: const [],
      helpOfferedNonArchived: [_row(_openBeacon('open-1'))],
    ).single;
    expect(vm.kind, MyWorkCardKind.helpOfferedActive);
    expect(vm.showArchiveAffordance, isTrue);
    expect(vm.viewerArchived, isFalse);
  });

  testWidgets(
    'open helper card shows the archive action; archiving is viewer-local and leaves '
    'the request open',
    (tester) async {
      final beacon = _openBeacon('open-1');
      final repo = FakeMyWorkRepository()
        ..initResult = (
          authoredNonArchived: const <Beacon>[],
          helpOfferedNonArchived: [_row(beacon)],
          obligationBeacons: const [],
          archivedCountHint: 0,
        );
      // Behaves like the server: archiving flips only the viewer's own
      // archive flag — the offer, the request and its status stay as they are.
      final archiveRepo = _RecordingArchiveRepository(repo, _row(beacon));
      final cubit = MyWorkCubit(
        userId: _viewerId,
        myWorkCase: buildTestMyWorkCase(repo: repo, archiveRepo: archiveRepo),
      );
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((s) => s.isSuccess);

      tester.view
        ..physicalSize = const Size(360, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<MyWorkCubit>.value(value: cubit),
                BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
                BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
              ],
              child: Scaffold(
                body: BlocBuilder<MyWorkCubit, MyWorkState>(
                  builder: (context, state) => ListView(
                    children: [
                      for (final vm in state.nonArchivedCards)
                        MyWorkCardRouter(vm: vm),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MyWorkCardRouter), findsOneWidget);
      expect(cubit.state.nonArchivedCards.single.beacon.status,
          BeaconStatus.open);
      // The affordance is the localized «archive» action (key myWorkArchive).
      final archiveLabel = L10n.of(
        tester.element(find.byType(Scaffold)),
      )!.myWorkArchive;
      expect(find.text(archiveLabel), findsOneWidget);

      await tester.tap(find.text(archiveLabel));
      await tester.pumpAndSettle();

      // Only the archive call went out, for this request.
      expect(archiveRepo.archived, ['open-1']);
      expect(archiveRepo.unarchived, isEmpty);
      // Gone from the viewer's desk ...
      expect(find.byType(MyWorkCardRouter), findsNothing);
      expect(cubit.state.nonArchivedCards, isEmpty);

      // ... and kept in the viewer's archive, request still open.
      cubit.setFilter(MyWorkFilter.archived);
      await cubit.stream.firstWhere((s) => s.archivedDataFetched);
      final archived = cubit.state.archivedCards.single;
      expect(archived.beaconId, 'open-1');
      expect(archived.viewerArchived, isTrue);
      expect(archived.beacon.status, BeaconStatus.open);
      expect(archived.sources, {MyWorkMembershipSource.helpOffered});
    },
  );
}

/// Server-like archive: records the call and moves the offer from the
/// viewer's desk to the viewer's archive, nothing else.
final class _RecordingArchiveRepository extends FakeArchiveRepository {
  _RecordingArchiveRepository(this._repo, this._row);

  final FakeMyWorkRepository _repo;
  final MyWorkHelpOfferedRow _row;
  final archived = <String>[];
  final unarchived = <String>[];

  @override
  Future<void> archive(String beaconId) async {
    archived.add(beaconId);
    _repo
      ..initResult = (
        authoredNonArchived: const <Beacon>[],
        helpOfferedNonArchived: const [],
        obligationBeacons: const [],
        archivedCountHint: 1,
      )
      ..archivedResult = (
        authoredArchived: const <Beacon>[],
        helpOfferedArchived: [_row],
      );
  }

  @override
  Future<void> unarchive({
    required String beaconId,
    required String userId,
  }) async {
    unarchived.add(beaconId);
  }
}
