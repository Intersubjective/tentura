import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BeaconCreateCase registration injects one operation ID port', () {
    final config = File('lib/app/di/di_current.config.dart').readAsStringSync();
    final registration = RegExp(
      r'gh\.\w+<_i\d+\.BeaconCreateCase>\(\s*\(\)\s*=>\s*'
      r'_i\d+\.BeaconCreateCase\(',
    );
    final registrations = registration.allMatches(config).toList();
    expect(registrations, hasLength(1));

    final opIdImport = RegExp(
      r"""import\s+['"][^'"]*domain/port/op_id_port\.dart['"]\s+as\s+(\w+)\s*;""",
    ).firstMatch(config);
    expect(opIdImport, isNotNull, reason: 'Import the domain OpIdPort');
    final opIdAlias = RegExp.escape(opIdImport![1]!);
    final constructorArguments = RegExp(
      r'^\s*gh<_i\d+\.BeaconWritePort>\(\),\s*'
      r'gh<_i\d+\.BeaconImagePort>\(\),\s*'
      'gh<$opIdAlias\\.OpIdPort>\\(\\),?\\s*\\)',
    );

    final start = registrations.single.end;
    final end = config.indexOf(RegExp(r'\n    (await )?gh\.'), start);
    expect(
      config.substring(start, end == -1 ? config.length : end),
      matches(constructorArguments),
      reason: 'Pass one OpIdPort lookup after the write and image ports',
    );
  });
}
