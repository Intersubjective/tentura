@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('W12: client pubspec has no direct latlong2 dependency', () {
    final pubspec = loadYaml(
      File('pubspec.yaml').readAsStringSync(),
    ) as YamlMap;
    final deps = pubspec['dependencies'] as YamlMap? ?? YamlMap();
    expect(deps.containsKey('latlong2'), isFalse);
  });
}
