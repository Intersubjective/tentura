import 'package:test/test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/widget/coordination_participant_lookup.dart';

void main() {
  group('profileForParticipant viewer fallback', () {
    const viewer = Profile(id: 'me', displayName: 'Current User');

    test('uses viewer profile when id matches and not in participants', () {
      final profile = profileForParticipant(
        const [],
        'me',
        viewerProfile: viewer,
      );
      expect(profile.displayName, 'Current User');
    });

    test('prefers viewer profile over empty participant row for self', () {
      final profile = profileForParticipant(
        const [],
        'me',
        viewerProfile: viewer,
      );
      expect(profile.id, 'me');
      expect(profile.displayName, isNotEmpty);
    });
  });
}
