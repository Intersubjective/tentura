import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';
import 'package:tentura_server/domain/evaluation/evaluation_visibility_rules.dart';

Set<(String, String)> _pairSet(List<EvaluationVisibilityPair> v) => {
      for (final p in v) (p.evaluatorId, p.participantId),
    };

ForwardEdgeEntity _edge({
  required String senderId,
  required String recipientId,
}) =>
    ForwardEdgeEntity(
      id: '${senderId}_$recipientId',
      beaconId: 'beacon',
      senderId: senderId,
      recipientId: recipientId,
      createdAt: DateTime.utc(2024, 1, 1),
    );

void main() {
  const author = 'author';
  const c1 = 'committer1';
  const c2 = 'committer2';
  const forwarder = 'forwarder';

  test('author evaluates all non-self; committers evaluate author and each other', () {
    final vis = buildEvaluationVisibility(
      authorId: author,
      participants: const [
        EvaluationVisibilityParticipant(
          userId: author,
          role: EvaluationParticipantRole.author,
        ),
        EvaluationVisibilityParticipant(
          userId: c1,
          role: EvaluationParticipantRole.committer,
        ),
        EvaluationVisibilityParticipant(
          userId: c2,
          role: EvaluationParticipantRole.committer,
        ),
      ],
      latestEdgeToCommitter: {},
    );

    expect(
      _pairSet(vis),
      equals({
        (author, c1),
        (author, c2),
        (c1, author),
        (c1, c2),
        (c2, author),
        (c2, c1),
      }),
    );
  });

  test('committer may evaluate forwarder on path when forwarder is not author', () {
    final vis = buildEvaluationVisibility(
      authorId: author,
      participants: const [
        EvaluationVisibilityParticipant(
          userId: author,
          role: EvaluationParticipantRole.author,
        ),
        EvaluationVisibilityParticipant(
          userId: c1,
          role: EvaluationParticipantRole.committer,
        ),
        EvaluationVisibilityParticipant(
          userId: forwarder,
          role: EvaluationParticipantRole.forwarder,
        ),
      ],
      latestEdgeToCommitter: {
        c1: _edge(senderId: forwarder, recipientId: c1),
      },
    );

    expect(_pairSet(vis), containsAll([(c1, forwarder), (forwarder, c1)]));
    expect(_pairSet(vis), contains((c1, author)));
    expect(_pairSet(vis), contains((forwarder, author)));
  });

  test('forwarder evaluates author and committers they forwarded toward', () {
    final vis = buildEvaluationVisibility(
      authorId: author,
      participants: const [
        EvaluationVisibilityParticipant(
          userId: author,
          role: EvaluationParticipantRole.author,
        ),
        EvaluationVisibilityParticipant(
          userId: c1,
          role: EvaluationParticipantRole.committer,
        ),
        EvaluationVisibilityParticipant(
          userId: forwarder,
          role: EvaluationParticipantRole.forwarder,
        ),
      ],
      latestEdgeToCommitter: {
        c1: _edge(senderId: forwarder, recipientId: c1),
      },
    );

    expect(_pairSet(vis), containsAll([(forwarder, author), (forwarder, c1)]));
  });

  test('no self edges', () {
    final vis = buildEvaluationVisibility(
      authorId: author,
      participants: const [
        EvaluationVisibilityParticipant(
          userId: author,
          role: EvaluationParticipantRole.author,
        ),
      ],
      latestEdgeToCommitter: {},
    );

    expect(vis, isEmpty);
  });
}
