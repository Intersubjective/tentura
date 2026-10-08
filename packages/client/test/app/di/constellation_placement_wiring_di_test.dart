import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// DI smoke for the constellation use cases (#235).
///
/// Like `constellation_infrastructure_ports_di_test.dart`, this reads the
/// generated registrations, because the full container cannot be initialised
/// in a plain `flutter test`. A stale config fails here instead of at app start.
void main() {
  final packageRoot = Directory('lib/app').existsSync()
      ? ''
      : 'packages/client/';
  final config = File(
    '${packageRoot}lib/app/di/di_current.config.dart',
  ).readAsStringSync();

  String useCaseSource(String fileName) => File(
    '${packageRoot}lib/features/constellation/domain/use_case/$fileName',
  ).readAsStringSync();

  final useCaseBaseSource = File(
    '${packageRoot}lib/domain/use_case/use_case_base.dart',
  ).readAsStringSync();

  String? fieldType(String source, String field) => RegExp(
    '\\bfinal\\s+(\\w+)\\??\\s+$field\\s*;',
  ).firstMatch(source)?.group(1);

  /// Type names of the `gh<...>()` dependencies the generated factory call
  /// passes to the constructor of [type], whatever the registration kind.
  List<String> registeredDependencyTypes(String type) {
    final start = RegExp(
      r'gh\.\w+<_i\d+\.' + type + r'>\(\s*\(\) => _i\d+\.' + type + r'\(',
    ).firstMatch(config);
    expect(start, isNotNull, reason: '$type must be registered');
    final end = config.indexOf(RegExp(r'\n      \),'), start!.end);
    return [
      for (final match in RegExp(
        r'gh<(?:_i\d+\.)?(\w+)>\(\)',
      ).allMatches(config.substring(start.end, end)))
        match.group(1)!,
    ]..sort();
  }

  /// Type names of the injected constructor parameters of [type]: `this.x`
  /// fields (resolved to the declared field type), `required` named
  /// parameters and `required super.x` forwards (resolved in the base class).
  List<String> declaredDependencyTypes(String source, String type) {
    final constructor = RegExp(
      '\\n  $type\\(([\\s\\S]*?)\\)\\s*(?::|\\{|;)',
    ).firstMatch(source);
    expect(constructor, isNotNull, reason: '$type constructor not found');
    final types = <String>[];
    for (final match in RegExp(
      r'this\.(\w+)|required\s+super\.(\w+)|required\s+([\w<>?]+)\s+\w+',
    ).allMatches(constructor!.group(1)!)) {
      final String? resolved;
      if (match.group(1) != null) {
        resolved = fieldType(source, match.group(1)!);
      } else if (match.group(2) != null) {
        resolved = fieldType(useCaseBaseSource, match.group(2)!);
      } else {
        resolved = match.group(3)!.replaceAll('?', '');
      }
      expect(
        resolved,
        isNotNull,
        reason: 'dependency type of ${match.group(0)} not resolved',
      );
      types.add(resolved!);
    }
    return types..sort();
  }

  group('constellation use case registrations', () {
    for (final (type, file) in [
      ('ConstellationAnchorCase', 'constellation_anchor_case.dart'),
      ('ConstellationPlacementCase', 'constellation_placement_case.dart'),
    ]) {
      test('$type is registered with exactly the dependency types its '
          'constructor declares', () {
        expect(
          registeredDependencyTypes(type),
          declaredDependencyTypes(useCaseSource(file), type),
        );
      });
    }
  });
}
