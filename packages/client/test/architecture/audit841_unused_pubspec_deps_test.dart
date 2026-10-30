@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('W1: client pubspec drops unused direct dependencies', () {
    final pubspec = loadYaml(
      File('pubspec.yaml').readAsStringSync(),
    ) as YamlMap;
    final deps = pubspec['dependencies'] as YamlMap? ?? YamlMap();
    for (final name in [
      'scrollable_positioned_list',
      'gql_dedupe_link',
      'html',
    ]) {
      expect(deps.containsKey(name), isFalse, reason: name);
    }
  });
}
