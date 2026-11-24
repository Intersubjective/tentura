import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/invitation_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';

void main() {
  test('only ordinary invitations expire after seven days', () {
    final now = DateTime.timestamp();
    final old = now.subtract(const Duration(days: 8));
    final recent = now.subtract(const Duration(days: 1));
    const issuer = UserEntity(id: 'Uinviteowner1');
    final ordinary = InvitationEntity(
      id: 'I000000000001',
      issuer: issuer,
      createdAt: old,
      updatedAt: old,
    );

    expect(ordinary.isExpired, isTrue);
    expect(ordinary.copyWith(createdAt: recent).isExpired, isFalse);

    final linked = ordinary.copyWith(phantomId: 'PH000000000001');
    expect(linked.isExpired, isFalse);
  });
}
