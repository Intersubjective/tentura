// Independent wire contract verified against the reported production build:
// git show 11e521c:packages/client/lib/features/like/data/gql/like_user_by_id.graphql
// That build's FriendsCase.removeFriend, ProfileViewCase.removeFriend and
// GraphTrustWriteCase._send all call LikeRemoteRepository.setLike. Its
// _likeUser sends this UserVote operation; Ferry adds root __typename.
// Keep this independent of the current source document so changing both
// callers to a different mutation cannot silently change the test oracle.
const personUntrustMutationDocument = r'''
mutation UserVote($objectId: String!, $amount: Int!) {
  __typename
  userVote(objectId: $objectId, amount: $amount)
}
''';

Map<String, Object> personUntrustMutationRequest(String personId) => {
  'query': personUntrustMutationDocument,
  'operationName': 'UserVote',
  'variables': {'objectId': personId, 'amount': 0},
};
