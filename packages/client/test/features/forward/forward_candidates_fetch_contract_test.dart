import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ForwardCandidatesFetch queries V2 forwardCandidates via UserPublicModel', () {
    final source = File(
      'lib/features/forward/data/gql/forward_candidates_fetch.graphql',
    ).readAsStringSync();
    expect(source, contains('query ForwardCandidatesFetch'));
    expect(source, contains(r'forwardCandidates(context: $context)'));
    expect(source, contains('...UserPublicModel'));
    expect(source, isNot(contains('mutually_visible_users')));
    expect(source, isNot(contains('UserModel')));
  });
}
