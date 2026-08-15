import 'package:test/test.dart';

import 'package:tentura_server/data/repository/forward_candidates_sql.dart';

void main() {
  test('wrap SQL joins user, orders by value MR, and caps at 500', () {
    expect(kForwardCandidatesWrapSql, contains('INNER JOIN public."user"'));
    expect(kForwardCandidatesWrapSql, contains(r'cap_normalize_context($2)'));
    expect(
      kForwardCandidatesWrapSql,
      contains('ORDER BY p.forward_mr DESC, u.display_name, u.id'),
    );
    expect(kForwardCandidatesWrapSql, contains('LIMIT 500'));
    expect(kForwardCandidatesWrapSql, isNot(contains('mr_node_score')));
  });
}
