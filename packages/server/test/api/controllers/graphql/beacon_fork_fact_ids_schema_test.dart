@Tags(['repo-files'])
library;

import 'dart:io';
import 'dart:isolate';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/gql_nodel_base.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_beacon.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/beacon_lifecycle_effects_test_support.dart';
import '../../../support/fake_beacon_access_guard.dart';
import '../../../support/fake_beacon_child_create_port.dart';
import '../../../support/fake_beacon_hierarchy_repository.dart';
import '../../../support/noop_commitment_query_case.dart';

class _Beacons extends Fake implements BeaconRepositoryPort {}

class _Images extends Fake implements ImageRepositoryPort {}

class _Gc extends Fake implements ImageObjectGcPort {}

class _Tasks extends Fake implements TaskRepositoryPort {}

Future<String> _clientSchema() async {
  final lib = await Isolate.resolvePackageUri(
    Uri.parse('package:tentura_server/'),
  );
  return File.fromUri(
    lib!.resolve('../../client/lib/data/gql/schema.graphql'),
  ).readAsStringSync();
}

/// `name: Type` pairs of an SDL argument list.
Map<String, String> _args(String list) => {
  for (final part in list.split(','))
    if (part.trim().isNotEmpty)
      part.split(':').first.trim(): part
          .substring(part.indexOf(':') + 1)
          .trim(),
};

void main() {
  final mutation = MutationBeacon(
    beaconCase: BeaconCase(
      _Beacons(),
      _Images(),
      _Gc(),
      _Tasks(),
      noopCommitmentQueryCase(),
      FakeBeaconAccessGuard(),
      FakeBeaconHierarchyRepository(),
      FakeBeaconChildCreatePort(),
      buildLifecycleEffectsCase(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconForkFactIdsSchemaTest'),
    ),
  );

  group('Forking a Request with ticked facts over GraphQL', () {
    GraphQLObjectField<dynamic, dynamic> forkField() =>
        mutation.all.singleWhere((f) => f.name == 'beaconFork');

    test('the server beaconFork accepts an optional factIds list of ids and '
        'still answers a Beacon', () {
      final field = forkField();
      final inputs = {for (final a in field.inputs) a.name: '${a.type}'};
      expect(inputs, containsPair('factIds', '[String!]'));
      expect(inputs, containsPair('id', 'String!'));
      expect(inputs.keys, containsAll(['copyPlan', 'planStepTimes']));
      // The server prints its type without the client's `v2_` prefix.
      expect('${field.type}', 'Beacon!');
    });

    test('the client schema copy of beaconFork declares factIds next to its '
        'other arguments, with the return type unchanged', () async {
      final line = RegExp(
        r'^\s*beaconFork\(([^)]*)\):\s*(\S+)\s*$',
        multiLine: true,
      ).firstMatch(await _clientSchema());
      expect(line, isNotNull, reason: 'client schema lacks beaconFork');
      expect(_args(line!.group(1)!), {
        'copyPlan': 'Boolean',
        'factIds': '[String!]',
        'id': 'String!',
        'planStepTimes': '[v2_PlanStepTimeInput!]',
      });
      expect(line.group(2), 'v2_Beacon!');
    });
  });
}
