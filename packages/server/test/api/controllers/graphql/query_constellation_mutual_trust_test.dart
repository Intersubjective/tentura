import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_constellation_mutual_trust.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/constellation_mutual_trust_port.dart';
import 'package:tentura_server/domain/use_case/constellation_mutual_trust_case.dart';
import 'package:tentura_server/env.dart';

final class _Port implements ConstellationMutualTrustPort {
  _Port(this.edges);

  final List<ConstellationEdgeRecord> edges;
  String? viewerId;
  String? context;
  String? personId;

  @override
  Future<List<ConstellationEdgeRecord>> explicitTrustEdgesOf({
    required String viewerId,
    required String context,
    required String personId,
  }) async {
    this.viewerId = viewerId;
    this.context = context;
    this.personId = personId;
    return edges;
  }
}

ConstellationEdgeRecord _e(String src, String dst, {int tier = 1}) =>
    ConstellationEdgeRecord(src: src, dst: dst, tier: tier);

/// The selected person's two-way explicit trust on the field: the viewer
/// comes from the JWT only, and only pairs with an explicit edge each way
/// count.
void main() {
  late _Port port;
  late QueryConstellationMutualTrust query;

  void build(List<ConstellationEdgeRecord> edges) {
    port = _Port(edges);
    query = QueryConstellationMutualTrust(
      case_: ConstellationMutualTrustCase(
        port,
        env: Env(environment: Environment.test),
        logger: Logger('QueryConstellationMutualTrustTest'),
      ),
    );
  }

  setUp(() => build(const []));

  test('is wired in _queries_all.dart', () {
    final source = File(
      'lib/api/controllers/graphql/query/_queries_all.dart',
    ).readAsStringSync();
    expect(source, contains('...QueryConstellationMutualTrust().all'));
  });

  test('rejects a missing JWT', () {
    expect(
      () => query.constellationMutualTrust.resolve!(null, {'personId': 'Ux'}),
      throwsA(isA<UnauthorizedException>()),
    );
    expect(port.personId, isNull);
  });

  test('returns only two-way explicit partners, in id order', () async {
    build([
      // Mutual, the viewer among them.
      _e('Ux', 'Ub'),
      _e('Ub', 'Ux'),
      _e('Ux', 'Uviewer'),
      _e('Uviewer', 'Ux'),
      _e('Ux', 'Ua'),
      _e('Ua', 'Ux'),
      // One way only, either direction.
      _e('Ux', 'Uout'),
      _e('Uin', 'Ux'),
      // A derived link never counts.
      _e('Ux', 'Ud'),
      _e('Ud', 'Ux', tier: 2),
      // Edges among the partners are not the selected person's.
      _e('Ua', 'Ub'),
      _e('Ub', 'Ua'),
    ]);

    final result = await query.constellationMutualTrust.resolve!(null, {
      kGlobalInputQueryJwt: const JwtEntity(sub: 'Uviewer'),
      'personId': ' Ux ',
    });

    expect(result, ['Ua', 'Ub', 'Uviewer']);
    expect(port.viewerId, 'Uviewer');
    expect(port.personId, 'Ux');
    expect(port.context, kConstellationContext);
  });

  test('a blank person id reads nothing', () async {
    final result = await query.constellationMutualTrust.resolve!(null, {
      kGlobalInputQueryJwt: const JwtEntity(sub: 'Uviewer'),
      'personId': '  ',
    });

    expect(result, isEmpty);
    expect(port.personId, isNull);
  });
}
