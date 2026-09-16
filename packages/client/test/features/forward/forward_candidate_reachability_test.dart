import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';

void main() {
  group('ForwardCandidate.isReachable', () {
    test('bond-only peer is reachable', () {
      const profile = Profile(id: 'U-peer', sharesActiveContext: true);
      expect(profile.isMutuallyVisible, isFalse);
      expect(const ForwardCandidate(profile: profile).isReachable, isTrue);
    });

    test('no trust and no bond is unreachable', () {
      const candidate = ForwardCandidate(profile: Profile(id: 'U-peer'));
      expect(candidate.isReachable, isFalse);
    });

    test('mutual trust without bond is reachable', () {
      const candidate = ForwardCandidate(
        profile: Profile(id: 'U-peer', score: 1, rScore: 1),
      );
      expect(candidate.isReachable, isTrue);
    });
  });
}
