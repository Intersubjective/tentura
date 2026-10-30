@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('W14: drift_dev is a dev_dependency, not a runtime dependency', () {
    final pubspec = loadYaml(
      File('pubspec.yaml').readAsStringSync(),
    ) as YamlMap;
    final deps = pubspec['dependencies'] as YamlMap? ?? YamlMap();
    final devDeps = pubspec['dev_dependencies'] as YamlMap? ?? YamlMap();
    expect(deps.containsKey('drift_dev'), isFalse);
    expect(devDeps.containsKey('drift_dev'), isTrue);
  });
}
