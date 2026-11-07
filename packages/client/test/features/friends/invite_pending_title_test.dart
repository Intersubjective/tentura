import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/features/friends/ui/invite_pending_title.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  final l10n = lookupL10n(const Locale('en'));
  final at = DateTime.utc(2026, 11, 6, 12);

  test('uses trimmed addressee when set', () {
    final invitation = InvitationEntity(
      id: 'Iabc123',
      createdAt: at,
      updatedAt: at,
      addresseeName: '  Mom  ',
    );
    expect(pendingPeopleInviteTitle(l10n, invitation), 'Mom');
  });

  test('falls back to untitled label when addressee empty (#1078)', () {
    final invitation = InvitationEntity(
      id: 'Ilfb1dab0cd250',
      createdAt: at,
      updatedAt: at,
    );
    expect(pendingPeopleInviteTitle(l10n, invitation), 'Untitled invite');
  });
}
