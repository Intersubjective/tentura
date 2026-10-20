import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// #466: the sign-in methods list called the seed credential "Device key", and
// the "I saved it" confirmation popped up only after the seed dialog had
// closed. The confirmation now lives inside ShowSeedDialog itself.

const _screen = 'lib/features/credentials/ui/screen/credentials_screen.dart';

void main() {
  final source = File(_screen).readAsStringSync();

  test('seed credentials are listed as Recovery seed, not Device key', () {
    final match = RegExp(
      r'CredentialTypes\.ed25519Device\s*=>\s*l10n\.(\w+)',
    ).firstMatch(source);
    expect(match, isNotNull, reason: 'type label mapping not found');
    expect(match!.group(1), 'credentialRecoverySeed');
  });

  test('no separate save-it dialog after the seed dialog closes', () {
    expect(source, contains('ShowSeedDialog.show('));
    expect(source, isNot(contains('seedBackupTitle')));
    expect(source, isNot(contains('seedBackupBody')));
  });
}
