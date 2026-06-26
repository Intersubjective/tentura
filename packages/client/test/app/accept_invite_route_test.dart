import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('AcceptInviteRoute checks auth before goToLanding', () {
    final source = File('lib/app/router/root_router.dart').readAsStringSync();
    final acceptInviteBlock = source.substring(
      source.indexOf('page: AcceptInviteRoute.page'),
      source.indexOf('// Profile View'),
    );
    expect(acceptInviteBlock, contains('page: AcceptInviteRoute.page'));
    expect(acceptInviteBlock, contains(r"path: '$kPathAcceptInvite/:id'"));
    final authCheckIndex = acceptInviteBlock.indexOf('isAuthenticated');
    final goToLandingIndex = acceptInviteBlock.indexOf('goToLanding');
    expect(authCheckIndex, greaterThan(-1));
    expect(goToLandingIndex, greaterThan(-1));
    expect(authCheckIndex, lessThan(goToLandingIndex));
  });
}
