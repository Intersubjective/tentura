import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

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

class _FakeBeaconRepo extends Fake implements BeaconRepositoryPort {}

class _FakeImageRepo extends Fake implements ImageRepositoryPort {}

class _FakeImageObjectGc extends Fake implements ImageObjectGcPort {}

class _FakeTaskRepo extends Fake implements TaskRepositoryPort {}

/// The V2 `beaconConvertToRequest` mutation exposes the Request form's fields
/// (the same input definitions as `beaconUpdateDraft`) and returns the
/// converted Beacon.
const _requestFormInputs = [
  'id',
  'title',
  'description',
  'needs',
  'primaryNeedSlug',
  'startAt',
  'endAt',
  'isDiscoverable',
];

/// `Name` or `Name!` for a scalar, with list wrappers spelled out.
String _describe(GraphQLType<dynamic, dynamic> type) => switch (type) {
  GraphQLNonNullableType(:final ofType) => '${_describe(ofType)}!',
  GraphQLListType(:final ofType) => '[${_describe(ofType)}]',
  _ => type.name ?? '${type.runtimeType}',
};

void main() {
  late MutationBeacon mutation;

  GraphQLObjectField<dynamic, dynamic> field() =>
      mutation.all.singleWhere((f) => f.name == 'beaconConvertToRequest');

  setUp(() {
    mutation = MutationBeacon(
      beaconCase: BeaconCase(
        _FakeBeaconRepo(),
        _FakeImageRepo(),
        _FakeImageObjectGc(),
        _FakeTaskRepo(),
        noopCommitmentQueryCase(),
        FakeBeaconAccessGuard(),
        FakeBeaconHierarchyRepository(),
        FakeBeaconChildCreatePort(),
        buildLifecycleEffectsCase(),
        env: Env(environment: Environment.test),
        logger: Logger('MutationBeaconConvertToRequestTest'),
      ),
    );
  });

  group('beaconConvertToRequest mutation', () {
    test('accepts selected helper ids as a list of non-null strings', () {
      final inputs = field().inputs.where((input) => input.name == 'helperIds');
      expect(
        inputs,
        hasLength(1),
        reason: 'Authors choose which post members become Request helpers',
      );
      expect(_describe(inputs.single.type), '[String!]');
    });

    test('is registered next to the other beacon mutations', () {
      final names = mutation.all.map((f) => f.name);

      expect(
        names,
        containsAll(['beaconUpdateDraft', 'beaconConvertToRequest']),
      );
    });

    test('takes the Request content, schedule, discoverability and selected '
        'helpers', () {
      expect(
        field().inputs.map((a) => a.name),
        unorderedEquals([..._requestFormInputs, 'helperIds']),
      );
    });

    for (final name in _requestFormInputs) {
      test('$name has the same type, nullability and default as in '
          'beaconUpdateDraft', () {
        final converted = field().inputs.singleWhere((a) => a.name == name);
        final draft = mutation.all
            .singleWhere((f) => f.name == 'beaconUpdateDraft')
            .inputs
            .singleWhere((a) => a.name == name);

        expect(_describe(converted.type), _describe(draft.type));
        expect(converted.defaultValue, draft.defaultValue);
        expect(converted.defaultsToNull, draft.defaultsToNull);
      });
    }

    test('requires the id and the title', () {
      final inputs = {for (final a in field().inputs) a.name: a.type};

      expect(inputs['id'], isA<GraphQLNonNullableType<dynamic, dynamic>>());
      expect(inputs['title'], isA<GraphQLNonNullableType<dynamic, dynamic>>());
    });

    test('returns a required Beacon', () {
      final type = field().type;

      expect(type, isA<GraphQLNonNullableType<dynamic, dynamic>>());
      expect(
        (type as GraphQLNonNullableType<dynamic, dynamic>).ofType.name,
        'Beacon',
      );
    });
  });
}
