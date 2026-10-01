import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/domain/entity/forward_candidate_peer_row.dart';
import 'package:tentura_server/domain/port/forward_candidates_repository_port.dart';

import '../database/tentura_db.dart';
import 'forward_candidates_sql.dart';
import 'mappers/mr_score_value.dart';

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
          forwardMr: mrScoreAsDouble(row.data['forward_mr']),
          reverseMr: mrScoreAsDouble(row.data['reverse_mr']),
          viewerTrusts: row.read<bool>('viewer_explicitly_trusts_subject'),
          trustsViewer: row.read<bool>('subject_explicitly_trusts_viewer'),
        ),
    ];
  }

  @override
  Future<Map<String, List<DateTime>>> fetchRecentOwnForwardTimes({
    required String viewerId,
    required DateTime since,
  }) async {
    if (viewerId.trim().isEmpty) {
      return const {};
    }

    final rows = await _database
        .customSelect(
          'SELECT recipient_id, created_at FROM public.beacon_forward_edge '
          r'WHERE sender_id = $1 AND created_at >= $2',
          variables: [
            Variable.withString(viewerId),
            Variable(TypedValue(Type.timestampTz, since.toUtc())),
          ],
        )
        .get();

    final result = <String, List<DateTime>>{};
    for (final row in rows) {
      result
          .putIfAbsent(row.read<String>('recipient_id'), () => [])
          .add((row.data['created_at']! as DateTime).toUtc());
    }
    return result;
  }
}
