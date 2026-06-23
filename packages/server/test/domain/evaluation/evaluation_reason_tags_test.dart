import 'package:test/test.dart';

import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';
import 'package:tentura_server/domain/evaluation/evaluation_reason_tags.dart';

void main() {
  group('allowedForRoleAndSign', () {
    test('author positive tags exclude negative tags', () {
      final allowed = EvaluationReasonTags.allowedForRoleAndSign(
        EvaluationParticipantRole.author,
        isNegative: false,
      );
      expect(allowed, contains('clear_request'));
      expect(allowed, isNot(contains('unclear_request')));
    });

    test('committer negative tags exclude positive tags', () {
      final allowed = EvaluationReasonTags.allowedForRoleAndSign(
        EvaluationParticipantRole.committer,
        isNegative: true,
      );
      expect(allowed, contains('did_not_follow_through'));
      expect(allowed, isNot(contains('delivered_as_promised')));
    });

    test('forwarder positive tags are role-specific', () {
      final allowed = EvaluationReasonTags.allowedForRoleAndSign(
        EvaluationParticipantRole.forwarder,
        isNegative: false,
      );
      expect(allowed, contains('reached_right_person'));
      expect(allowed, isNot(contains('clear_request')));
    });
  });

  group('allowedUnionForRole', () {
    test('includes both positive and negative tags for role', () {
      final union = EvaluationReasonTags.allowedUnionForRole(
        EvaluationParticipantRole.author,
      );
      expect(union, containsAll(EvaluationReasonTags.authorPositive));
      expect(union, containsAll(EvaluationReasonTags.authorNegative));
    });
  });
}
