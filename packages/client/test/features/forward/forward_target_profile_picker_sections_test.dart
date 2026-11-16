// Which Forward picker sections each target profile shows: the
// invite-new-person bar, tag chips, scope links («Not yet seen / Already
// involved») and the shared note + send composer. Inviting Post members to a
// budded Request hides all four; forwarding a Request or a Post keeps them.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/forward/domain/forward_target_profile.dart';

void main() {
  group('Forward picker sections per target profile', () {
    test('inviting Post members hides the invite-new-person bar, tag chips, '
        'scope links and the shared note/send composer', () {
      const p = ForwardTargetProfile.postBudInvite;
      expect(p.showsInviteNewPersonBar, isFalse);
      expect(p.showsTagChips, isFalse);
      expect(p.showsScopeLinks, isFalse);
      expect(p.showsSharedComposer, isFalse);
    });

    for (final p in [ForwardTargetProfile.request, ForwardTargetProfile.post]) {
      test('forwarding a ${p.name} shows the invite-new-person bar, tag chips, '
          'scope links and the shared note/send composer', () {
        expect(p.showsInviteNewPersonBar, isTrue);
        expect(p.showsTagChips, isTrue);
        expect(p.showsScopeLinks, isTrue);
        expect(p.showsSharedComposer, isTrue);
      });
    }
  });
}
