import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/features/beacon_lobby/domain/port/beacon_lobby_port.dart';

/// DI smoke for the Request lobby port (U088): the real repository only in
/// dev/prod, a Mockito stub under ENV=test. Reads the generated config, as
/// `constellation_infrastructure_ports_di_test.dart` does (the full test
/// container cannot boot in a plain `flutter test`).
void main() {
  final config = File('lib/app/di/di_current.config.dart').readAsStringSync();

  String registration(String type, String impl) {
    final match = RegExp(
      r'gh\.\w+<_i\d+\.' + type + r'>\(\s*\(\) => _i\d+\.' + impl + r'\(',
    ).firstMatch(config);
    expect(match, isNotNull, reason: '$impl must be registered as $type');
    final end = config.indexOf(RegExp(r'\n    (await )?gh\.'), match!.end);
    return config.substring(match.start, end < 0 ? config.length : end);
  }

  test('BeaconLobbyPort: mock for test, repository for dev/prod', () {
    expect(
      registration('BeaconLobbyPort', 'BeaconLobbyRepositoryMock'),
      contains('registerFor: {_test}'),
    );
    expect(
      registration('BeaconLobbyPort', 'BeaconLobbyRepository'),
      contains('registerFor: {_dev, _prod}'),
    );
    expect(BeaconLobbyRepositoryMock(), isA<BeaconLobbyPort>());
  });
}
