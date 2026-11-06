import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// Issue #1050: Field / recipient-picker empty invite CTA must match People →
// Invitations wording (trust), not "know".
//
// Run from packages/client: the ARB files are read by relative path.
Map<String, dynamic> _arb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  test('English empty-invite CTA matches Friends invitation CTAs', () {
    final l10n = lookupL10n(const Locale('en'));
    expect(l10n.emptyInviteSomeoneAction, 'Invite someone you trust');
    expect(l10n.emptyInviteSomeoneAction, l10n.friendsCreateInvitation);
    expect(l10n.emptyInviteSomeoneAction, l10n.friendsInviteMore);
  });

  test('Russian empty-invite CTA matches Friends invitation CTAs', () {
    final l10n = lookupL10n(const Locale('ru'));
    expect(l10n.emptyInviteSomeoneAction, l10n.friendsCreateInvitation);
    expect(l10n.emptyInviteSomeoneAction, l10n.friendsInviteMore);
  });

  test('ARB files carry trust wording for emptyInviteSomeoneAction', () {
    final en = _arb('l10n/app_en.arb');
    final ru = _arb('l10n/app_ru.arb');
    expect(en['emptyInviteSomeoneAction'], 'Invite someone you trust');
    expect(ru['emptyInviteSomeoneAction'], ru['friendsCreateInvitation']);
    expect(en['emptyInviteSomeoneAction'], en['friendsCreateInvitation']);
  });
}
