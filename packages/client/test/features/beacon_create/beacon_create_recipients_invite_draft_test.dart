import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/components/tentura_confirm_dialog.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/widget/recipients_tab.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_invite_bar.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/context/domain/entity/context_entity.dart';
import 'fake_beacon_ports.dart';

class _ContextRepositoryFake extends Fake implements ContextRepository {
  @override
  Stream<RepositoryEvent<ContextEntity>> get changes =>
      const Stream<RepositoryEvent<ContextEntity>>.empty();

  @override
  Future<Iterable<String>> fetch({bool fromCache = true}) async => [];
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _RecordingInvitationRepository extends Fake
    implements InvitationRepository {
  int createCalls = 0;
  String? lastBeaconId;

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<InvitationsFetchResult> fetchMine({
    int pendingOffset = 0,
    int pendingLimit = 0,
    int acceptedOffset = 0,
    int acceptedLimit = 0,
  }) async => (
    pending: <InvitationEntity>[],
    accepted: <InvitationEntity>[],
    pendingCount: 0,
  );

  @override
  Future<int> fetchTtlHours() async => 48;

  @override
  Future<InvitationFetchByIdResult?> fetchById(String id) async => null;

  @override
  Future<InvitationEntity> create({
    required String addresseeName,
    String? beaconId,
  }) async {
    createCalls++;
    lastBeaconId = beaconId;
    return InvitationEntity(
      id: 'Iabc123def456',
      beaconId: beaconId,
      createdAt: DateTime.utc(2026, 10, 19),
      updatedAt: DateTime.utc(2026, 10, 19),
    );
  }

  @override
  Future<void> deleteById(String id) async {}

  @override
  Future<void> dispose() async {}
}

Beacon _validDraftBeacon() => Beacon.empty.copyWith(
  id: 'draft-1',
  status: BeaconStatus.draft,
  title: 'My draft title',
  description: 'Valid description for recipients tab.',
);

Future<void> _pumpRecipientsTab(
  WidgetTester tester, {
  required ForwardCubit forwardCubit,
  required BeaconCreateCubit createCubit,
  required ContextCubit contextCubit,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<BeaconCreateCubit>.value(value: createCubit),
          BlocProvider<ForwardCubit>.value(value: forwardCubit),
          BlocProvider<ContextCubit>.value(value: contextCubit),
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
  );
}

ForwardCubit _readyForwardCubit() => ForwardCubit(
  beaconId: 'draft-1',
  debugSkipInitialLoad: true,
  embedded: true,
  effects: FakeUiEffectPort(),
)..emit(
  ForwardState(
    beaconId: 'draft-1',
    beacon: Beacon.empty.copyWith(id: 'draft-1', title: 'Draft'),
    candidatesLoad: const ForwardCandidatesReady(),
  ),
);

BeaconCreateCubit _liveReadyCreateCubit(FakeBeaconWritePort write) {
  final draft = _validDraftBeacon();
  final createCubit = BeaconCreateCubit(
    beaconCreateCase: fakeBeaconCreateCase(write: write),
    effects: FakeUiEffectPort(),
  );
  createCubit.emit(
    createCubit.state.copyWith(
      draftId: draft.id,
      title: draft.title,
      description: draft.description,
      canTryToPublish: true,
    ),
  );
  return createCubit;
}

Future<void> _tapInviteBar(WidgetTester tester) async {
  final bar = tester.widget<ForwardInviteBar>(find.byType(ForwardInviteBar));
  bar.onInvite();
}

Future<void> _pumpUntilShareDialog(WidgetTester tester) async {
  final dialog = find.byType(ShareCodeDialog);
  for (var i = 0; i < 40 && dialog.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late ContextCubit contextCubit;

  setUp(() {
    contextCubit = ContextCubit(
      authCase: buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote()),
      contextRepository: _ContextRepositoryFake(),
      effects: FakeUiEffectPort(),
    );
    if (!GetIt.I.isRegistered<UiEffectPort>()) {
      GetIt.I.registerSingleton<UiEffectPort>(FakeUiEffectPort());
    }
  });

  tearDown(() async {
    await contextCubit.close();
    if (GetIt.I.isRegistered<InvitationRepository>()) {
      await GetIt.I.unregister<InvitationRepository>();
    }
    if (GetIt.I.isRegistered<UiEffectPort>()) {
      await GetIt.I.unregister<UiEffectPort>();
    }
  });

  testWidgets('draft recipients step shows invite-new-person bar', (
    tester,
  ) async {
    final write = FakeBeaconWritePort(beacon: _validDraftBeacon());
    final createCubit = _liveReadyCreateCubit(write);
    addTearDown(createCubit.close);
    final forwardCubit = _readyForwardCubit();
    addTearDown(forwardCubit.close);

    GetIt.I.registerSingleton<InvitationRepository>(
      _RecordingInvitationRepository(),
    );

    await _pumpRecipientsTab(
      tester,
      forwardCubit: forwardCubit,
      createCubit: createCubit,
      contextCubit: contextCubit,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(TestIds.key(TestIds.forwardInviteNewPerson)),
      findsOneWidget,
    );
    expect(createCubit.state.isLive, isFalse);
  });

  testWidgets('cancel confirm does not make live or open invite flow', (
    tester,
  ) async {
    final write = FakeBeaconWritePort(beacon: _validDraftBeacon());
    final createCubit = _liveReadyCreateCubit(write);
    addTearDown(createCubit.close);
    final forwardCubit = _readyForwardCubit();
    addTearDown(forwardCubit.close);
    final invites = _RecordingInvitationRepository();
    GetIt.I.registerSingleton<InvitationRepository>(invites);

    await _pumpRecipientsTab(
      tester,
      forwardCubit: forwardCubit,
      createCubit: createCubit,
      contextCubit: contextCubit,
    );
    await tester.pumpAndSettle();

    await _tapInviteBar(tester);
    await tester.pumpAndSettle();
    expect(find.byType(TenturaConfirmDialog), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(createCubit.state.isLive, isFalse);
    expect(invites.createCalls, 0);
    expect(find.byType(ShareCodeDialog), findsNothing);
  });

  testWidgets('confirm runs makeLive then opens invite flow', (tester) async {
    final write = FakeBeaconWritePort(beacon: _validDraftBeacon());
    final createCubit = _liveReadyCreateCubit(write);
    addTearDown(createCubit.close);
    final forwardCubit = _readyForwardCubit();
    addTearDown(forwardCubit.close);
    final invites = _RecordingInvitationRepository();
    GetIt.I.registerSingleton<InvitationRepository>(invites);

    await _pumpRecipientsTab(
      tester,
      forwardCubit: forwardCubit,
      createCubit: createCubit,
      contextCubit: contextCubit,
    );
    await tester.pumpAndSettle();

    await _tapInviteBar(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Publish without sending'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(createCubit.state.isLive, isTrue);
    expect(write.publishedIds, contains('draft-1'));
    expect(invites.createCalls, 1);
    expect(invites.lastBeaconId, 'draft-1');

    await _pumpUntilShareDialog(tester);
    expect(find.byType(ShareCodeDialog), findsOneWidget);
  });

  testWidgets('makeLive failure leaves invite flow closed', (tester) async {
    final write = FakeBeaconWritePort(beacon: _validDraftBeacon())
      ..publishError = Exception('publish failed');
    final createCubit = _liveReadyCreateCubit(write);
    addTearDown(createCubit.close);
    final forwardCubit = _readyForwardCubit();
    addTearDown(forwardCubit.close);
    final invites = _RecordingInvitationRepository();
    GetIt.I.registerSingleton<InvitationRepository>(invites);

    await _pumpRecipientsTab(
      tester,
      forwardCubit: forwardCubit,
      createCubit: createCubit,
      contextCubit: contextCubit,
    );
    await tester.pumpAndSettle();

    await _tapInviteBar(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Publish without sending'));
    await tester.pumpAndSettle();

    expect(createCubit.state.isLive, isFalse);
    expect(invites.createCalls, 0);
    expect(find.byType(ShareCodeDialog), findsNothing);
  });

  testWidgets('375×667 RU confirm and invite bar copy', (tester) async {
    await usePhoneSurface(tester);
    final l10nRu = lookupL10n(const Locale('ru'));

    final write = FakeBeaconWritePort(beacon: _validDraftBeacon());
    final createCubit = _liveReadyCreateCubit(write);
    addTearDown(createCubit.close);
    final forwardCubit = _readyForwardCubit();
    addTearDown(forwardCubit.close);
    GetIt.I.registerSingleton<InvitationRepository>(
      _RecordingInvitationRepository(),
    );

    await _pumpRecipientsTab(
      tester,
      forwardCubit: forwardCubit,
      createCubit: createCubit,
      contextCubit: contextCubit,
      locale: const Locale('ru'),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10nRu.forwardInviteNewPerson), findsOneWidget);

    await _tapInviteBar(tester);
    await tester.pumpAndSettle();

    expect(
      find.text(l10nRu.beaconCreateInviteMakeLiveConfirmTitle),
      findsOneWidget,
    );
    expect(
      find.text(l10nRu.beaconCreateInviteMakeLiveConfirmBody),
      findsOneWidget,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('InvitationCreate wire carries draft beacon id after makeLive', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    await tester.runAsync(() async {
      final sent = <WireSent>[];
      await withRemoteWire(
        {
          'InvitationCreate': {
            '__typename': 'mutation_root',
            'invitationCreate': {
              '__typename': 'invitation',
              'id': 'Iabc123def456',
              'beacon_id': 'draft-1',
              'invited_id': null,
              'addressee_name': '',
              'created_at': '2026-10-19T00:00:00+00:00',
              'updated_at': '2026-10-19T00:00:00+00:00',
            },
          },
        },
        sent,
        (remote) async {
          GetIt.I.registerSingleton<InvitationRepository>(
            InvitationRepository(remote),
          );

          final write = FakeBeaconWritePort(beacon: _validDraftBeacon());
          final createCubit = _liveReadyCreateCubit(write);
          addTearDown(createCubit.close);
          final forwardCubit = _readyForwardCubit();
          addTearDown(forwardCubit.close);

          await _pumpRecipientsTab(
            tester,
            forwardCubit: forwardCubit,
            createCubit: createCubit,
            contextCubit: contextCubit,
          );
          await tester.pumpAndSettle();

          await _tapInviteBar(tester);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Publish without sending'));
          await tester.pump();
          for (var i = 0; i < 40; i++) {
            await tester.pump(const Duration(milliseconds: 50));
            if (find.byType(ShareCodeDialog).evaluate().isNotEmpty) break;
          }

          expect(
            sent.where((w) => w.operationName == 'InvitationCreate'),
            isNotEmpty,
          );
          final vars = sent
              .firstWhere((w) => w.operationName == 'InvitationCreate')
              .variables;
          expect(vars['beaconId'], 'draft-1');
        },
      );
    });
  });
}
