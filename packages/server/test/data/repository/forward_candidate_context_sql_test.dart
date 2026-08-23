import 'package:test/test.dart';
import 'package:tentura_server/data/repository/forward_candidate_context_sql.dart';

void main() {
  test('uses one authorized capped MeritRank snapshot', () {
    expect(
      kForwardCandidateContextSql,
      contains('WITH params AS MATERIALIZED'),
    );
    expect(
      kForwardCandidateContextSql,
      contains('person_visibility_peers('),
    );
    expect(kForwardCandidateContextSql, contains(r'cap_normalize_context($3'));
    expect(kForwardCandidateContextSql, contains('public.mr_graph('));
    expect(kForwardCandidateContextSql, contains('true,'));
    expect(kForwardCandidateContextSql, contains('0,'));
    expect(kForwardCandidateContextSql, contains('100'));
    expect(
      RegExp(
        r'block_hides\(a\.viewer_id, e\.(src|dst)\)',
      ).allMatches(kForwardCandidateContextSql).length,
      2,
    );
  });
}
