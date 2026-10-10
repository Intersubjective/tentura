import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_constellation_anchor.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura_server/env.dart';

/// Never called: tests only inspect the declared schema.
final class _UnusedRepository implements ConstellationAnchorRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('schema-only test');
}

void main() {
  late MutationConstellationAnchor mutation;

  setUp(() {
    mutation = MutationConstellationAnchor(
      constellationAnchorCase: ConstellationAnchorCase(
        _UnusedRepository(),
        env: Env(environment: Environment.test),
        logger: Logger('ConstellationAnchorsApplyAckOnlyTest'),
      ),
    );
  });

  group('anchor batch mutation acknowledgement contract', () {
    test('accepts only anchor operations', () {
      final argNames = mutation.constellationAnchorsApply.inputs
          .map((input) => input.name)
          .toSet();
      expect(argNames, {'ops'});
    });

    test('returns revisions and operation results without a projection', () {
      final names = gqlTypeConstellationAnchorsApplyResult.fields
          .map((field) => field.name)
          .toSet();
      expect(names, {'beforeRevision', 'afterRevision', 'results'});
    });

    test('each operation result reports whether it was replayed', () {
      final replayed = gqlTypeConstellationAnchorOpResult.fields.where(
        (field) => field.name == 'replayed',
      );
      expect(replayed, hasLength(1));
    });

    test('each operation result declares the stored anchor object type', () {
      final anchors = gqlTypeConstellationAnchorOpResult.fields.where(
        (field) => field.name == 'anchor',
      );
      expect(anchors, hasLength(1));
      final declaredType = anchors.single.type;
      final rowType = declaredType is GraphQLNonNullableType
          ? declaredType.ofType
          : declaredType;
      expect(rowType, isA<GraphQLObjectType>());
      expect(rowType, same(gqlTypeConstellationAnchor));
    });
  });
}
