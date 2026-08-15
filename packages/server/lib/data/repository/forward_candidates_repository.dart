import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/forward_candidate_peer_row.dart';
import 'package:tentura_server/domain/port/forward_candidates_repository_port.dart';

import '../database/tentura_db.dart';
import 'forward_candidates_sql.dart';

@LazySingleton(as: ForwardCandidatesRepositoryPort)
class ForwardCandidatesRepository implements ForwardCandidatesRepositoryPort {
  ForwardCandidatesRepository(this._database);

  final TenturaDb _database;

  @override
  Future<List<ForwardCandidatePeerRow>> fetchVisiblePeers({
    required String viewerId,
    required String context,
  }) async {
    if (viewerId.trim().isEmpty) {
      return const [];
    }

    final rows = await _database
        .customSelect(
          kForwardCandidatesWrapSql,
          variables: [
            Variable.withString(viewerId),
            Variable.withString(context),
          ],
        )
        .get();

    return [
      for (final row in rows)
        ForwardCandidatePeerRow(
          peerId: row.read<String>('peer_id'),
          forwardMr: _asDouble(row.data['forward_mr']),
          reverseMr: _asDouble(row.data['reverse_mr']),
          viewerTrusts: row.read<bool>('viewer_explicitly_trusts_subject'),
          trustsViewer: row.read<bool>('subject_explicitly_trusts_viewer'),
        ),
    ];
  }

  static double _asDouble(Object? value) {
    if (value == null) {
      return 0;
    }
    if (value is num) {
      return value.toDouble();
    }
    throw StateError('Expected num, got ${value.runtimeType}');
  }
}
