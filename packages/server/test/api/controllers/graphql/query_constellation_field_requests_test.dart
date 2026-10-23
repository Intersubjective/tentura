import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_constellation_field_requests.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/constellation_field_requests_port.dart';
import 'package:tentura_server/domain/use_case/constellation_field_requests_case.dart';
import 'package:tentura_server/env.dart';

final class _Port implements ConstellationFieldRequestsPort {
  String? viewerId;
  Set<String>? ids;
  ConstellationFieldMembershipFilters? filters;

  @override
  Future<List<ConstellationRequestRecord>> discoverableRequestsByIds({
    required String viewerId,
    required Set<String> beaconIds,
    required ConstellationFieldMembershipFilters filters,
  }) async {
    this.viewerId = viewerId;
    ids = beaconIds;
    this.filters = filters;
    return [
      for (final id in beaconIds)
        ConstellationRequestRecord(
          id: id,
          authorId: 'Uauthor',
          title: 't',
          status: 0,
          needs: const [],
          hasCoordinates: false,
          isMine: false,
          viewerHasActiveHelpOffer: false,
          viewerIsRoomParticipant: false,
          viewerHasForwardEdge: false,
          helpOfferCount: 0,
        ),
    ];
  }
}

/// #671: the targeted field Request read takes the viewer from the JWT only,
/// passes the field filters through and refuses oversized id lists.
void main() {
  late _Port port;
  late QueryConstellationFieldRequests query;

  setUp(() {
    port = _Port();
    query = QueryConstellationFieldRequests(
      case_: ConstellationFieldRequestsCase(
        port,
        env: Env(environment: Environment.test),
        logger: Logger('QueryConstellationFieldRequestsTest'),
      ),
    );
  });

  test('is wired in _queries_all.dart', () {
    final source = File(
      'lib/api/controllers/graphql/query/_queries_all.dart',
    ).readAsStringSync();
    expect(source, contains('...QueryConstellationFieldRequests().all'));
  });

  test('rejects a missing JWT', () {
    expect(
      () => query.constellationFieldRequests.resolve!(null, {
        'ids': ['B1'],
      }),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('reads for the JWT viewer with the given filters', () async {
    final result =
        await query.constellationFieldRequests.resolve!(null, {
              kGlobalInputQueryJwt: const JwtEntity(sub: 'Uviewer'),
              'ids': ['B1', 'B2', ''],
              'showClosed': true,
              'participatedOnly': false,
            })
            as List;

    expect(port.viewerId, 'Uviewer');
    expect(port.ids, {'B1', 'B2'});
    expect(port.filters!.showClosed, isTrue);
    expect(result.map((r) => (r as Map)['id']), ['B1', 'B2']);
  });

  test('refuses more ids than the cap', () {
    expect(
      () => query.constellationFieldRequests.resolve!(null, {
        kGlobalInputQueryJwt: const JwtEntity(sub: 'Uviewer'),
        'ids': [
          for (var i = 0; i <= kConstellationFieldRequestsByIdsCap; i++) 'B$i',
        ],
        'showClosed': false,
        'participatedOnly': false,
      }),
      throwsA(isA<ArgumentError>()),
    );
    expect(port.ids, isNull);
  });
}
