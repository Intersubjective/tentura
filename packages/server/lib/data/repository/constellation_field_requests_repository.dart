import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/constellation/constellation_field_selection.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/port/constellation_field_requests_port.dart';

import '../database/tentura_db.dart';
import 'constellation_field_repository.dart';

@LazySingleton(
  as: ConstellationFieldRequestsPort,
  env: [Environment.dev, Environment.prod],
)
final class ConstellationFieldRequestsRepository
    implements ConstellationFieldRequestsPort {
  ConstellationFieldRequestsRepository(this._database);

  final TenturaDb _database;

  @override
  Future<List<ConstellationRequestRecord>> discoverableRequestsByIds({
    required String viewerId,
    required Set<String> beaconIds,
    required ConstellationFieldMembershipFilters filters,
  }) async {
    final ids = [
      for (final id in beaconIds)
        if (id.trim().isNotEmpty) id,
    ]..sort();
    if (viewerId.trim().isEmpty || ids.isEmpty) {
      return const [];
    }
    final capped = ids.length > kConstellationFieldRequestsByIdsCap
        ? ids.sublist(0, kConstellationFieldRequestsByIdsCap)
        : ids;
    final statuses = constellationFieldBeaconStatuses(
      showClosed: filters.showClosed,
    ).toList()..sort();
    final participation = filters.participatedOnly
        ? constellationViewerParticipatesSql(
            viewerParam: r'$1',
            beaconAlias: 'b',
          )
        : null;
    // The same row predicates as the FULL discoverable scan; readability is
    // decided set-wise for the candidates that pass them.
    final rows = await _database
        .customSelect(
          '''
WITH candidates AS (
  SELECT b.id
  FROM public.beacon b
  WHERE b.id = ANY(\$2::text[])
    AND b.user_id <> \$1
    AND b.is_discoverable
    AND b.kind = 0
    AND b.status = ANY(\$3::int[])
    AND b.published_at IS NOT NULL
    AND NOT public.block_hides(\$1, b.user_id)
    ${participation == null ? '' : 'AND ($participation)'}
)
SELECT $constellationRequestSelectColumns
FROM public.beacon b
LEFT JOIN public.image cover ON cover.id = b.cover_thumb_image_id
WHERE b.id IN (
  SELECT public.beacon_readable_ids(
    \$1,
    ARRAY(SELECT c.id FROM candidates c ORDER BY c.id)
  )
)
ORDER BY b.user_id, b.id
''',
          variables: [
            Variable.withString(viewerId),
            Variable(TypedValue(Type.textArray, capped)),
            Variable(TypedValue(Type.integerArray, statuses)),
          ],
        )
        .get();
    return rows.map(readConstellationRequestRow).toList(growable: false);
  }
}
