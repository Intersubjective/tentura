import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../database/tentura_db.dart' hide ConstellationAnchor;

ConstellationAnchorTarget readConstellationAnchorTarget(QueryRow row) {
  final kind = row.read<String>('target_kind');
  final id = row.read<String>('target_id');
  return ConstellationAnchorTarget.tryFromWire(kindWire: kind, targetId: id) ??
      (throw StateError('Invalid stored constellation anchor kind: $kind'));
}

ConstellationAnchor readConstellationAnchor(QueryRow row) =>
    ConstellationAnchor(
      target: readConstellationAnchorTarget(row),
      position: ConstellationAnchorPosition(
        xUnits: row.read<double>('x_units'),
        yUnits: row.read<double>('y_units'),
        coordinateSpaceVersion: row.read<int>('coordinate_space_version'),
      ),
      revision: switch (ConstellationAnchorRevision.parseDecimalString(
        row.read<String>('revision'),
      )) {
        ConstellationAnchorRevisionParsed(:final revision) => revision,
        ConstellationAnchorRevisionMalformed() =>
          ConstellationAnchorRevision.zero,
      },
      placedAt: DateTime.parse(row.read<String>('placed_at')).toUtc(),
    );
