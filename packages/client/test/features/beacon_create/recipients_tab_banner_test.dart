import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/widget/recipients_tab.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _FakeInvitationRepository extends Fake implements InvitationRepository {
  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<List<InvitationEntity>> fetchMine({
    int offset = 0,
    int limit = 0,
  }) async =>
      <InvitationEntity>[];

  @override
  Future<InvitationFetchByIdResult?> fetchById(String id) async => null;

  @override
  Future<InvitationEntity> create({
    required String addresseeName,
    String? beaconId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteById(String id) async {}

  @override
  Future<void> dispose() async {}
}

Future<void> _pumpRecipientsTab(
  WidgetTester tester, {
  required ForwardCubit forwardCubit,
  required BeaconCreateCubit createCubit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(800, 900)),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<BeaconCreateCubit>.value(value: createCubit),
            BlocProvider<ForwardCubit>.value(value: forwardCubit),
            BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
          ],
          child: Scaffold(
            body: BeaconRecipientsTab(
              beaconId: 'draft-1',
              onSendRequest: () {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  const bannerText =
      'Nobody will see this request until you send it to someone.';

  setUp(() {
    if (!GetIt.I.isRegistered<UiEffectPort>()) {
      GetIt.I.registerSingleton<UiEffectPort>(FakeUiEffectPort());
    }
    if (!GetIt.I.isRegistered<InvitationRepository>()) {
      GetIt.I.registerSingleton<InvitationRepository>(
        _FakeInvitationRepository(),
      );
    }
  });

  tearDown(() async {
    if (GetIt.I.isRegistered<InvitationRepository>()) {
      await GetIt.I.unregister<InvitationRepository>();
    }
    if (GetIt.I.isRegistered<UiEffectPort>()) {
      await GetIt.I.unregister<UiEffectPort>();
    }
  });

  testWidgets('routing banner hidden while candidatesLoad is loading', (
    tester,
  ) async {
    final createCubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(),
      effects: FakeUiEffectPort(),
    );
    addTearDown(createCubit.close);
    final cubit = ForwardCubit(
      beaconId: 'draft-1',
      debugSkipInitialLoad: true,
      embedded: true,
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    cubit.emit(
      ForwardState(
        beaconId: 'draft-1',
        beacon: Beacon.empty.copyWith(id: 'draft-1'),
        candidatesLoad: const ForwardCandidatesLoading(),
      ),
    );

    await _pumpRecipientsTab(
      tester,
      forwardCubit: cubit,
      createCubit: createCubit,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(bannerText), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('routing banner hidden while candidatesLoad is error', (
    tester,
  ) async {
    final createCubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(),
      effects: FakeUiEffectPort(),
    );
    addTearDown(createCubit.close);
    final cubit = ForwardCubit(
      beaconId: 'draft-1',
      debugSkipInitialLoad: true,
      embedded: true,
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    cubit.emit(
      ForwardState(
        beaconId: 'draft-1',
        beacon: Beacon.empty.copyWith(id: 'draft-1'),
        candidatesLoad: ForwardCandidatesError(Exception('network down')),
      ),
    );

    await _pumpRecipientsTab(
      tester,
      forwardCubit: cubit,
      createCubit: createCubit,
    );
    await tester.pumpAndSettle();

    expect(find.text(bannerText), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('routing banner shown when candidatesLoad is ready', (
    tester,
  ) async {
    final createCubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(),
      effects: FakeUiEffectPort(),
    );
    addTearDown(createCubit.close);
    final cubit = ForwardCubit(
      beaconId: 'draft-1',
      debugSkipInitialLoad: true,
      embedded: true,
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    cubit.emit(
      ForwardState(
        beaconId: 'draft-1',
        beacon: Beacon.empty.copyWith(id: 'draft-1', title: 'Draft'),
        candidatesLoad: const ForwardCandidatesReady(),
      ),
    );

    await _pumpRecipientsTab(
      tester,
      forwardCubit: cubit,
      createCubit: createCubit,
    );
    await tester.pumpAndSettle();

    expect(find.text(bannerText), findsOneWidget);
  });

  testWidgets('routing banner shown when candidatesLoad is empty', (
    tester,
  ) async {
    final createCubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(),
      effects: FakeUiEffectPort(),
    );
    addTearDown(createCubit.close);
    final cubit = ForwardCubit(
      beaconId: 'draft-1',
      debugSkipInitialLoad: true,
      embedded: true,
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    cubit.emit(
      ForwardState(
        beaconId: 'draft-1',
        beacon: Beacon.empty.copyWith(id: 'draft-1', title: 'Draft'),
        candidatesLoad: const ForwardCandidatesEmpty(),
      ),
    );

    await _pumpRecipientsTab(
      tester,
      forwardCubit: cubit,
      createCubit: createCubit,
    );
    await tester.pumpAndSettle();

    expect(find.text(bannerText), findsOneWidget);
    expect(find.text('No reachable contacts'), findsOneWidget);
  });
}
