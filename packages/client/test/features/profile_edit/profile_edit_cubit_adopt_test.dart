import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile_edit/ui/bloc/profile_edit_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _FakeImageRepository extends Fake implements ImageRepository {}

class _FakeProfileRepository extends Fake implements ProfileRepositoryPort {}

ProfileEditCubit _cubit(Profile profile) => ProfileEditCubit(
  profile: profile,
  imageRepository: _FakeImageRepository(),
  profileRepository: _FakeProfileRepository(),
  effects: FakeUiEffectPort(),
);

// UI review #207: a cold /profile/edit used to snapshot the empty profile and
// never pick up the loaded one, so the form opened blank.
void main() {
  const loaded = Profile(
    id: 'U1',
    displayName: 'Mara Okonkwo',
    handle: 'seed_mara',
    description: 'Retired nurse.',
  );

  test('adopts the loaded profile while the form is untouched', () async {
    final cubit = _cubit(const Profile());
    cubit.adoptProfile(const Profile(id: 'U1'));
    cubit.adoptProfile(loaded);

    expect(cubit.state.original, loaded);
    expect(cubit.state.displayName, 'Mara Okonkwo');
    expect(cubit.state.handle, 'seed_mara');
    expect(cubit.state.description, 'Retired nurse.');
    expect(cubit.state.hasChanges, isFalse);
    await cubit.close();
  });

  test('never overwrites edits the user already made', () async {
    final cubit = _cubit(const Profile(id: 'U1'));
    cubit.setDisplayName('Typed by hand');
    cubit.adoptProfile(loaded);

    expect(cubit.state.displayName, 'Typed by hand');
    expect(cubit.state.original.displayName, isEmpty);
    await cubit.close();
  });

  test('ignores an empty profile', () async {
    final cubit = _cubit(loaded);
    cubit.adoptProfile(const Profile());

    expect(cubit.state.original, loaded);
    await cubit.close();
  });
}
