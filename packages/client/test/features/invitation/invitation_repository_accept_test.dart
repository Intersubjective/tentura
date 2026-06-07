import 'package:test/test.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/invitation/domain/entity/invite_preview.dart';
import 'package:tentura/features/invitation/domain/exception.dart';

void main() {
  group('InvitationRepository.mapAcceptExistingStatus', () {
    test('404 maps to InvitationNoLongerValid', () {
      expect(
        InvitationRepository.mapAcceptExistingStatus(404, 'I1'),
        isA<InvitationNoLongerValid>(),
      );
    });

    test('400 maps to InvitationSelfOrInvalid', () {
      expect(
        InvitationRepository.mapAcceptExistingStatus(400, 'I1'),
        isA<InvitationSelfOrInvalid>(),
      );
    });

    test('401 and 403 map to InvitationAuthLost', () {
      expect(
        InvitationRepository.mapAcceptExistingStatus(401, 'I1'),
        isA<InvitationAuthLost>(),
      );
      expect(
        InvitationRepository.mapAcceptExistingStatus(403, 'I1'),
        isA<InvitationAuthLost>(),
      );
    });

    test('other statuses map to InvitationAcceptException', () {
      expect(
        InvitationRepository.mapAcceptExistingStatus(500, 'I1'),
        isA<InvitationAcceptException>().having((e) => e.id, 'id', 'I1'),
      );
    });
  });

  group('InvitationRepository.mapPreviewAuthStatus', () {
    test('401 and 403 map to InvitationAuthLost', () {
      expect(
        InvitationRepository.mapPreviewAuthStatus(401),
        isA<InvitationAuthLost>(),
      );
      expect(
        InvitationRepository.mapPreviewAuthStatus(403),
        isA<InvitationAuthLost>(),
      );
    });

    test('other statuses are not mapped', () {
      expect(InvitationRepository.mapPreviewAuthStatus(404), isNull);
    });
  });

  group('InvitePreview.fromJson', () {
    test('parses each callerStatus', () {
      for (final entry in {
        'anonymous': InviteCallerStatus.anonymous,
        'existing-user': InviteCallerStatus.existingUser,
        'already-friends': InviteCallerStatus.alreadyFriends,
        'is-inviter': InviteCallerStatus.isInviter,
      }.entries) {
        final preview = InvitePreview.fromJson({
          'codeStatus': 'available',
          'callerStatus': entry.key,
        });
        expect(preview.callerStatus, entry.value);
      }
    });

    test('parses each codeStatus', () {
      for (final entry in {
        'available': InviteCodeStatus.available,
        'consumed': InviteCodeStatus.consumed,
        'expired': InviteCodeStatus.expired,
        'invalid': InviteCodeStatus.invalid,
      }.entries) {
        final preview = InvitePreview.fromJson({
          'codeStatus': entry.key,
          'callerStatus': 'anonymous',
        });
        expect(preview.codeStatus, entry.value);
      }
    });
  });
}
