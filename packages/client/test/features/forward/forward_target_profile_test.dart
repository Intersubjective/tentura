import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/forward/domain/forward_target_profile.dart';
import 'package:tentura/features/forward/ui/bloc/forward_state.dart';

void main() {
  group('ForwardTargetProfile capabilities', () {
    test('Request profile shows every Request-only forward affordance', () {
      const p = ForwardTargetProfile.request;
      expect(p.showsBand, isTrue);
      expect(p.showsReasons, isTrue);
      expect(p.showsLineage, isTrue);
      expect(p.showsAttribution, isTrue);
      expect(p.showsRequirements, isTrue);
      expect(p.nudgesOfferHelp, isTrue);
    });

    test('Post profile hides band, reasons, lineage, attribution, '
        'requirements and the offer-help nudge', () {
      const p = ForwardTargetProfile.post;
      expect(p.showsBand, isFalse);
      expect(p.showsReasons, isFalse);
      expect(p.showsLineage, isFalse);
      expect(p.showsAttribution, isFalse);
      expect(p.showsRequirements, isFalse);
      expect(p.nudgesOfferHelp, isFalse);
    });
  });

  group('ForwardState.profile', () {
    test('is request for a Request beacon', () {
      final state = ForwardState(
        beacon: Beacon.empty.copyWith(kind: BeaconKind.request),
      );
      expect(state.profile, ForwardTargetProfile.request);
    });

    test('is post for a Post beacon', () {
      final state = ForwardState(
        beacon: Beacon.empty.copyWith(kind: BeaconKind.post),
      );
      expect(state.profile, ForwardTargetProfile.post);
    });

    test('defaults to request while the beacon is not loaded', () {
      expect(const ForwardState().profile, ForwardTargetProfile.request);
    });
  });

  group('offer-help nudge call sites', () {
    const callSites = [
      'lib/features/beacon_view/ui/widget/beacon_view_forward_overflow.dart',
      'lib/features/inbox/ui/widget/inbox_card_actions.dart',
    ];
    for (final path in callSites) {
      test('$path passes the forward target profile to the nudge policy', () {
        final source = File(path).readAsStringSync();
        final call = RegExp(
          r'shouldNudgeOfferHelpAfterForwardVisit\(([^;]*?)\)\s*\)\s*\{',
          dotAll: true,
        ).firstMatch(source);
        expect(call, isNotNull);
        expect(call!.group(1), contains('profile:'));
      });
    }
  });
}
