import 'package:test/test.dart';
import 'package:tentura/features/invitation/domain/entity/invite_preview.dart';

void main() {
  test('fromJson parses caller-aware preview', () {
    final preview = InvitePreview.fromJson({
      'codeStatus': 'available',
      'callerStatus': 'existing-user',
      'inviter': {
        'id': 'U1',
        'displayName': 'Alice',
        'image': 'https://example.com/a.png',
      },
      'beacon': {
        'id': 'B1',
        'title': 'Help needed',
        'snippet': 'snippet',
      },
      'suggestedAction': 'accept-as-existing',
    });

    expect(preview.codeStatus, InviteCodeStatus.available);
    expect(preview.callerStatus, InviteCallerStatus.existingUser);
    expect(preview.inviter?.id, 'U1');
    expect(preview.inviter?.displayName, 'Alice');
    expect(preview.beacon?.id, 'B1');
    expect(preview.beacon?.title, 'Help needed');
    expect(preview.isAvailable, isTrue);
  });

  test('fromJson maps unknown callerStatus to anonymous', () {
    final preview = InvitePreview.fromJson({
      'codeStatus': 'invalid',
      'callerStatus': 'unknown',
    });
    expect(preview.callerStatus, InviteCallerStatus.anonymous);
    expect(preview.codeStatus, InviteCodeStatus.invalid);
  });
}
