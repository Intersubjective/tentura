import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/person_forward_row.dart';

void main() {
  group('PersonForwardRow.blockFor', () {
    for (final status in [
      BeaconStatus.open,
      BeaconStatus.needsMoreHelp,
      BeaconStatus.enoughHelp,
    ]) {
      test('allows non-blocking involvement while ${status.name}', () {
        for (final involvement in [
          CandidateInvolvement.unseen,
          CandidateInvolvement.forwarded,
          CandidateInvolvement.watching,
        ]) {
          expect(
            PersonForwardRow.blockFor(involvement, status),
            PersonForwardBlock.none,
            reason: '${involvement.name} should be eligible',
          );
        }
      });
    }

    test('notOpen beats every involvement signal', () {
      for (final status in [
        BeaconStatus.reviewOpen,
        BeaconStatus.closed,
      ]) {
        for (final involvement in CandidateInvolvement.values) {
          expect(
            PersonForwardRow.blockFor(involvement, status),
            PersonForwardBlock.notOpen,
            reason: '${status.name}/${involvement.name}',
          );
        }
      }
    });

    test('maps blocking involvement reasons for open-family requests', () {
      const cases = {
        CandidateInvolvement.forwardedByMe: PersonForwardBlock.alreadySent,
        CandidateInvolvement.helpOffered: PersonForwardBlock.alreadyHelping,
        CandidateInvolvement.declined: PersonForwardBlock.declined,
        CandidateInvolvement.withdrawn: PersonForwardBlock.withdrawn,
        CandidateInvolvement.author: PersonForwardBlock.theirOwn,
      };

      for (final entry in cases.entries) {
        expect(
          PersonForwardRow.blockFor(entry.key, BeaconStatus.open),
          entry.value,
        );
      }
    });
  });
}
