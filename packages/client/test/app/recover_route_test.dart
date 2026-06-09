import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('RecoverRoute is web-accessible without goToLanding guard', () {
    final source = File('lib/app/router/root_router.dart').readAsStringSync();
    final recoverBlock = source.substring(
      source.indexOf('page: RecoverRoute.page'),
      source.indexOf('// Profile Register'),
    );
    expect(recoverBlock, contains('path: kPathRecover'));
    expect(recoverBlock, isNot(contains('goToLanding')));
    expect(recoverBlock, contains('HomeRoute'));
  });
}
