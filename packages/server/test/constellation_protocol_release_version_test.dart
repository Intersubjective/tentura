@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_constellation_anchor.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

// Last client version using the retired individual anchor mutations.
const _lastClientBeforeRelease = '7.41.23';

String _shippedClientVersion() => RegExp(
  r'^version:\s*(\S+)\s*$',
  multiLine: true,
).firstMatch(File('../client/pubspec.yaml').readAsStringSync())!.group(1)!;

int _compareCoreVersions(String left, String right) {
  List<int> components(String value) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(value);
    expect(match, isNotNull, reason: 'Expected a release semver: $value');
    return [for (var i = 1; i <= 3; i++) int.parse(match!.group(i)!)];
  }

  final a = components(left);
  final b = components(right);
  for (var i = 0; i < a.length; i++) {
    final order = a[i].compareTo(b[i]);
    if (order != 0) return order;
  }
  return 0;
}

void main() {
  group('Interactive Constellation protocol release', () {
    test(
      'client version matches the web bootstrap cache-buster',
      () {
        final shipped = _shippedClientVersion();
        final html = File('../client/web/index.html').readAsStringSync();
        final bootstrapVersions = RegExp(
          r'''flutter_bootstrap\.js\?v=([^"'\s>]+)''',
        ).allMatches(html).map((match) => match.group(1)!).toList();

        expect(
          bootstrapVersions,
          [shipped],
          reason: 'The tracked browser entry point must fetch the new release.',
        );
      },
    );

    test('excludes older clients and admits the shipped client', () {
      expect(
        _compareCoreVersions(
          kDefaultMinClientVersion,
          _lastClientBeforeRelease,
        ),
        greaterThan(0),
        reason:
            'The coordinated protocol switch cannot admit clients from '
            '$_lastClientBeforeRelease or earlier.',
      );
      expect(
        _compareCoreVersions(_shippedClientVersion(), kDefaultMinClientVersion),
        greaterThanOrEqualTo(0),
        reason: 'The released client must satisfy the server version gate.',
      );
    });

    test('exposes batch apply without legacy mutations', () {
      final mutation = MutationConstellationAnchor(
        constellationAnchorCase: ConstellationAnchorCase(
          _UnusedAnchorRepository(),
          env: Env(environment: Environment.test),
          logger: Logger('ConstellationProtocolReleaseTest'),
        ),
      );
      expect(
        mutation.all.map((field) => field.name),
        orderedEquals(['constellationAnchorsApply']),
      );
    });
  });
}

final class _UnusedAnchorRepository
    implements ConstellationAnchorRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Schema construction must not call a repository');
}
