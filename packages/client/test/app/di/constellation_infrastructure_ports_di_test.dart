import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/mock/infrastructure_port_mocks.dart';
import 'package:tentura/domain/port/clock_port.dart';
import 'package:tentura/domain/port/op_id_port.dart';
import 'package:tentura/domain/port/wake_up_port.dart';

/// DI smoke for the U04 ports (#235).
///
/// The full `Environment.test` GetIt container cannot be initialised in a
/// plain `flutter test`: eager singletons (e.g. `AuthCase`) are registered
/// before their `order: 1` test mocks and the drift database needs a native
/// path_provider plugin. That is pre-existing and outside this unit, so, like
/// `forward_candidate_context_di_test.dart`, this asserts the generated
/// registrations that `configureDependencies` would run under ENV=test.
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

  group('U04 infrastructure ports under ENV=test', () {
    for (final (port, service, mock) in [
      ('ClockPort', 'ClockService', 'ClockPortMock'),
      ('OpIdPort', 'OpIdService', 'OpIdPortMock'),
      ('WakeUpPort', 'WakeUpService', 'WakeUpPortMock'),
    ]) {
      test('$port: mock for test, real adapter for dev/prod', () {
        expect(
          registration(port, mock),
          contains('registerFor: {_test}'),
        );
        expect(
          registration(port, service),
          contains('registerFor: {_dev, _prod}'),
        );
      });
    }

    test('test-env mocks implement their ports', () {
      expect(ClockPortMock(), isA<ClockPort>());
      expect(OpIdPortMock(), isA<OpIdPort>());
      expect(WakeUpPortMock(), isA<WakeUpPort>());
    });

    test('ConstellationAccountPort is registered in every environment', () {
      final account = registration(
        'ConstellationAccountPort',
        'ConstellationAccountAdapter',
      );
      expect(account, isNot(contains('registerFor')));
      expect(account, matches(RegExp(r'gh<_i\d+\.AuthCase>\(\)')));
      expect(
        registration('AuthCase', 'AuthCase'),
        isNot(contains('registerFor')),
      );
    });
  });
}
