import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final recoverSource = File(
    'lib/features/auth/ui/screen/recover_screen.dart',
  ).readAsStringSync();

  test('RecoverScreen accepts invite query param', () {
    expect(recoverSource, contains("@QueryParam('invite')"));
    expect(recoverSource, contains('final String? invite;'));
  });

  test('RecoverScreen navigates to accept-invite after recovery when invite valid', () {
    expect(recoverSource, contains('AcceptInviteRoute(id: inviteCode)'));
    expect(recoverSource, contains('isValidInviteCode'));
    expect(recoverSource, contains('normalizeInviteCode'));
    expect(recoverSource, contains('const HomeRoute()'));
  });

  test('RecoverScreen wrappedRoute listens for auth success', () {
    expect(
      recoverSource,
      contains('previous.isNotAuthenticated && current.isAuthenticated'),
    );
  });
}
