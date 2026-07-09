import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

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

void main() {
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
  testWidgets('embedded ForwardRecipientPicker hides standalone send CTA', (
    tester,
  ) async {
    final cubit = ForwardCubit(
      beaconId: 'draft-1',
      debugSkipInitialLoad: true,
      embedded: true,
      effects: FakeUiEffectPort(),
    );
    cubit.emit(
      ForwardState(
        beaconId: 'draft-1',
        beacon: Beacon.empty.copyWith(id: 'draft-1', title: 'Draft'),
        candidates: const [
          ForwardCandidate(
            profile: Profile(id: 'u1', displayName: 'Alex'),
          ),
        ],
        selectedIds: {'u1'},
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: MultiBlocProvider(
          providers: [
            BlocProvider<ForwardCubit>.value(value: cubit),
            BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
          ],
          child: const Scaffold(
            body: ForwardRecipientPicker(
              beaconId: 'draft-1',
              embedded: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Forward to 1'), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets(
    'embedded ForwardRecipientPicker enables send when onSendPressed provided',
    (tester) async {
      final cubit = ForwardCubit(
        beaconId: 'draft-1',
        debugSkipInitialLoad: true,
        embedded: true,
        effects: FakeUiEffectPort(),
      );
      cubit.emit(
        ForwardState(
          beaconId: 'draft-1',
          beacon: Beacon.empty.copyWith(id: 'draft-1', title: 'Draft'),
          candidates: const [
            ForwardCandidate(
              profile: Profile(id: 'u1', displayName: 'Alex'),
            ),
          ],
          selectedIds: {'u1'},
        ),
      );
      var sendPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: TenturaTheme.light(),
          home: MultiBlocProvider(
            providers: [
              BlocProvider<ForwardCubit>.value(value: cubit),
              BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
            ],
            child: Scaffold(
              body: ForwardRecipientPicker(
                beaconId: 'draft-1',
                embedded: true,
                onSendPressed: () => sendPressed = true,
                sendEnabled: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Forward to 1'), findsOneWidget);
      await tester.tap(find.text('Forward to 1'));
      await tester.pump();
      expect(sendPressed, isTrue);
    },
  );

  testWidgets(
    'embedded ForwardRecipientPicker keeps send disabled when sendEnabled is false',
    (tester) async {
      final cubit = ForwardCubit(
        beaconId: 'draft-1',
        debugSkipInitialLoad: true,
        embedded: true,
        effects: FakeUiEffectPort(),
      );
      cubit.emit(
        ForwardState(
          beaconId: 'draft-1',
          beacon: Beacon.empty.copyWith(id: 'draft-1', title: 'Draft'),
          candidates: const [
            ForwardCandidate(
              profile: Profile(id: 'u1', displayName: 'Alex'),
            ),
          ],
          selectedIds: {'u1'},
        ),
      );
      var sendPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: TenturaTheme.light(),
          home: MultiBlocProvider(
            providers: [
              BlocProvider<ForwardCubit>.value(value: cubit),
              BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
            ],
            child: Scaffold(
              body: ForwardRecipientPicker(
                beaconId: 'draft-1',
                embedded: true,
                onSendPressed: () => sendPressed = true,
                sendEnabled: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Select recipients'), findsOneWidget);
      expect(find.text('Forward to 1'), findsNothing);
      await tester.tap(find.text('Select recipients'));
      await tester.pump();
      expect(sendPressed, isFalse);
    },
  );
}
