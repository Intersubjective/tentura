import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile_edit/ui/bloc/profile_edit_cubit.dart';
import 'package:tentura/features/profile_edit/ui/screen/profile_edit_screen.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

class _FakeImageRepository extends Fake implements ImageRepository {}

class _RecordingProfileRepository extends Fake implements ProfileRepositoryPort {
  String? lastDisplayName;

  @override
  Future<void> update(
    Profile profile, {
    String? displayName,
    String? description,
    bool dropImage = false,
    ImageEntity? image,
    bool updateHandle = false,
    String? handle,
  }) async {
    lastDisplayName = displayName;
  }

  @override
  Future<void> dispose() async {}

  @override
  @override
  Stream<RepositoryEvent<Profile>> get changes =>
      const Stream<RepositoryEvent<Profile>>.empty();

  @override
  Future<Profile> fetchById(String id) async => const Profile();

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [];

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> setAvailabilityLimited({
    required String profileId,
    required bool isLimited,
  }) async {}

  @override
  Future<void> pauseAvailability({
    required String profileId,
    required DateTime resumeOn,
  }) async {}

  @override
  Future<void> resumeAvailability({required String profileId}) async {}
}

void main() {
  test('save trims display name (#1118)', () async {
    final repo = _RecordingProfileRepository();
    final cubit = ProfileEditCubit(
      profile: const Profile(
        id: 'u1',
        displayName: 'Alice',
        handle: 'alice',
      ),
      imageRepository: _FakeImageRepository(),
      profileRepository: repo,
      effects: FakeUiEffectPort(),
    );
    cubit.setDisplayName('  Bob  ');
    final ok = await cubit.save();
    expect(ok, isTrue);
    expect(repo.lastDisplayName, 'Bob');
    await cubit.close();
  });

  testWidgets('whitespace-only display name disables Save at 375 RU (#1118)', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final l10n = lookupL10n(const Locale('ru'));
    final cubit = ProfileEditCubit(
      profile: const Profile(
        id: 'u1',
        displayName: 'Alice',
        handle: 'alice',
      ),
      imageRepository: _FakeImageRepository(),
      profileRepository: _RecordingProfileRepository(),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: TenturaResponsiveScope(
          child: BlocProvider.value(
            value: cubit,
            child: const ProfileEditScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final save = find.widgetWithText(TextButton, l10n.buttonSave);
    expect(save, findsOneWidget);
    expect(tester.widget<TextButton>(save).onPressed, isNull);

    await tester.enterText(find.byType(TextFormField).first, '   ');
    await tester.pump();

    expect(tester.widget<TextButton>(save).onPressed, isNull);
    expect(find.text(l10n.displayNameTooShort), findsOneWidget);
  });
}
