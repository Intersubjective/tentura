// The Post→Request invite step reuses the Forward picker through
// `ForwardTargetProfile.postBudInvite`: the profile getters switch the picker
// affordances on and off per use.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/forward/domain/forward_target_profile.dart';

void main() {
  group('Inviting Post members to a budded Request', () {
    const p = ForwardTargetProfile.postBudInvite;

    test('hides band, reasons, lineage, attribution, requirements and the '
        'offer-help nudge', () {
      expect(p.showsBand, isFalse);
      expect(p.showsReasons, isFalse);
      expect(p.showsLineage, isFalse);
      expect(p.showsAttribution, isFalse);
      expect(p.showsRequirements, isFalse);
      expect(p.nudgesOfferHelp, isFalse);
    });

    test('keeps one personal note per invitee', () {
      expect(p.showsPersonalNotes, isTrue);
    });
  });

  group('Forwarding a Request or a Post keeps its affordances', () {
    test('a Request shows every request-only affordance', () {
      const p = ForwardTargetProfile.request;
      expect(p.showsBand, isTrue);
      expect(p.showsReasons, isTrue);
      expect(p.showsPersonalNotes, isTrue);
      expect(p.showsLineage, isTrue);
      expect(p.showsAttribution, isTrue);
      expect(p.showsRequirements, isTrue);
      expect(p.nudgesOfferHelp, isTrue);
    });

    test('a Post shows none of the request-only affordances', () {
      const p = ForwardTargetProfile.post;
      expect(p.showsBand, isFalse);
      expect(p.showsReasons, isFalse);
      expect(p.showsPersonalNotes, isFalse);
      expect(p.showsLineage, isFalse);
      expect(p.showsAttribution, isFalse);
      expect(p.showsRequirements, isFalse);
      expect(p.nudgesOfferHelp, isFalse);
    });
  });
}
