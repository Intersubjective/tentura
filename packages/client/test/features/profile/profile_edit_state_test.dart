import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';

import 'package:tentura/features/profile_edit/ui/bloc/profile_edit_state.dart';

void main() {
  test('Copy with null', () {
    final stateA = ProfileEditState(
      original: const Profile(),
      title: 'title',
      handle: '',
      description: 'description',
      image: ImageEntity(imageBytes: Uint8List(0)),
    );
    final stateB = stateA.copyWith(image: null);

    expect(stateB.hasImage, false);
  });
}
