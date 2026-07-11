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

  test('RecoverScreen does not navigate on auth success (router guard owns it)', () {
    expect(recoverSource, isNot(contains('replaceAll([')));
    expect(recoverSource, isNot(contains('BlocListener<AuthCubit, AuthState>')));
  });
}
