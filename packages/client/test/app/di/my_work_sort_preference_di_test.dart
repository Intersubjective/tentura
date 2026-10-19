import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// DI wiring for the per-device My Work sort order (#431).
///
/// Like `constellation_infrastructure_ports_di_test.dart`, this reads the
/// generated injectable config instead of building the GetIt container. The
/// cubit falls back to "no persistence" when the port is not registered, so a
/// missing registration would make the sort order silently not persist in the
/// app while every cubit test still passes.
void main() {
  final config = File('lib/app/di/di_current.config.dart').readAsStringSync();

  /// The generated `gh.<kind><_iN.Type>(...)` call registering [type] with a
  /// factory that constructs [impl].
  String registration(String type, String impl) {
    final match = RegExp(
      r'gh\.\w+<_i\d+\.' + type + r'>\(\s*\(\) => _i\d+\.' + impl + r'\(',
    ).firstMatch(config);
    expect(match, isNotNull, reason: '$impl must be registered as $type');
    final end = config.indexOf(RegExp(r'\n    (await )?gh\.'), match!.end);
    return config.substring(match.start, end < 0 ? config.length : end);
  }

  test('MyWorkSortPreferencePort is the drift-backed repository '
      'for dev and prod', () {
    final sortPreference = registration(
      'MyWorkSortPreferencePort',
      'MyWorkSortPreferenceRepository',
    );
    expect(sortPreference, contains('registerFor: {_dev, _prod}'));
    expect(sortPreference, matches(RegExp(r'gh<_i\d+\.Database>\(\)')));
  });
}
